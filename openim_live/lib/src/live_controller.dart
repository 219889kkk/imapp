import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_live_alert/flutter_openim_live_alert.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../openim_live.dart';
import 'utils/call_audio_keepalive.dart';

mixin OpenIMLive {
  final signalingSubject = PublishSubject<CallEvent>();

  void invitationCancelled(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beCanceled, info));
  }

  void inviteeAccepted(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beAccepted, info));
  }

  void inviteeRejected(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beRejected, info));
  }

  void receiveNewInvitation(SignalingInfo info) {
    final roomID = info.invitation?.roomID?.trim() ?? '';
    _pruneEndedRooms();
    if (roomID.isNotEmpty && _endedRoomUntilMs.containsKey(roomID)) {
      Logger.print('ignore invite: room already ended $roomID');
      return;
    }
    // Already in a call: never re-open invite UI (fixes looping invite sheets).
    if (isBusy) {
      final current = OpenIMLiveClient().currentRoomID;
      if (current != null && current == roomID) {
        // Same room — attach UI if lock-screen join has no overlay yet.
        if (!OpenIMLiveClient().hasOverlay) {
          _presentCallUi(info, fromHeadless: true);
        } else {
          Logger.print('ignore invite: already in same room $roomID');
        }
        return;
      }
      Logger.print(
          'ignore invite: busy current=$current incoming=$roomID');
      return;
    }
    signalingSubject.add(CallEvent(CallState.beCalled, info));
  }

  void beHangup(SignalingInfo info) {
    final roomID = info.invitation?.roomID;
    _markRoomEnded(roomID);
    signalingSubject.add(CallEvent(CallState.beHangup, info));
  }

  void _markRoomEnded(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    _endedRoomUntilMs[id] = DateTime.now().millisecondsSinceEpoch + _endedRoomTtlMs;
  }

  void _pruneEndedRooms() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _endedRoomUntilMs.removeWhere((_, until) => until <= now);
  }

  bool _isRoomEnded(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    _pruneEndedRooms();
    return _endedRoomUntilMs.containsKey(id);
  }

  /// Tear down in-app + system call UI for [roomID] (peer hangup / cancel).
  void _terminateCallUi(String? roomID) {
    _markRoomEnded(roomID);
    _clearPickupCache();
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
    _autoPickup = false;
    _beCalledEvent = null;
    _activeCallSignaling = null;
    _callSessionGen++; // invalidate in-flight headless accept/present
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    unawaited(
        VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
    // Clear any leftover lock-screen / notification CallKit (id mismatch).
    unawaited(
        VoipCallkitController.toOrNull?.endAllCalls() ?? Future.value());
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }
  }

  final backgroundSubject = PublishSubject<bool>();

  final insertSignalingMessageSubject = PublishSubject<CallEvent>();

  Function(SignalingMessageEvent)? onSignalingMessage;
  final roomParticipantDisconnectedSubject = PublishSubject<RoomCallingInfo>();
  final roomParticipantConnectedSubject = PublishSubject<RoomCallingInfo>();

  bool _isRunningBackground = false;

  CallEvent? _beCalledEvent;
  /// Signaling for the active headless/lock-screen call (for UI attach after unlock).
  SignalingInfo? _activeCallSignaling;
  /// Bumped on hangup/terminate so late async accept cannot reopen UI.
  int _callSessionGen = 0;

  bool _autoPickup = false;

  /// Shared in-flight accept+join (CallKit, notification, in-app — one pipeline).
  Future<SignalingCertificate>? _acceptJoinInFlight;
  String? _acceptJoinRoomID;

  /// Shared in-flight CallKit / UI pickup so lock-screen accept can send
  /// `callingAccept` before Flutter overlay exists (avoids caller timeout).
  Future<SignalingCertificate>? _pickupInFlight;
  String? _pickupRoomID;
  SignalingCertificate? _pickupCertCache;
  String? _pickupCertRoomID;

  /// Recently ended roomIDs — ignore late/synced invites (WeChat-like).
  final Map<String, int> _endedRoomUntilMs = {};
  static const _endedRoomTtlMs = 120 * 1000;
  final _ring = 'assets/audio/live_ring.wav';
  final _audioPlayer = AudioPlayer(
    // Avoid fighting LiveKit's playAndRecord session (reduces connect-time noise).
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );
  int _ringPlayGen = 0;

  bool get isBusy => OpenIMLiveClient().isBusy;

  /// Tear down all call UI/ringtone on logout — no further incoming alerts.
  void terminateAllCallsOnLogout() {
    _terminateCallUi(null);
  }

  onCloseLive() {
    if (identical(
        PackageBridge.handleCallNotificationAction, _handleCallNotificationAction)) {
      PackageBridge.handleCallNotificationAction = null;
    }
    if (identical(PackageBridge.onCallKitAccept, _onCallKitAccept)) {
      PackageBridge.onCallKitAccept = null;
    }
    if (identical(PackageBridge.onCallKitDecline, _onCallKitDecline)) {
      PackageBridge.onCallKitDecline = null;
    }
    if (identical(PackageBridge.onCallKitEnded, _onCallKitEnded)) {
      PackageBridge.onCallKitEnded = null;
    }
    _clearPickupCache();
    signalingSubject.close();
    backgroundSubject.close();
    roomParticipantDisconnectedSubject.close();
    roomParticipantConnectedSubject.close();
    _stopSound();
  }

  onInitLive() async {
    PackageBridge.handleCallNotificationAction = _handleCallNotificationAction;
    PackageBridge.onCallKitAccept = _onCallKitAccept;
    PackageBridge.onCallKitDecline = _onCallKitDecline;
    PackageBridge.onCallKitEnded = _onCallKitEnded;
    _signalingListener();
    _insertSignalingMessageListener();
    _bindLiveAlertButtons();
    backgroundSubject.listen((background) {
      _isRunningBackground = background;
      if (!_isRunningBackground) {
        FlutterOpenimLiveAlert.closeLiveAlert();
        if (_beCalledEvent != null) {
          final pending = _beCalledEvent!;
          _beCalledEvent = null;
          final pendingRoom = pending.data.invitation?.roomID;
          if (_isRoomEnded(pendingRoom)) {
            Logger.print('skip foreground restore: room ended $pendingRoom');
          } else if (OpenIMLiveClient().hasMediaFor(pendingRoom)) {
            // Already answered on lock-screen — attach UI, keep CallKit connected.
            if (!_isRoomEnded(pendingRoom)) {
              _presentCallUi(pending.data, fromHeadless: true);
            }
          } else {
            // Unanswered: drop system incoming UI so only in-app Accept remains.
            unawaited(
                VoipCallkitController.toOrNull?.endCall(pendingRoom) ??
                    Future.value());
            PackageBridge.clearCallNotification?.call();
            signalingSubject.add(pending);
          }
        } else {
          final active = _activeCallSignaling;
          final activeRoom = active?.invitation?.roomID;
          if (active != null &&
              !_isRoomEnded(activeRoom) &&
              OpenIMLiveClient().isBusy &&
              OpenIMLiveClient().hasMediaFor(activeRoom) &&
              !OpenIMLiveClient().hasOverlay) {
            _presentCallUi(active, fromHeadless: true);
          }
        }
      }
    });

    roomParticipantDisconnectedSubject.listen((info) {
      if (null == info.participant || info.participant!.length == 1) {
        final roomID = info.invitation?.roomID;
        _terminateCallUi(roomID);
      }
    });
  }

  void _onCallKitAccept(SignalingInfo signaling) {
    _autoPickup = true;
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    final roomID = signaling.invitation?.roomID;
    if (roomID != null && roomID.isNotEmpty) {
      unawaited(
          VoipCallkitController.toOrNull?.setConnected(roomID) ?? Future.value());
    }
    unawaited(_acceptIncomingCall(signaling, requestPermissions: false));
  }

  /// Single callee accept pipeline: permissions → accept signal → token → LiveKit.
  /// Safe to call from CallKit, notification, live-alert, and in-app Accept.
  Future<SignalingCertificate> acceptIncomingCall(
    SignalingInfo signaling, {
    bool requestPermissions = true,
    bool presentUiAfter = true,
  }) async {
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    if (roomID.isEmpty) {
      throw StateError('acceptIncomingCall: empty roomID');
    }
    if (_isRoomEnded(roomID)) {
      throw StateError('acceptIncomingCall: room ended $roomID');
    }

    final client = OpenIMLiveClient();
    if (client.hasMediaFor(roomID) && client.mediaCertificate != null) {
      Logger.print('acceptIncomingCall: reuse media roomID=$roomID');
      if (presentUiAfter) {
        _presentCallUi(signaling, fromHeadless: true);
      }
      return client.mediaCertificate!;
    }

    if (_acceptJoinInFlight != null && _acceptJoinRoomID == roomID) {
      final cert = await _acceptJoinInFlight!;
      if (presentUiAfter && !_isRoomEnded(roomID)) {
        _presentCallUi(signaling, fromHeadless: true);
      }
      return cert;
    }

    final gen = _callSessionGen;
    _activeCallSignaling = signaling;
    OpenIMLiveClient().onTapHangup = (duration, isPositive) => onTapHangup(
          signaling..userID = OpenIM.iMManager.userID,
          duration,
          isPositive,
        );

    final future = _runAcceptJoin(
      signaling,
      gen: gen,
      requestPermissions: requestPermissions,
    );
    _acceptJoinInFlight = future;
    _acceptJoinRoomID = roomID;
    try {
      final cert = await future;
      if (presentUiAfter && gen == _callSessionGen && !_isRoomEnded(roomID)) {
        _presentCallUi(signaling, fromHeadless: true);
      }
      return cert;
    } finally {
      if (_acceptJoinRoomID == roomID) {
        _acceptJoinInFlight = null;
        _acceptJoinRoomID = null;
      }
    }
  }

  Future<void> _acceptIncomingCall(
    SignalingInfo signaling, {
    bool requestPermissions = false,
  }) async {
    try {
      await acceptIncomingCall(
        signaling,
        requestPermissions: requestPermissions,
        presentUiAfter: true,
      );
    } catch (e, s) {
      Logger.print('acceptIncomingCall failed: $e $s');
    }
  }

  Future<SignalingCertificate> _runAcceptJoin(
    SignalingInfo signaling, {
    required int gen,
    required bool requestPermissions,
  }) async {
    final roomID = signaling.invitation?.roomID;
    final isVideo = signaling.invitation?.mediaType == 'video';
    final callType = isVideo ? CallType.video : CallType.audio;

    if (requestPermissions) {
      final ok = await Permissions.requestCallMedia(needCamera: isVideo);
      if (!ok) throw StateError('media permission denied');
    }

    _stopSound();
    PackageBridge.clearCallNotification?.call();

    if (roomID != null && roomID.isNotEmpty) {
      await CallAudioKeepAlive.instance.start(
        roomID: roomID,
        isVideo: isVideo,
        speakerOn: true,
      );
    }

    final cert =
        await onTapPickup(signaling..userID = OpenIM.iMManager.userID);
    if (gen != _callSessionGen || _isRoomEnded(roomID)) {
      Logger.print('abort accept join after hangup roomID=$roomID');
      if (roomID != null && roomID.isNotEmpty) {
        OpenIMLiveClient().closeByRoomID(roomID);
      } else {
        OpenIMLiveClient().close();
      }
      throw StateError('accept aborted: session ended');
    }

    final liveURL = cert.liveURL?.trim() ?? '';
    final token = cert.token?.trim() ?? '';
    if (liveURL.isEmpty || token.isEmpty) {
      throw StateError(
          'invalid rtc cert roomID=$roomID liveURL=$liveURL tokenLen=${token.length}');
    }

    await OpenIMLiveClient().connectMedia(
      certificate: cert,
      callType: callType,
      speakerOn: true,
      enableCamera: isVideo,
      enableMicrophone: true,
      enableKeepAlive: true,
      onDisconnected: () {
        final id = signaling.invitation?.roomID;
        if (!_isRoomEnded(id)) {
          _terminateCallUi(id);
        }
      },
    );

    if (gen != _callSessionGen || _isRoomEnded(roomID)) {
      Logger.print('abort accept after connect roomID=$roomID');
      if (roomID != null && roomID.isNotEmpty) {
        OpenIMLiveClient().closeByRoomID(roomID);
      } else {
        OpenIMLiveClient().close();
      }
      throw StateError('accept aborted after connect');
    }

    await OpenIMLiveClient().reinforceLockScreenAudio(speakerOn: true);
    Logger.print('accept joined roomID=${cert.roomID} type=$callType');
    return cert;
  }

  /// @deprecated — use acceptIncomingCall.
  Future<void> _headlessAcceptAndJoin(SignalingInfo signaling) =>
      _acceptIncomingCall(signaling, requestPermissions: false);

  /// Show call overlay if Flutter is ready. Safe to call while media already live.
  void _presentCallUi(SignalingInfo signaling, {bool fromHeadless = false}) {
    final roomID = signaling.invitation?.roomID;
    if (_isRoomEnded(roomID)) {
      Logger.print('skip present UI: room ended $roomID');
      return;
    }
    final client = OpenIMLiveClient();
    if (client.hasOverlay) return;

    final mediaType = signaling.invitation?.mediaType;
    final sessionType = signaling.invitation?.sessionType;
    final callType = mediaType == 'audio' ? CallType.audio : CallType.video;
    final callObj = sessionType == ConversationType.single
        ? CallObj.single
        : CallObj.group;
    final overlayContext = Get.overlayContext;
    if (overlayContext == null) {
      // Keep pending so foreground restores UI without interrupting media.
      _beCalledEvent = CallEvent(
        fromHeadless || client.hasMediaFor(roomID)
            ? CallState.calling
            : CallState.beCalled,
        signaling,
      );
      return;
    }

    final mediaReady = client.hasMediaFor(roomID);
    OpenIMLiveClient().start(
      overlayContext,
      callEventSubject: signalingSubject,
      roomID: roomID,
      inviteeUserIDList: signaling.invitation!.inviteeUserIDList!,
      inviterUserID: signaling.invitation!.inviterUserID!,
      groupID: signaling.invitation!.groupID,
      callType: callType,
      callObj: callObj,
      initState: mediaReady ? CallState.calling : CallState.beCalled,
      onSyncUserInfo: onSyncUserInfo,
      onSyncGroupInfo: onSyncGroupInfo,
      onSyncGroupMemberInfo: onSyncGroupMemberInfo,
      autoPickup: mediaReady ? false : _autoPickup,
      onTapPickup: () => acceptIncomingCall(
        signaling..userID = OpenIM.iMManager.userID,
        requestPermissions: true,
        presentUiAfter: false,
      ),
      onTapReject: () => onTapReject(
        signaling..userID = OpenIM.iMManager.userID,
      ),
      onTapHangup: (duration, isPositive) => onTapHangup(
        signaling..userID = OpenIM.iMManager.userID,
        duration,
        isPositive,
      ),
      onError: onError,
      onRoomDisconnected: () => onRoomDisconnected(signaling),
    );
    _beCalledEvent = null;
    _autoPickup = false;
  }

  void _onCallKitDecline(SignalingInfo signaling) {
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    _beCalledEvent = null;
    onTapReject(signaling..userID = OpenIM.iMManager.userID);
  }

  /// Lock-screen / system UI End — must tear down LiveKit + notify peer.
  void _onCallKitEnded(SignalingInfo? signaling) {
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    _beCalledEvent = null;
    _autoPickup = false;

    final info = signaling ?? _activeCallSignaling;
    final roomID =
        info?.invitation?.roomID ?? OpenIMLiveClient().currentRoomID;
    if (roomID != null && roomID.isNotEmpty && _isRoomEnded(roomID)) {
      return;
    }

    final client = OpenIMLiveClient();
    final inCall = client.hasMediaFor(roomID) ||
        client.mediaRoom?.localParticipant != null;

    if (inCall && info != null) {
      Logger.print('CallKit ended active call roomID=$roomID');
      unawaited(onTapHangup(info..userID = OpenIM.iMManager.userID, 0, true));
      return;
    }

    if (info != null && !inCall) {
      Logger.print('CallKit ended before connect roomID=$roomID');
      unawaited(onTapReject(info..userID = OpenIM.iMManager.userID));
      return;
    }

    Logger.print('CallKit ended fallback terminate roomID=$roomID');
    _terminateCallUi(roomID);
  }

  void _handleCallNotificationAction(bool accept) {
    if (accept) {
      _autoPickup = true;
      _stopSound();
      PackageBridge.clearCallNotification?.call();
      final pending = _beCalledEvent;
      if (pending != null) {
        _beCalledEvent = null;
        unawaited(_acceptIncomingCall(pending.data, requestPermissions: false));
      }
      return;
    }
    final pending = _beCalledEvent;
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    if (pending == null) return;
    _beCalledEvent = null;
    onTapReject(pending.data..userID = OpenIM.iMManager.userID);
  }

  void _bindLiveAlertButtons() {
    FlutterOpenimLiveAlert.buttonEvent(
      activityName: 'io.openim.MainActivity',
      onAccept: () {
        _autoPickup = true;
        final pending = _beCalledEvent;
        if (pending != null) {
          unawaited(_acceptIncomingCall(pending.data, requestPermissions: false));
        }
      },
      onReject: () {
        final pending = _beCalledEvent;
        _beCalledEvent = null;
        _stopSound();
        PackageBridge.clearCallNotification?.call();
        if (pending != null) {
          onTapReject(pending.data..userID = OpenIM.iMManager.userID);
        }
      },
    );
  }

  Stream<CallEvent> get _stream => signalingSubject
      .stream /*.where((event) => LiveClient.dispatchSignaling(event))*/;

  _signalingListener() => _stream.listen(
        (event) async {
          if (!SessionGuard.shouldNotify) return;
          final roomID = event.data.invitation?.roomID;
          if (event.state != CallState.beCalled) {
            _beCalledEvent = null;
            FlutterOpenimLiveAlert.closeLiveAlert();
            PackageBridge.clearCallNotification?.call();
            // Stop ring on any non-ringing state (accept/hangup/etc.).
            if (event.state == CallState.beAccepted ||
                event.state == CallState.beRejected ||
                event.state == CallState.beCanceled ||
                event.state == CallState.beHangup) {
              unawaited(_stopSound());
            }
          }
          if (event.state == CallState.beCalled) {
            unawaited(_prefetchPickupToken(event.data.invitation?.roomID));
            if (!_autoPickup) {
              _playSound();
            } else {
              _stopSound();
            }
            final mediaType = event.data.invitation!.mediaType;
            final callType =
                mediaType == 'audio' ? CallType.audio : CallType.video;

            // Background: show CallKit / overlay. Skip when user already
            // accepted from CallKit (_autoPickup) — go straight to LiveKit UI.
            if (_isRunningBackground && !_autoPickup) {
              _beCalledEvent = event;
              if (Platform.isAndroid) {
                // Prefer flutter_callkit_incoming full-screen / call notification.
                final voip = VoipCallkitController.toOrNull;
                if (voip != null) {
                  String caller = event.data.invitation?.inviterUserID ?? '';
                  try {
                    final uid = event.data.invitation?.inviterUserID;
                    if (uid != null && uid.isNotEmpty) {
                      final list = await OpenIM.iMManager.userManager
                          .getUsersInfo(userIDList: [uid]);
                      caller = list.firstOrNull?.simpleUserInfo.nickname ??
                          caller;
                    }
                  } catch (_) {}
                  await voip.showIncoming(event.data, nameCaller: caller);
                } else {
                  final hasOverlay =
                      await Permissions.checkSystemAlertWindow();
                  if (!hasOverlay) {
                    await Permissions.request([Permission.systemAlertWindow]);
                  }
                  await FlutterOpenimLiveAlert.showLiveAlert(
                    title: callType == CallType.video
                        ? StrRes.videoCallNotificationTitle
                        : StrRes.voiceCallNotificationTitle,
                    rejectText: StrRes.reject,
                    acceptText: StrRes.pickUp,
                  );
                }
              } else if (Platform.isIOS) {
                // Prefer CallKit over in-app alert when backgrounded.
                final voip = VoipCallkitController.toOrNull;
                if (voip != null && !voip.ownsIncomingUi) {
                  await voip.showIncoming(event.data);
                }
              }
              // Keep pending invite; CallKit / foreground restores UI.
              return;
            }
            _beCalledEvent = null;
            final overlayContext = Get.overlayContext;
            if (overlayContext == null) {
              _beCalledEvent = event;
              return;
            }
            // One answer surface: always use shared presenter.
            PackageBridge.clearCallNotification?.call();
            FlutterOpenimLiveAlert.closeLiveAlert();
            _presentCallUi(event.data, fromHeadless: _autoPickup);
            _autoPickup = false;
          } else if (event.state == CallState.beRejected) {
            insertSignalingMessageSubject.add(event);
            _terminateCallUi(roomID);
          } else if (event.state == CallState.beHangup) {
            // Peer hung up — force close LiveKit + CallKit (WeChat-like).
            _terminateCallUi(roomID);
          } else if (event.state == CallState.beCanceled) {
            insertSignalingMessageSubject.add(event);
            _terminateCallUi(roomID);
          } else if (event.state == CallState.beAccepted) {
            await _stopSound();
            // Inviter: backup path if LiveKit event missed — unmute + subscribe.
            unawaited(OpenIMLiveClient().ensureCallKeepAlive(speakerOn: true));
            unawaited(OpenIMLiveClient().ensureMediaAudible(
              speakerOn: true,
              forceRestartMic: true,
            ));
          } else if (event.state == CallState.otherReject ||
              event.state == CallState.otherAccepted) {
            await _stopSound();
            if (!existActiveCallFor(roomID)) {
              _terminateCallUi(roomID);
            }
          } else if (event.state == CallState.timeout) {
            insertSignalingMessageSubject.add(event);
            _terminateCallUi(roomID);
            final sessionType = event.data.invitation!.sessionType;
            if (sessionType == 1) {
              onTimeoutCancelled(event.data);
            }
          }
        },
      );

  bool existActiveCallFor(String? roomID) {
    if (!isBusy) return false;
    final current = OpenIMLiveClient().currentRoomID;
    if (roomID == null || roomID.isEmpty) return isBusy;
    return current == roomID;
  }
  _insertSignalingMessageListener() {
    insertSignalingMessageSubject.listen((value) {
      _insertMessage(
        state: value.state,
        signalingInfo: value.data,
        duration: value.fields ?? 0,
      );
    });
  }

  call({
    required CallObj callObj,
    required CallType callType,
    CallState callState = CallState.call,
    String? roomID,
    String? inviterUserID,
    required List<String> inviteeUserIDList,
    String? groupID,
    SignalingCertificate? credentials,
  }) async {
    final mediaType = callType == CallType.audio ? 'audio' : 'video';
    final sessionType = callObj == CallObj.single ? 1 : 3;
    inviterUserID ??= OpenIM.iMManager.userID;

    final signal = SignalingInfo(
      userID: inviterUserID,
      invitation: InvitationInfo(
        inviterUserID: inviterUserID,
        inviteeUserIDList: inviteeUserIDList,
        roomID: roomID ?? groupID ?? const Uuid().v4(),
        timeout: 30,
        mediaType: mediaType,
        sessionType: sessionType,
        platformID: IMUtils.getPlatform(),
        groupID: groupID,
      ),
    );

    OpenIMLiveClient().start(
      Get.overlayContext!,
      callEventSubject: signalingSubject,
      inviterUserID: inviterUserID,
      groupID: groupID,
      inviteeUserIDList: inviteeUserIDList,
      callObj: callObj,
      callType: callType,
      initState: callState,
      onDialSingle: () => onDialSingle(signal),
      onDialGroup: () => onDialGroup(signal),
      onJoinGroup: () => Future.value(credentials!),
      onTapCancel: () => onTapCancel(signal),
      onTapHangup: (duration, isPositive) => onTapHangup(
        signal,
        duration,
        isPositive,
      ),
      onSyncUserInfo: onSyncUserInfo,
      onSyncGroupInfo: onSyncGroupInfo,
      onSyncGroupMemberInfo: onSyncGroupMemberInfo,
      onWaitingAccept: () {
        if (callObj == CallObj.single) _playSound();
      },
      onBusyLine: onBusyLine,
      onStartCalling: () {
        _stopSound();
      },
      onError: onError,
      onRoomDisconnected: () => onRoomDisconnected(signal),
      onClose: _stopSound,
    );
  }

  onError(error, stack) {
    Logger.print('onError=====> $error $stack');
    // Duplicate Accept (CallKit + in-app / notification) can throw on the
    // second path while the first already joined — never kill a live call.
    final client = OpenIMLiveClient();
    if (client.mediaRoom?.localParticipant != null) {
      Logger.print('onError ignored: media already connected');
      unawaited(client.ensureMediaAudible(speakerOn: true, forceRestartMic: false));
      return;
    }
    client.close();
    _stopSound();
    // HttpUtil already toasted API failures like (errCode, errMsg).
    if (error is (int, String?)) {
      return;
    }
    if (error is PlatformException) {
      final code = int.tryParse(error.code);
      if (code == SDKErrorCode.hasBeenBlocked) {
        IMViews.showToast(StrRes.callFail);
        return;
      }
    }
    final msg = error?.toString() ?? '';
    if (msg.contains('permission') || msg.contains('Permission')) {
      return;
    }
    IMViews.showToast(StrRes.networkError);
  }

  onRoomDisconnected(SignalingInfo signalingInfo) {}

  Future<SignalingCertificate> onDialSingle(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingInvite,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final isVideo = signaling.invitation!.mediaType == 'video';
    final invitation = signaling.invitation!;
    OpenIM.iMManager.messageManager.sendMessage(
      message: message,
      offlinePushInfo:
          Config.offlineCallPushInfo(isVideo: isVideo, invitation: invitation),
      userID: invitation.inviteeUserIDList!.first,
      // Keep WS delivery when online; also allow offline push when away.
      isOnlineOnly: false,
    );
    // iOS CallKit: after invite(200), ask chat server to fire APNs VoIP.
    unawaited(_triggerVoipPush(signaling, action: 'invite'));
    final certificate = await Apis.getTokenForRTC(
        invitation.roomID!, OpenIM.iMManager.userID);

    return certificate;
  }

  Future<SignalingCertificate> onDialGroup(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingInvite,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final isVideo = signaling.invitation!.mediaType == 'video';
    final invitation = signaling.invitation!;
    for (final userID in invitation.inviteeUserIDList!) {
      OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo:
            Config.offlineCallPushInfo(isVideo: isVideo, invitation: invitation),
        userID: userID,
        isOnlineOnly: false,
      );
    }
    unawaited(_triggerVoipPush(signaling, action: 'invite'));
    final certificate = await Apis.getTokenForRTC(
      invitation.roomID!,
      OpenIM.iMManager.userID,
    );

    return certificate;
  }

  Future<void> _triggerVoipPush(
    SignalingInfo signaling, {
    required String action,
    List<String>? toUserIDs,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final inv = signaling.invitation;
    if (inv == null) return;
    final targets = (toUserIDs ?? inv.inviteeUserIDList ?? const [])
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (targets.isEmpty) return;
    String nickname = '';
    try {
      nickname = OpenIM.iMManager.userInfo.nickname?.trim() ?? '';
    } catch (_) {}
    await Apis.voipPush(
      action: action,
      inviteeUserIDList: targets,
      roomID: inv.roomID ?? '',
      inviterUserID: inv.inviterUserID ?? OpenIM.iMManager.userID,
      mediaType: inv.mediaType ?? 'audio',
      nickname: nickname,
      sessionType: inv.sessionType,
      groupID: inv.groupID,
      timeout: inv.timeout ?? 60,
    );
  }

  Future<void> _prefetchPickupToken(String? roomID) async {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    if (_pickupCertRoomID == id && _pickupCertCache != null) return;
    if (_pickupInFlight != null && _pickupRoomID == id) return;
    try {
      final cert = await Apis.getTokenForRTC(id, OpenIM.iMManager.userID);
      _pickupCertCache = cert;
      _pickupCertRoomID = id;
      Logger.print('prefetch rtc token ok roomID=$id');
    } catch (e, s) {
      Logger.print('prefetch rtc token failed roomID=$id: $e $s');
    }
  }

  Future<SignalingCertificate> onTapPickup(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID;
    if (roomID != null &&
        roomID.isNotEmpty &&
        _pickupCertRoomID == roomID &&
        _pickupCertCache != null) {
      return _pickupCertCache!;
    }
    if (roomID != null &&
        roomID.isNotEmpty &&
        _pickupInFlight != null &&
        _pickupRoomID == roomID) {
      return _pickupInFlight!;
    }

    final future = _doPickup(signaling);
    if (roomID != null && roomID.isNotEmpty) {
      _pickupInFlight = future;
      _pickupRoomID = roomID;
    }
    try {
      final cert = await future;
      if (roomID != null && roomID.isNotEmpty) {
        _pickupCertCache = cert;
        _pickupCertRoomID = roomID;
      }
      return cert;
    } finally {
      if (_pickupRoomID == roomID) {
        _pickupInFlight = null;
        _pickupRoomID = null;
      }
    }
  }

  void _clearPickupCache() {
    _pickupInFlight = null;
    _pickupRoomID = null;
    _pickupCertCache = null;
    _pickupCertRoomID = null;
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
  }

  Future<SignalingCertificate> _doPickup(SignalingInfo signaling) async {
    _beCalledEvent = null; // ios bug
    _stopSound();
    final data = {
      'customType': CustomMessageType.callingAccept,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    // Persist accept so inviter still gets it if briefly offline / Doze.
    OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: signaling.invitation!.inviterUserID,
        // Online-only accept reaches waiting caller faster than offline sync.
        isOnlineOnly: true);
    final certificate = await Apis.getTokenForRTC(
        signaling.invitation!.roomID!, OpenIM.iMManager.userID);

    return certificate;
  }

  onTapReject(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID;
    if (OpenIMLiveClient().hasMediaFor(roomID)) {
      _terminateCallUi(roomID);
    } else {
      _markRoomEnded(roomID);
      _clearPickupCache();
    }
    _stopSound();
    insertSignalingMessageSubject.add(CallEvent(CallState.reject, signaling));

    final data = {
      'customType': CustomMessageType.callingReject,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserID =
        signaling.invitation!.inviterUserID == OpenIM.iMManager.userID
            ? signaling.invitation!.inviteeUserIDList!.first
            : signaling.invitation!.inviterUserID;
    final result = await OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: recvUserID,
        isOnlineOnly: false);
    if (recvUserID != null && recvUserID.isNotEmpty) {
      unawaited(_triggerVoipPush(
        signaling,
        action: 'reject',
        toUserIDs: [recvUserID],
      ));
    }
    unawaited(
        VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
    unawaited(
        VoipCallkitController.toOrNull?.endAllCalls() ?? Future.value());
    return result;
  }
  onTapCancel(SignalingInfo signaling) async {
    _clearPickupCache();
    _stopSound();
    insertSignalingMessageSubject.add(CallEvent(CallState.cancel, signaling));

    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserIDList = _recvUserIDList(signaling);
    for (final userID in recvUserIDList) {
      OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: userID,
          // Critical: online-only cancel is dropped when callee is Doze /
          // WS-dead while CallKit still rings → ringtone never stops.
          isOnlineOnly: false);
    }
    final peers = _recvUserIDList(signaling);
    unawaited(
        _triggerVoipPush(signaling, action: 'cancel', toUserIDs: peers));
    _terminateCallUi(signaling.invitation?.roomID);
    return true;
  }

  onTimeoutCancelled(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');

    OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: signaling.invitation!.inviterUserID,
        isOnlineOnly: false);
    unawaited(_triggerVoipPush(
      signaling,
      action: 'cancel',
      toUserIDs: [
        if (signaling.invitation?.inviterUserID != null)
          signaling.invitation!.inviterUserID!,
      ],
    ));
    return true;
  }

  onTapHangup(SignalingInfo signaling, int duration, bool isPositive) async {
    final roomID = signaling.invitation?.roomID;
    // Mark ended + bump session gen FIRST so late invite/accept cannot reopen UI.
    _markRoomEnded(roomID);
    _callSessionGen++;
    _activeCallSignaling = null;
    _beCalledEvent = null;
    _autoPickup = false;
    _clearPickupCache();
    if (isPositive) {
      final data = {
        'customType': CustomMessageType.callingHungup,
        'data': signaling.invitation!.toJson()
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      final recvUserIDList = _recvUserIDList(signaling);
      for (final userID in recvUserIDList) {
        OpenIM.iMManager.messageManager.sendMessage(
            message: message,
            offlinePushInfo: OfflinePushInfo(),
            userID: userID,
            isOnlineOnly: false);
      }
      // End peer CallKit even if IM is slow / app backgrounded.
      unawaited(_triggerVoipPush(
        signaling,
        action: 'hungup',
        toUserIDs: recvUserIDList,
      ));
    }
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    unawaited(
        VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
    unawaited(
        VoipCallkitController.toOrNull?.endAllCalls() ?? Future.value());
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }

    insertSignalingMessageSubject.add(CallEvent(
      CallState.hangup,
      signaling,
      fields: duration,
    ));
  }
  onBusyLine() {
    _stopSound();
    IMViews.showToast(StrRes.busyVideoCallHint);
  }

  onJoin() {}

  Future<UserInfo?> onSyncUserInfo(userID) async {
    var list = await OpenIM.iMManager.userManager.getUsersInfo(
      userIDList: [userID],
    );

    return list.firstOrNull?.simpleUserInfo;
  }

  Future<GroupInfo?> onSyncGroupInfo(groupID) async {
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID],
    );
    return list.firstOrNull;
  }

  Future<List<GroupMembersInfo>> onSyncGroupMemberInfo(
      groupID, userIDList) async {
    var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
      groupID: groupID,
      userIDList: userIDList,
    );
    return list;
  }

  void _playSound() async {
    final gen = ++_ringPlayGen;
    try {
      if (_audioPlayer.playerState.playing) {
        await _audioPlayer.stop();
      }
      if (gen != _ringPlayGen) return;
      await _audioPlayer.setAsset(_ring, package: 'openim_common');
      if (gen != _ringPlayGen) return;
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setVolume(1.0);
      if (gen != _ringPlayGen) return;
      await _audioPlayer.play();
    } catch (e, s) {
      Logger.print('play ring failed: $e $s');
    }
  }

  Future<void> _stopSound() async {
    _ringPlayGen++;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  void _insertMessage({
    required CallState state,
    required SignalingInfo signalingInfo,
    int duration = 0,
  }) async {
    (() async {
      var invitation = signalingInfo.invitation;
      var mediaType = invitation!.mediaType;
      var inviterUserID = invitation.inviterUserID;
      var inviteeUserID = invitation.inviteeUserIDList!.first;
      var groupID = invitation.groupID;
      Logger.print(
          'end calling and insert message state:${state.name}, mediaType:$mediaType, inviterUserID:$inviterUserID, inviteeUserID:$inviteeUserID, groupID:$groupID, duration:$duration',
          functionName: '_insertMessage');
      var message = await OpenIM.iMManager.messageManager.createCallMessage(
        state: state.name,
        type: mediaType!,
        duration: duration,
      );

      String? receiverID;
      if (inviterUserID != OpenIM.iMManager.userID) {
        receiverID = inviterUserID;
      } else {
        receiverID = inviteeUserID;
      }

      var msg = await OpenIM.iMManager.messageManager
          .insertSingleMessageToLocalStorage(
        receiverID: inviteeUserID,
        senderID: inviterUserID,
        message: message..status = 2,
      );

      onSignalingMessage?.call(SignalingMessageEvent(msg, 1, receiverID, null));
    })();
  }

  List<String> _recvUserIDList(SignalingInfo signaling) {
    final currentUserID = OpenIM.iMManager.userID;
    final userIDSet = <String>{
      if (signaling.invitation?.inviterUserID != null)
        signaling.invitation!.inviterUserID!,
      ...?signaling.invitation?.inviteeUserIDList,
    };
    userIDSet.remove(currentUserID);
    return userIDSet.toList();
  }
}

class SignalingMessageEvent {
  Message message;
  String? userID;
  String? groupID;
  int sessionType;

  SignalingMessageEvent(
    this.message,
    this.sessionType,
    this.userID,
    this.groupID,
  );

  bool get isSingleChat => sessionType == ConversationType.single;

  bool get isGroupChat =>
      sessionType == ConversationType.group ||
      sessionType == ConversationType.superGroup;
}

extension MessageMangerExt on MessageManager {
  Future<Message> createCallMessage({
    required String type,
    required String state,
    int? duration,
  }) =>
      createCustomMessage(
        data: json.encode({
          "customType": CustomMessageType.call,
          "data": {
            'duration': duration,
            'state': state,
            'type': type,
          },
        }),
        extension: '',
        description: '',
      );
}
