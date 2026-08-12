import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_live_alert/flutter_openim_live_alert.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:livekit_client/livekit_client.dart'
    show ConnectException, MediaConnectException;
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../openim_live.dart';
import 'utils/call_audio_keepalive.dart';

mixin OpenIMLive {
  final signalingSubject = PublishSubject<CallEvent>();

  void invitationCancelled(SignalingInfo info) {
    final roomID = info.invitation?.roomID;
    // Same hardening as beHangup — BG/lock/home CallKit + Flutter ring must stop
    // without waiting for a stream listener that may be suspended.
    _markRoomEnded(roomID);
    signalingSubject.add(CallEvent(CallState.beCanceled, info));
    _terminateCallUi(roomID);
  }

  /// Caller received peer accept (IM `callingAccept`). Single entry — idempotent.
  void inviteeAccepted(SignalingInfo info) => _onPeerAccepted(info);

  void inviteeRejected(SignalingInfo info) {
    final roomID = info.invitation?.roomID;
    _markRoomEnded(roomID);
    signalingSubject.add(CallEvent(CallState.beRejected, info));
    _terminateCallUi(roomID);
  }

  void receiveNewInvitation(SignalingInfo info) {
    final roomID = info.invitation?.roomID?.trim() ?? '';
    final inviter = info.invitation?.inviterUserID?.trim() ?? '';
    final self = OpenIM.iMManager.userID.trim();
    _pruneEndedRooms();
    // Own outbound invite (echo/sync) must never open incoming UI.
    if (inviter.isNotEmpty && inviter == self) {
      Logger.print('ignore invite: self is inviter roomID=$roomID');
      return;
    }
    if (roomID.isNotEmpty && _endedRoomUntilMs.containsKey(roomID)) {
      Logger.print('ignore invite: room already ended $roomID');
      return;
    }
    // Already answered this room — never re-open invite sheet after hangup.
    if (roomID.isNotEmpty && _answeredRoomUntilMs.containsKey(roomID)) {
      Logger.print('ignore invite: room already answered $roomID');
      return;
    }
    if (_isAcceptInProgressForRoom(roomID) ||
        _callKitAcceptHandledRoomID == roomID) {
      Logger.print('ignore invite: accept in progress $roomID');
      return;
    }
    // Outbound waiting in this room — keep "等待接听", never promote/invite.
    if (_isOutboundWaitingRoom(roomID)) {
      Logger.print('ignore invite: outbound waiting roomID=$roomID');
      return;
    }
    // Already in a call: never re-open invite UI (fixes looping invite sheets).
    if (isBusy) {
      final current = OpenIMLiveClient().currentRoomID;
      if (current != null && current == roomID) {
        if (_isRoomEnded(roomID)) {
          Logger.print('ignore invite: room ended $roomID');
          return;
        }
        // Same room — attach in-call UI only (never beCalled).
        if (!OpenIMLiveClient().hasOverlay) {
          _presentCallUi(info, fromHeadless: true);
        } else if (OpenIMLiveClient().hasMediaFor(roomID)) {
          _promoteOverlayToInCall(info);
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

  void beHangup(SignalingInfo info, {int durationSec = 0}) {
    final roomID = info.invitation?.roomID;
    final wall = _connectedDurationSec();
    final sec = durationSec > wall ? durationSec : wall;
    _markRoomEnded(roomID);
    signalingSubject.add(CallEvent(CallState.beHangup, info, fields: sec));
    // Do not rely on signaling listener alone — background/lock may miss the stream pass.
    _terminateCallUi(roomID);
  }

  void _markRoomEnded(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    _endedRoomUntilMs[id] = DateTime.now().millisecondsSinceEpoch + _endedRoomTtlMs;
    _answeredRoomUntilMs.remove(id);
    unawaited(
        VoipCallkitController.toOrNull?.markRoomEndedNative(id) ?? Future.value());
  }

  void _markRoomAnswered(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    _answeredRoomUntilMs[id] =
        DateTime.now().millisecondsSinceEpoch + _endedRoomTtlMs;
  }

  void _pruneEndedRooms() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _endedRoomUntilMs.removeWhere((_, until) => until <= now);
    _answeredRoomUntilMs.removeWhere((_, until) => until <= now);
  }

  bool _isRoomEnded(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    _pruneEndedRooms();
    return _endedRoomUntilMs.containsKey(id);
  }

  /// Wall-clock from answer — UI timer alone often stays 0 on CallKit/headless.
  int? _callConnectedAtMs;

  void _markCallConnected() {
    _callConnectedAtMs ??= DateTime.now().millisecondsSinceEpoch;
  }

  int _connectedDurationSec() {
    final t = _callConnectedAtMs;
    if (t == null) return 0;
    final sec =
        ((DateTime.now().millisecondsSinceEpoch - t) / 1000).floor();
    return sec < 0 ? 0 : sec;
  }

  /// Tear down in-app + system call UI for [roomID] (peer hangup / cancel).
  void _terminateCallUi(String? roomID) {
    _markRoomEnded(roomID);
    final id = roomID?.trim() ?? '';
    if (id.isNotEmpty) _peerAcceptedRooms.remove(id);
    _callConnectedAtMs = null;
    _clearPickupCache();
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
    _autoPickup = false;
    _pendingHeadlessMicPermission = false;
    _iosCallKitAudioActivated = false;
    _iosCallKitDidActivateNative = false;
    _callKitAcceptHandledRoomID = null;
    _iosCallKitAudioGate = null;
    _beCalledEvent = null;
    _activeCallSignaling = null;
    _callSessionGen++; // invalidate in-flight headless accept/present
    _cancelRingTimeout();
    _ringTimeoutExtendCount = 0;
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    // Suppress programmatic endCall → actionCallEnded echo (not user hangup).
    _suppressCallKitEnded(roomID, duration: const Duration(seconds: 2));
    unawaited(_endSystemCallUi(roomID));
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }
  }

  /// End CallKit / system incoming UI. Never [endAllCalls] during active LiveKit.
  Future<void> _endSystemCallUi(String? roomID) async {
    final voip = VoipCallkitController.toOrNull;
    if (voip == null) return;
    final id = roomID?.trim() ?? '';
    final client = OpenIMLiveClient();
    final inLiveCall = id.isNotEmpty && client.isConnectedMedia(id);
    if (id.isNotEmpty) {
      await voip.endCall(id);
    }
    // Ringing-only fallback — endAllCalls during live call drops audio + fires ended.
    if (Platform.isIOS && voip.callKitActive.value && !inLiveCall) {
      await voip.endAllCalls();
    }
  }

  final backgroundSubject = PublishSubject<bool>();

  final insertSignalingMessageSubject = PublishSubject<CallEvent>();

  /// One chat call-record bubble per room (hangup + beHangup echo used to double).
  final Set<String> _hangupRecordInsertedRooms = {};

  Function(SignalingMessageEvent)? onSignalingMessage;
  final roomParticipantDisconnectedSubject = PublishSubject<RoomCallingInfo>();
  final roomParticipantConnectedSubject = PublishSubject<RoomCallingInfo>();

  bool _isRunningBackground = false;

  CallEvent? _beCalledEvent;
  /// Signaling for the active headless/lock-screen call (for UI attach after unlock).
  SignalingInfo? _activeCallSignaling;
  /// Outbound rooms where peer accept was already handled (idempotent `_onPeerAccepted`).
  final Set<String> _peerAcceptedRooms = {};
  /// Bumped on hangup/terminate so late async accept cannot reopen UI.
  int _callSessionGen = 0;

  bool _autoPickup = false;
  bool _pendingHeadlessMicPermission = false;
  /// Native didActivateAudioSession already bridged WebRTC (may arrive before gate exists).
  bool _iosCallKitAudioActivated = false;
  /// True only for real CXProvider didActivate (not timeout/optimistic bridge).
  bool _iosCallKitDidActivateNative = false;
  /// Deduplicate CallKit accept storm for the same room.
  String? _callKitAcceptHandledRoomID;
  /// Lock-screen CallKit: wait for didActivateAudioSession before LiveKit join.
  Completer<void>? _iosCallKitAudioGate;

  /// After *our* programmatic [endCall] (UI switch) — ignore Ended/Decline.
  final Map<String, int> _callKitUiDismissUntilMs = {};
  /// Short window after Accept for CallKit incoming→active noise only.
  final Map<String, int> _callKitAcceptSettleUntilMs = {};

  // --- iOS call UI rules (single source of truth) ---
  // | App state              | Incoming ring | Active call      |
  // |------------------------|---------------|------------------|
  // | Foreground (in app)    | Flutter overlay | Flutter overlay |
  // | Background / lock      | CallKit       | LiveKit + keepalive |
  // | Return to foreground   | overlay + dismiss CallKit | attach/promote overlay |
  //
  // CallKit Ended classification:
  // - uiDismiss armed     → NO-OP (we closed CallKit for UI switch)
  // - acceptSettle+joining → NO-OP (CallKit transition after Answer)
  // - answered / in-call   → hangup (real user End on lock screen)
  // - still ringing        → reject (user dismissed incoming CallKit)

  void _armCallKitUiDismiss(String? roomID,
      {Duration duration = const Duration(seconds: 3)}) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    final until =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    final prev = _callKitUiDismissUntilMs[id] ?? 0;
    if (until > prev) _callKitUiDismissUntilMs[id] = until;
  }

  void _armCallKitAcceptSettle(String? roomID,
      {Duration duration = const Duration(milliseconds: 2500)}) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    final until =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    final prev = _callKitAcceptSettleUntilMs[id] ?? 0;
    if (until > prev) _callKitAcceptSettleUntilMs[id] = until;
  }

  bool _isCallKitUiDismissArmed(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    final until = _callKitUiDismissUntilMs[id];
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  bool _isCallKitAcceptSettleArmed(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    final until = _callKitAcceptSettleUntilMs[id];
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  /// Bridge for PackageBridge / plugin — always means "we dismissed CallKit".
  void _suppressCallKitEnded(String? roomID,
      {Duration duration = const Duration(seconds: 4)}) {
    _armCallKitUiDismiss(roomID, duration: duration);
  }

  bool _shouldIgnoreCallKitEnded(String? roomID) {
    if (_isRoomEnded(roomID)) return true;
    return _isCallKitUiDismissArmed(roomID);
  }

  /// Dismiss system incoming UI only — not a user reject/hangup.
  Future<void> _dismissCallKitIncoming(String? roomID) async {
    if (!Platform.isIOS) return;
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    // 3s is enough for plugin Ended echo; do NOT use 45s (that swallowed real hangups).
    _armCallKitUiDismiss(id, duration: const Duration(seconds: 3));
    await VoipCallkitController.toOrNull?.endCall(id);
  }

  bool _iosShouldUseCallKitForRing(String? roomID) {
    if (!Platform.isIOS) return false;
    if (roomID != null && _isRoomEnded(roomID)) return false;
    if (_autoPickup || _isAcceptInProgressForRoom(roomID)) return false;
    // Debounced Flutter bg flag can lag 450ms — also use lifecycle so
    // home/lock WS invites still take CallKit instead of a missing overlay.
    final life = WidgetsBinding.instance.lifecycleState;
    final notActive = _isRunningBackground ||
        life == null ||
        life == AppLifecycleState.inactive ||
        life == AppLifecycleState.paused ||
        life == AppLifecycleState.hidden ||
        life == AppLifecycleState.detached;
    return notActive;
  }

  /// True while lock-screen / CallKit accept → LiveKit join has not finished.
  bool _isAcceptInProgressForRoom(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (_acceptJoinInFlight != null) {
      final joinRoom = _acceptJoinRoomID?.trim() ?? '';
      if (joinRoom.isEmpty || id.isEmpty || joinRoom == id) return true;
    }
    if (!_autoPickup) return false;
    if (id.isEmpty) return true;
    final active = _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    final joinRoom = _acceptJoinRoomID?.trim() ?? '';
    return active == id || joinRoom == id;
  }

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
  /// Answered roomIDs — ignore re-delivered invites that would flash accept UI.
  final Map<String, int> _answeredRoomUntilMs = {};
  static const _endedRoomTtlMs = 120 * 1000;
  final _ring = 'assets/audio/live_ring.wav';
  final _audioPlayer = AudioPlayer(
    // Avoid fighting LiveKit's playAndRecord session (reduces connect-time noise).
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );
  int _ringPlayGen = 0;
  Timer? _ringTimeoutTimer;
  String? _ringTimeoutRoomID;
  /// Caller waiting in LiveKit — allow up to 2 extra windows after first timeout.
  int _ringTimeoutExtendCount = 0;

  void _startRingTimeout(SignalingInfo signaling, {bool isExtension = false}) {
    _cancelRingTimeout();
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    if (roomID.isEmpty || _isRoomEnded(roomID)) return;
    // Lock-screen ICE often needs >30s end-to-end; default ring window 60s.
    final configured = signaling.invitation?.timeout ?? 60;
    final seconds = configured <= 0 ? 60 : configured;
    _ringTimeoutRoomID = roomID;
    if (!isExtension) _ringTimeoutExtendCount = 0;
    _ringTimeoutTimer = Timer(Duration(seconds: seconds), () {
      if (_isRoomEnded(roomID)) return;
      // Already answered (signal or LiveKit remote) — never auto-hang as "ring timeout".
      if (_peerAcceptedRooms.contains(roomID) ||
          OpenIMLiveClient().peerAcceptedForUi ||
          (OpenIMLiveClient().mediaRoom?.remoteParticipants.isNotEmpty ??
              false)) {
        Logger.print('call ring timeout ignored: already in-call roomID=$roomID');
        CallAudioDebugLog.add('ring', 'timeout ignored — already answered roomID=$roomID');
        _cancelRingTimeout();
        return;
      }
      final client = OpenIMLiveClient();
      final isCaller =
          signaling.invitation?.inviterUserID == OpenIM.iMManager.userID;
      // Only extend when peer is actually answering / joining — never because
      // caller alone sits in an empty LiveKit wait room (felt like forever).
      if (isCaller &&
          _ringTimeoutExtendCount < 2 &&
          client.currentRoomID == roomID &&
          (_peerAcceptedRooms.contains(roomID) ||
              client.peerAcceptedForUi ||
              client.isMediaConnecting ||
              (client.mediaRoom?.remoteParticipants.isNotEmpty ?? false))) {
        _ringTimeoutExtendCount++;
        Logger.print(
            'call ring timeout extended #$_ringTimeoutExtendCount roomID=$roomID');
        CallAudioDebugLog.add(
          'ring',
          'timeout extended #$_ringTimeoutExtendCount still in LiveKit roomID=$roomID',
        );
        _startRingTimeout(signaling, isExtension: true);
        return;
      }
      Logger.print('call ring timeout roomID=$roomID after ${seconds}s');
      CallAudioDebugLog.add('ring', 'timeout fire roomID=$roomID caller=$isCaller');
      signalingSubject.add(CallEvent(CallState.timeout, signaling));
    });
  }

  /// Caller: remote joined LiveKit ⇒ treat as answered (cancel ring timeout).
  void markOutboundPeerPresent(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty || _isRoomEnded(id)) return;
    _peerAcceptedRooms.add(id);
    _cancelRingTimeout();
    _ringTimeoutExtendCount = 0;
    _markCallConnected();
    OpenIMLiveClient().promoteCallingUi(markAccepted: true);
    final info = _activeCallSignaling;
    if (info != null) {
      // Drive CallState.calling so UI timer + duration insert both work.
      signalingSubject.add(CallEvent(CallState.calling, info));
    }
    Logger.print('outbound peer present (LiveKit) roomID=$id');
    CallAudioDebugLog.add('ring', 'LiveKit remote present — cancel timeout roomID=$id');
  }

  /// True while we are the inviter and peer has not accepted yet.
  bool _isOutboundWaitingRoom(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    if (_peerAcceptedRooms.contains(id)) return false;
    if (OpenIMLiveClient().peerAcceptedForUi) return false;
    final self = OpenIM.iMManager.userID.trim();
    final inviter =
        _activeCallSignaling?.invitation?.inviterUserID?.trim() ?? '';
    final activeRoom =
        _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    if (inviter != self) return false;
    if (activeRoom.isNotEmpty && activeRoom != id) return false;
    return true;
  }

  void _cancelRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _ringTimeoutRoomID = null;
  }

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
    if (identical(PackageBridge.onCallKitTimeout, _onCallKitTimeout)) {
      PackageBridge.onCallKitTimeout = null;
    }
    if (identical(PackageBridge.onVoipRemoteEnd, _onVoipRemoteEnd)) {
      PackageBridge.onVoipRemoteEnd = null;
    }
    if (identical(PackageBridge.suppressCallKitEnded, _suppressCallKitEnded)) {
      PackageBridge.suppressCallKitEnded = null;
    }
    if (identical(PackageBridge.isCallRoomEnded, _isRoomEnded)) {
      PackageBridge.isCallRoomEnded = null;
    }
    if (identical(PackageBridge.onPeerLeftCall, _onPeerLeftCall)) {
      PackageBridge.onPeerLeftCall = null;
    }
    if (identical(PackageBridge.markOutboundPeerPresent, markOutboundPeerPresent)) {
      PackageBridge.markOutboundPeerPresent = null;
    }
    if (identical(PackageBridge.onCallKitAudioActivated, _onCallKitAudioActivated)) {
      PackageBridge.onCallKitAudioActivated = null;
    }
    if (identical(
        PackageBridge.onCallKitAudioDeactivated, _onCallKitAudioDeactivated)) {
      PackageBridge.onCallKitAudioDeactivated = null;
    }
    if (identical(
        PackageBridge.connectedCallDurationSec, _connectedDurationSec)) {
      PackageBridge.connectedCallDurationSec = null;
    }
    _clearPickupCache();
    _cancelRingTimeout();
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
    PackageBridge.onCallKitTimeout = _onCallKitTimeout;
    PackageBridge.onVoipRemoteEnd = _onVoipRemoteEnd;
    PackageBridge.suppressCallKitEnded = _suppressCallKitEnded;
    PackageBridge.isCallRoomEnded = _isRoomEnded;
    PackageBridge.onPeerLeftCall = _onPeerLeftCall;
    PackageBridge.markOutboundPeerPresent = markOutboundPeerPresent;
    PackageBridge.onCallKitAudioActivated = _onCallKitAudioActivated;
    PackageBridge.onCallKitAudioDeactivated = _onCallKitAudioDeactivated;
    PackageBridge.connectedCallDurationSec = _connectedDurationSec;
    _signalingListener();
    _insertSignalingMessageListener();
    _bindLiveAlertButtons();
    backgroundSubject.listen((background) {
      _isRunningBackground = background;
      if (background) {
        unawaited(_onIosBackgroundForRinging());
      } else {
        unawaited(_onIosForegroundResume());
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
    final resolved = _resolveIncomingSignaling(signaling) ?? signaling;
    final roomID = resolved.invitation?.roomID?.trim() ?? '';

    // Deduplicate accept storm (plugin may re-fire onAccept / setConnected dozens of times).
    if (roomID.isNotEmpty) {
      if (_isRoomEnded(roomID)) {
        Logger.print('CallKit accept ignored: room ended $roomID');
        CallAudioDebugLog.add('callkit', 'accept ignored room ended $roomID');
        return;
      }
      if (_callKitAcceptHandledRoomID == roomID ||
          _isAcceptInProgressForRoom(roomID) ||
          OpenIMLiveClient().hasMediaFor(roomID)) {
        CallAudioDebugLog.add('callkit', 'accept ignored duplicate roomID=$roomID');
        return;
      }
      _callKitAcceptHandledRoomID = roomID;
    }

    _autoPickup = true;
    _stopSound();
    // Gate must exist before async accept — native audio may activate immediately after fulfill.
    _ensureIosCallKitAudioGate();
    CallAudioDebugLog.add(
      'callkit',
      'accept gate=${_iosCallKitAudioGate != null} activated=$_iosCallKitAudioActivated',
    );
    PackageBridge.clearCallNotification?.call();
    if (roomID.isNotEmpty) {
      _markRoomAnswered(roomID);
      // Only cover CallKit incoming→active transition noise (~2.5s).
      // Long suppress was swallowing real lock-screen hangups (Bug1).
      _armCallKitAcceptSettle(roomID);
      // Do NOT setConnected here — wait until LiveKit join succeeds (avoids audio flap).
    }
    CallAudioDebugLog.add('callkit', 'accept join roomID=$roomID');
    unawaited(_callKitAcceptAndJoin(resolved));
  }

  Future<void> _callKitAcceptAndJoin(SignalingInfo signaling) async {
    // Mic status + gate already handled in _runAcceptJoin for all headless accepts.
    await _acceptIncomingCall(signaling, requestPermissions: false);
  }

  /// Foreground invite / in-app accept: activate VoIP session early so AEC is
  /// already warm when LiveKit media starts (clear audio immediately).
  ///
  /// Never fights CallKit: skip while CallKit owns the session / incoming UI,
  /// and only run after programmatic dismiss has armed uiDismiss.
  Future<void> _prewarmInAppCallAudio({
    bool force = false,
    String? afterDismissRoomID,
  }) async {
    if (!Platform.isIOS) return;
    final roomID = afterDismissRoomID?.trim() ?? '';
    if (roomID.isNotEmpty) {
      // Wait for CallKit endCall echo window so setActive does not race didDeactivate.
      var waited = 0;
      while (waited < 800 && _isCallKitUiDismissArmed(roomID)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        waited += 50;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final voip = VoipCallkitController.toOrNull;
    if (CallAudioKeepAlive.instance.callKitOwnsSession ||
        voip?.ownsIncomingUi == true ||
        _iosCallKitDidActivateNative) {
      CallAudioDebugLog.add(
        'audio',
        'prewarm skipped — CallKit still owns session',
      );
      return;
    }
    // Lock / bg ring must stay on CallKit audio — never pre-setActive there.
    if (_iosShouldUseCallKitForRing(roomID.isEmpty ? null : roomID)) {
      CallAudioDebugLog.add('audio', 'prewarm skipped — CallKit ring path');
      return;
    }
    final speaker = OpenIMLiveClient().userSpeakerPreference;
    CallAudioDebugLog.add(
      'audio',
      'prewarm in-app speaker=$speaker force=$force',
    );
    try {
      CallAudioKeepAlive.instance.releaseCallKitSession();
      await IosWebRtcAudio.ensureEnabled(speakerOn: speaker, force: force);
    } catch (e, s) {
      Logger.print('prewarm in-app audio failed: $e $s');
      CallAudioDebugLog.add('audio', 'prewarm failed: $e');
    }
  }

  /// Create or preserve the CallKit audio gate (never reset a pending gate — fixes race).
  void _ensureIosCallKitAudioGate() {
    if (_iosCallKitAudioActivated) {
      final gate = _iosCallKitAudioGate;
      if (gate == null || gate.isCompleted) {
        _iosCallKitAudioGate = Completer<void>()..complete();
        CallAudioDebugLog.add('gate', 'create completed (already activated)');
      }
      return;
    }
    final gate = _iosCallKitAudioGate;
    if (gate != null && !gate.isCompleted) {
      CallAudioDebugLog.add('gate', 'reuse pending');
      return;
    }
    _iosCallKitAudioGate = Completer<void>();
    CallAudioDebugLog.add('gate', 'create pending');
  }

  Future<void> _refreshHeadlessMicPending() async {
    try {
      final mic = await Permission.microphone.status;
      _pendingHeadlessMicPermission = !mic.isGranted;
      if (_pendingHeadlessMicPermission) {
        Logger.print('CallKit accept: mic not granted — defer capture until unlock');
        CallAudioDebugLog.add('mic', 'not granted — defer until unlock');
      } else {
        CallAudioDebugLog.add('mic', 'granted');
      }
    } catch (_) {
      _pendingHeadlessMicPermission = true;
      CallAudioDebugLog.add('mic', 'status check failed — treat as pending');
    }
  }

  void _onPeerLeftCall(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty || _isRoomEnded(id)) return;
    Logger.print('peer left — hangup call roomID=$id');
    final info = _activeCallSignaling;
    if (info != null && info.invitation?.roomID?.trim() == id) {
      // Notify peer so their timer stops (terminate-only left them in-call).
      unawaited(onTapHangup(info..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true));
    } else {
      _terminateCallUi(id);
    }
  }

  Future<void> _waitForIosCallKitAudio({bool speakerOn = false}) async {
    _ensureIosCallKitAudioGate();
    CallAudioDebugLog.add(
      'gate',
      'wait start activated=$_iosCallKitAudioActivated nativeDidActivate=$_iosCallKitDidActivateNative speaker=$speakerOn',
    );
    if (_iosCallKitDidActivateNative) {
      Logger.print('iOS CallKit audio already activated (native)');
      CallAudioDebugLog.add('gate', 'wait skip — native didActivate');
      return;
    }
    final gate = _iosCallKitAudioGate!;
    try {
      // Prefer real didActivate. Poll only for native flag, not timeout-bridge.
      await Future.any([
        gate.future,
        _pollNativeCallKitDidActivate(),
      ]).timeout(const Duration(seconds: 12));
      Logger.print('iOS CallKit audio session ready');
      CallAudioDebugLog.add(
        'gate',
        'wait ready nativeDidActivate=$_iosCallKitDidActivateNative',
      );
    } on TimeoutException {
      // Proceed with soft bridge so LiveKit can join; real didActivate will kickstart later.
      CallAudioDebugLog.add('gate', 'timeout — soft bridge then proceed');
      await IosWebRtcAudio.bridgeCallKitSession();
      _iosCallKitAudioActivated = true;
      final g = _iosCallKitAudioGate;
      if (g != null && !g.isCompleted) g.complete();
      Logger.print('iOS CallKit audio timeout — soft bridge, await late didActivate');
    }
  }

  Future<void> _pollNativeCallKitDidActivate() async {
    final gen = _callSessionGen;
    while (!_iosCallKitDidActivateNative && gen == _callSessionGen) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _markIosCallKitAudioReady({
    String source = 'native',
    bool fromNativeDidActivate = false,
  }) {
    _iosCallKitAudioActivated = true;
    if (fromNativeDidActivate) _iosCallKitDidActivateNative = true;
    final gate = _iosCallKitAudioGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    } else if (gate == null) {
      _iosCallKitAudioGate = Completer<void>()..complete();
    }
    Logger.print('iOS CallKit audio ready ($source)');
    CallAudioDebugLog.add(
      'gate',
      'ready source=$source nativeDidActivate=$_iosCallKitDidActivateNative',
    );
  }

  void _onCallKitAudioActivated() {
    _markIosCallKitAudioReady(
      source: 'didActivate',
      fromNativeDidActivate: true,
    );
    // Keep CallKit as session owner — do not hand off to in-app enable.
    CallAudioKeepAlive.instance.markCallKitOwnsSession();
    final client = OpenIMLiveClient();
    if (!client.isBusy || client.mediaRoom == null) {
      CallAudioDebugLog.add(
          'callkit', 'didActivate — media not ready yet (kickstart deferred)');
      return;
    }
    final isVideo = _activeCallSignaling?.invitation?.mediaType == 'video';
    Logger.print('CallKit audio activated (native) — enable LiveKit audio');
    CallAudioDebugLog.add(
        'callkit', 'didActivate — re-arm media (no setConnected storm)');
    // Subscribe remotes / unmute only if off — never setConnected here.
    unawaited(client.kickstartIosCallKitMedia(speakerOn: OpenIMLiveClient().userSpeakerPreference));
  }

  /// CallKit dropped AVAudioSession mid-call — take over so LiveKit can keep audio.
  void _onCallKitAudioDeactivated() {
    _iosCallKitDidActivateNative = false;
    CallAudioDebugLog.add('callkit', 'didDeactivate');
    final client = OpenIMLiveClient();
    if (!client.isBusy) return;
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    // Mid-ICE on lock screen: setActive often fails — bridge only.
    // If user already unlocked (fg), CallKit released the session — must setActive.
    if (client.isMediaConnecting && !foreground) {
      CallAudioDebugLog.add(
        'callkit',
        'didDeactivate during connect (locked) — bridge only',
      );
      unawaited(IosWebRtcAudio.bridgeCallKitSession());
      return;
    }
    CallAudioDebugLog.add(
      'callkit',
      'didDeactivate while busy — switch to in-app WebRTC enable fg=$foreground connecting=${client.isMediaConnecting}',
    );
    CallAudioKeepAlive.instance.releaseCallKitSession();
    unawaited(_takeOverAudioAfterCallKitDeactivate(client));
  }

  /// Unlock / open chat: CallKit releases session — force WebRTC setActive + mic.
  Future<void> _takeOverAudioAfterCallKitDeactivate(OpenIMLiveClient client) async {
    final speaker = OpenIMLiveClient().userSpeakerPreference ?? false;
    await IosWebRtcAudio.ensureEnabled(speakerOn: speaker, force: true);
    // Second pass after UI setSpeakerRoute may have raced the first enable.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await IosWebRtcAudio.ensureEnabled(speakerOn: speaker, force: true);
    if (!client.isBusy) return;
    if (!client.isMediaConnecting && client.mediaRoom != null) {
      await client.onCallActive(speakerOn: speaker, unmuteMic: true);
      await client.ensureMediaAudible(speakerOn: speaker);
    }
  }

  /// Background / lock: ringing uses CallKit, not Flutter overlay.
  Future<void> _onIosBackgroundForRinging() async {
    if (!Platform.isIOS) return;
    final signaling = _activeCallSignaling ?? _beCalledEvent?.data;
    if (signaling == null) return;
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    if (roomID.isEmpty || _isRoomEnded(roomID)) return;
    // Already answered / joining — never re-arm incoming CallKit.
    if (_answeredRoomUntilMs.containsKey(roomID) ||
        _isAcceptInProgressForRoom(roomID) ||
        _callKitAcceptHandledRoomID == roomID) {
      return;
    }
    if (!_iosShouldUseCallKitForRing(roomID)) return;

    final client = OpenIMLiveClient();
    if (client.hasMediaFor(roomID) || client.isBusy) return;

    final voip = VoipCallkitController.toOrNull;
    if (voip == null) return;

    if (client.hasOverlay) {
      Logger.print('iOS bg: overlay→CallKit roomID=$roomID');
      client.closeOverlayOnly();
    }

    _beCalledEvent ??= CallEvent(CallState.beCalled, signaling);
    _activeCallSignaling = signaling;

    if (!voip.ownsIncomingUi) {
      await voip.showIncoming(signaling);
    }
  }

  /// Foreground: attach in-app UI; dismiss CallKit without treating as hangup.
  Future<void> _onIosForegroundResume() async {
    if (!Platform.isIOS) return;
    await _ensureMicPermissionAfterHeadlessAccept();
    FlutterOpenimLiveAlert.closeLiveAlert();
    PackageBridge.clearCallNotification?.call();

    final client = OpenIMLiveClient();
    final active = _activeCallSignaling;
    final activeRoom = active?.invitation?.roomID?.trim() ?? '';

    // Outbound still ringing (already in LiveKit) — leave "等待接听" alone.
    if (active != null &&
        activeRoom.isNotEmpty &&
        _isOutboundWaitingRoom(activeRoom)) {
      _beCalledEvent = null;
      CallAudioDebugLog.add(
          'fg', 'outbound still ringing — keep waiting UI roomID=$activeRoom');
      return;
    }

    // Live / connecting call — attach UI only; never end media on unlock.
    if (active != null &&
        activeRoom.isNotEmpty &&
        !_isRoomEnded(activeRoom) &&
        (client.hasMediaFor(activeRoom) ||
            client.isBusy && client.currentRoomID == activeRoom)) {
      _beCalledEvent = null;
      if (!client.hasOverlay) {
        Logger.print('iOS fg: attach call UI roomID=$activeRoom');
        _presentCallUi(active, fromHeadless: true);
      } else {
        _promoteOverlayToInCall(active);
      }
      await _restoreLiveCallAudio(active);
      return;
    }

    // Pending ring or accept still in flight.
    if (_beCalledEvent != null) {
      final pending = _beCalledEvent!;
      final pendingRoom = pending.data.invitation?.roomID?.trim() ?? '';
      _beCalledEvent = null;
      // Already answered from CallKit banner — keep media, attach UI, don't kill call.
      if (_answeredRoomUntilMs.containsKey(pendingRoom) ||
          _isAcceptInProgressForRoom(pendingRoom)) {
        Logger.print(
            'iOS fg: answered/joining from banner roomID=$pendingRoom');
        CallAudioDebugLog.add(
            'fg', 'answered banner — attach UI roomID=$pendingRoom');
        _armCallKitAcceptSettle(pendingRoom);
        _activeCallSignaling = pending.data;
        await _dismissCallKitIncoming(pendingRoom);
        final inFlight = _acceptJoinInFlight;
        if (inFlight != null) {
          unawaited(inFlight.then((_) {
            if (_isRoomEnded(pendingRoom)) return;
            if (!client.hasOverlay) {
              _presentCallUi(pending.data, fromHeadless: true);
            } else {
              _promoteOverlayToInCall(pending.data);
            }
            unawaited(_restoreLiveCallAudio(pending.data));
          }));
        } else if (client.hasMediaFor(pendingRoom) || client.isBusy) {
          if (!client.hasOverlay) {
            _presentCallUi(pending.data, fromHeadless: true);
          } else {
            _promoteOverlayToInCall(pending.data);
          }
          await _restoreLiveCallAudio(pending.data);
        }
        return;
      }

      if (_isRoomEnded(pendingRoom)) {
        await _dismissCallKitIncoming(pendingRoom);
        return;
      }

      // Unanswered ring — in-app UI primary, silently drop CallKit.
      await _dismissCallKitIncoming(pendingRoom);
      final ctx = Get.overlayContext;
      if (ctx != null) {
        _presentCallUi(pending.data);
        unawaited(_prewarmInAppCallAudio(
          force: true,
          afterDismissRoomID: pendingRoom,
        ));
      } else {
        _beCalledEvent = pending;
      }
      return;
    }

    // Stale signaling after hangup / media gone — clear, never re-show invite page.
    if (active != null && activeRoom.isNotEmpty && !client.hasOverlay) {
      if (_isRoomEnded(activeRoom) ||
          (_answeredRoomUntilMs.containsKey(activeRoom) &&
              !client.hasMediaFor(activeRoom) &&
              !_isAcceptInProgressForRoom(activeRoom) &&
              !client.isBusy)) {
        Logger.print('iOS fg: clear stale call signaling roomID=$activeRoom');
        CallAudioDebugLog.add('fg', 'clear stale signaling roomID=$activeRoom');
        await _dismissCallKitIncoming(activeRoom);
        _activeCallSignaling = null;
        _beCalledEvent = null;
        return;
      }
      if (!_isRoomEnded(activeRoom) &&
          (client.hasMediaFor(activeRoom) ||
              client.isBusy ||
              _isAcceptInProgressForRoom(activeRoom))) {
        Logger.print('iOS fg: attach mid-call UI roomID=$activeRoom');
        _presentCallUi(active, fromHeadless: true);
        await _restoreLiveCallAudio(active);
        return;
      }
      // Unanswered leftover with CallKit still up — dismiss only, no Flutter invite.
      await _dismissCallKitIncoming(activeRoom);
      Logger.print(
          'iOS fg: skip present stale UI roomID=$activeRoom');
      CallAudioDebugLog.add('fg', 'skip present stale UI roomID=$activeRoom');
      _activeCallSignaling = null;
      _beCalledEvent = null;
    }
  }

  /// PushKit cancel/hungup/accept — tear down or mark answered.
  void _onVoipRemoteEnd(String? roomID, String action) {
    Logger.print('VoIP remote end action=$action roomID=$roomID');
    final id = roomID?.trim() ?? '';
    final act = action.toLowerCase();

    // Callee answered — cancel caller ring timeout even if IM accept is delayed.
    if (act == 'accept' || act == 'answered') {
      if (id.isEmpty || _isRoomEnded(id)) return;
      final info = _activeCallSignaling;
      if (info?.invitation?.roomID?.trim() == id) {
        CallAudioDebugLog.add('voip', 'peer accept push — cancel ring roomID=$id');
        _onPeerAccepted(info!);
      } else {
        _peerAcceptedRooms.add(id);
        _cancelRingTimeout();
        CallAudioDebugLog.add('voip', 'peer accept push — mark answered roomID=$id');
      }
      return;
    }

    if (id.isNotEmpty && _isRoomEnded(id)) return;

    if (act != 'hungup' && act != 'end' && act != 'cancel' && act != 'reject') {
      return;
    }

    if (act == 'hungup' || act == 'end') {
      final info = _activeCallSignaling;
      if (info != null) {
        // Peer already hung up — local cleanup only.
        unawaited(onTapHangup(info..userID = OpenIM.iMManager.userID, _connectedDurationSec(), false));
      } else {
        _terminateCallUi(id.isEmpty ? null : id);
      }
      return;
    }

    _terminateCallUi(id.isEmpty ? null : id);
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
      CallAudioDebugLog.add('accept', 'reuse media roomID=$roomID');
      if (presentUiAfter && !client.hasOverlay) {
        _promoteOverlayToInCall(signaling);
      }
      return client.mediaCertificate!;
    }

    if (_acceptJoinInFlight != null && _acceptJoinRoomID == roomID) {
      final cert = await _acceptJoinInFlight!;
      if (presentUiAfter && !_isRoomEnded(roomID)) {
        _promoteOverlayToInCall(signaling);
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
      if (gen == _callSessionGen && !_isRoomEnded(roomID)) {
        _autoPickup = false;
        _markRoomAnswered(roomID);
        _markCallConnected();
        signalingSubject.add(CallEvent(CallState.calling, signaling));
        // Single setConnected after successful join.
        _armCallKitAcceptSettle(roomID);
        unawaited(
            VoipCallkitController.toOrNull?.setConnected(roomID) ??
                Future.value());
        // Answered call: invite unread must not stick on conversation list.
        unawaited(_markCallConversationRead(signaling));
        if (presentUiAfter) {
          final client = OpenIMLiveClient();
          if (!client.hasOverlay) {
            _presentCallUi(signaling, fromHeadless: true);
          } else {
            _promoteOverlayToInCall(signaling);
          }
        }
      }
      return cert;
    } finally {
      if (_acceptJoinRoomID == roomID) {
        _acceptJoinInFlight = null;
        _acceptJoinRoomID = null;
      }
    }
  }

  Future<void> _ensureMicPermissionAfterHeadlessAccept() async {
    final client = OpenIMLiveClient();
    if (!client.isBusy) {
      _pendingHeadlessMicPermission = false;
      return;
    }
    final roomID = _activeCallSignaling?.invitation?.roomID?.trim() ??
        client.currentRoomID?.trim() ??
        '';
    // Caller still ringing in LiveKit — never unmute / promote in-call UI.
    if (_isOutboundWaitingRoom(roomID)) {
      CallAudioDebugLog.add('fg', 'skip mic restore — outbound still ringing');
      return;
    }
    final isVideo =
        _activeCallSignaling?.invitation?.mediaType == 'video';
    if (_pendingHeadlessMicPermission) {
      final mic = await Permission.microphone.status;
      if (!mic.isGranted) {
        Logger.print('headless accept: request mic permission on foreground');
        final ok = await Permissions.requestCallMedia(needCamera: isVideo);
        _pendingHeadlessMicPermission = false;
        if (!ok) return;
      } else {
        _pendingHeadlessMicPermission = false;
      }
    }
    // Unlock / open chat: always ensure WebRTC audio is live (CallKit may have
    // deactivated with a stale owns flag, or setSpeakerRoute left a dead session).
    final owns = CallAudioKeepAlive.instance.callKitOwnsSession;
    final speaker = OpenIMLiveClient().userSpeakerPreference ?? false;
    CallAudioDebugLog.add(
      'fg',
      'mic restore owns=$owns nativeDidActivate=$_iosCallKitDidActivateNative connecting=${client.isMediaConnecting}',
    );
    if (owns && !_iosCallKitDidActivateNative) {
      CallAudioKeepAlive.instance.releaseCallKitSession();
    }
    await IosWebRtcAudio.ensureEnabled(speakerOn: speaker, force: true);
    if (client.isMediaConnecting) {
      CallAudioDebugLog.add('fg', 'skip audio restore — connect in flight');
      return;
    }
    await client.onCallActive(speakerOn: speaker, unmuteMic: true);
    await client.ensureMediaAudible(speakerOn: speaker);
    // Do NOT promoteCallingUi here — that was starting caller timer before answer.
  }

  Future<void> _restoreLiveCallAudio(SignalingInfo? signaling) async {
    final client = OpenIMLiveClient();
    final roomID = signaling?.invitation?.roomID?.trim() ??
        client.currentRoomID?.trim() ??
        '';
    if (roomID.isEmpty || !client.hasMediaFor(roomID)) return;
    // Outbound wait: caller already joined LiveKit for faster answer — stay on "等待接听".
    if (_isOutboundWaitingRoom(roomID)) {
      CallAudioDebugLog.add(
          'fg', 'skip live audio restore — outbound still ringing roomID=$roomID');
      return;
    }
    Logger.print('restore live call audio roomID=$roomID');
    final owns = CallAudioKeepAlive.instance.callKitOwnsSession;
    final speaker = OpenIMLiveClient().userSpeakerPreference ?? false;
    CallAudioDebugLog.add(
      'fg',
      'restore owns=$owns nativeDidActivate=$_iosCallKitDidActivateNative connecting=${client.isMediaConnecting}',
    );
    if (owns && !_iosCallKitDidActivateNative) {
      CallAudioKeepAlive.instance.releaseCallKitSession();
    }
    // Always ensure — covers chat-page navigation after lock-screen answer.
    await IosWebRtcAudio.ensureEnabled(speakerOn: speaker, force: true);
    await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: speaker);
    if (client.isMediaConnecting) {
      CallAudioDebugLog.add('fg', 'skip audio restore — connect in flight');
      return;
    }
    await client.onCallActive(speakerOn: speaker, unmuteMic: true);
    await client.ensureMediaAudible(speakerOn: speaker);
  }

  Future<void> _acceptIncomingCall(
    SignalingInfo signaling, {
    bool requestPermissions = false,
  }) async {
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    try {
      await acceptIncomingCall(
        signaling,
        requestPermissions: requestPermissions,
        presentUiAfter: true,
      );
    } catch (e, s) {
      Logger.print('acceptIncomingCall failed: $e $s');
      CallAudioDebugLog.add('accept', 'failed — hangup+cleanup err=$e');
      // Failed join must not leave CallKit/signaling/UI zombie after unlock.
      if (roomID.isNotEmpty && !_isRoomEnded(roomID)) {
        unawaited(
          onTapHangup(signaling..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true),
        );
      }
      _terminateCallUi(roomID.isEmpty ? null : roomID);
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

    final isCallKitAccept = Platform.isIOS && !requestPermissions;
    CallAudioDebugLog.add(
      'accept',
      'join start roomID=$roomID callKit=$isCallKitAccept requestPerm=$requestPermissions',
    );
    // All headless/CallKit accepts (CallKit / notification / live-alert) —
    // create gate before pickup so early didActivate is never lost.
    if (isCallKitAccept) {
      _ensureIosCallKitAudioGate();
      await _refreshHeadlessMicPending();
    } else if (Platform.isIOS) {
      // In-app accept: take the session now so PeerConnection starts on a live
      // VoIP route (avoids muddy audio while AEC re-converges after late enable).
      CallAudioKeepAlive.instance.releaseCallKitSession();
      await _prewarmInAppCallAudio(force: true);
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

    // Lock-screen: join LiveKit only after CallKit activates WebRTC audio.
    if (isCallKitAccept) {
      await _waitForIosCallKitAudio(speakerOn: OpenIMLiveClient().userSpeakerPreference);
    }

    final micGranted = !isCallKitAccept || !_pendingHeadlessMicPermission;
    CallAudioDebugLog.add(
      'accept',
      'pre-connect micGranted=$micGranted pendingMic=$_pendingHeadlessMicPermission skipSession=$isCallKitAccept',
    );

    if (roomID != null && roomID.isNotEmpty) {
      await CallAudioKeepAlive.instance.start(
        roomID: roomID,
        isVideo: isVideo,
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        skipSessionActivation: isCallKitAccept,
      );
    }

    var workingCert = cert;
    // Audio-first: camera after LiveKit connect so video pickup isn't blocked on capture.
    Future<void> joinOnce() => OpenIMLiveClient().connectMedia(
          certificate: workingCert,
          callType: callType,
          speakerOn: OpenIMLiveClient().userSpeakerPreference,
          enableCamera: false,
          enableMicrophone: micGranted,
          enableKeepAlive: true,
          skipSessionActivation: isCallKitAccept,
          onDisconnected: () {
            final id = signaling.invitation?.roomID;
            if (_isRoomEnded(id)) return;
            // Never tear down while CallKit accept/join is still running.
            if (_isAcceptInProgressForRoom(id) ||
                OpenIMLiveClient().isMediaConnecting) {
              CallAudioDebugLog.add(
                  'accept', 'onDisconnected ignored — join in flight');
              return;
            }
            // Peer left / room dead — end immediately (no 8s zombie timer).
            if (!OpenIMLiveClient().isConnectedMedia(id) ||
                (OpenIMLiveClient().mediaRoom?.remoteParticipants.isEmpty ??
                    true)) {
              _terminateCallUi(id);
              return;
            }
            unawaited(Future<void>.delayed(const Duration(seconds: 3), () {
              if (_isRoomEnded(id)) return;
              if (OpenIMLiveClient().isConnectedMedia(id) &&
                  (OpenIMLiveClient()
                          .mediaRoom
                          ?.remoteParticipants
                          .isNotEmpty ??
                      false)) {
                return;
              }
              _terminateCallUi(id);
            }));
          },
        );

    try {
      await joinOnce();
    } catch (e) {
      final msg = e.toString();
      // Peer already left the LiveKit room — retrying ICE cannot revive the call.
      if (msg.contains('peer left during connect')) {
        CallAudioDebugLog.add('accept', 'peer left during connect — no retry');
        rethrow;
      }
      // Only retry real ICE/peer-connection timeouts — not clientInitiated cleanup.
      final retryable = e is TimeoutException ||
          msg.contains('Timed out waiting for PeerConnection') ||
          msg.contains('PeerConnection to connect') ||
          (e is MediaConnectException &&
              !msg.contains('clientInitiated') &&
              !msg.contains('peer left')) ||
          (e is ConnectException);
      if (!retryable || gen != _callSessionGen || _isRoomEnded(roomID)) {
        CallAudioDebugLog.add('accept', 'connect failed — no retry err=$e');
        rethrow;
      }
      CallAudioDebugLog.add('accept', 'connect failed — retry once err=$e');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (gen != _callSessionGen || _isRoomEnded(roomID)) {
        throw StateError('accept aborted after connect retry');
      }
      // Fresh JWT + re-bridge CallKit audio before second PeerConnection.
      if (roomID != null && roomID.isNotEmpty) {
        try {
          workingCert = await Apis.getTokenForRTC(
            roomID,
            OpenIM.iMManager.userID,
          );
          CallAudioDebugLog.add(
            'accept',
            'retry fresh token len=${workingCert.token?.length ?? 0}',
          );
        } catch (tokenErr) {
          CallAudioDebugLog.add('accept', 'retry token refresh failed: $tokenErr');
        }
      }
      if (isCallKitAccept) {
        await IosWebRtcAudio.bridgeCallKitSession();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await joinOnce();
    }

    if (gen != _callSessionGen || _isRoomEnded(roomID)) {
      Logger.print('abort accept after connect roomID=$roomID');
      if (roomID != null && roomID.isNotEmpty) {
        OpenIMLiveClient().closeByRoomID(roomID);
      } else {
        OpenIMLiveClient().close();
      }
      throw StateError('accept aborted after connect');
    }

    _markRoomAnswered(roomID);
    // One unmute/subscribe path after join — no second kickstart (mic flicker).
    await OpenIMLiveClient().onCallActive(
      speakerOn: OpenIMLiveClient().userSpeakerPreference,
      unmuteMic: micGranted,
    );
    if (isVideo && micGranted) {
      unawaited(OpenIMLiveClient().enableCameraWhenReady());
    }
    if (isCallKitAccept) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await OpenIMLiveClient().kickstartIosCallKitMedia(
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        unmuteMic: false, // already handled by onCallActive
      );
    }
    Logger.print('accept joined roomID=${cert.roomID} type=$callType');
    CallAudioDebugLog.add(
      'accept',
      'joined roomID=${cert.roomID} type=$callType remotes=${OpenIMLiveClient().mediaRoom?.remoteParticipants.length ?? 0}',
    );
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
    _activeCallSignaling = signaling;
    final client = OpenIMLiveClient();
    final roomKey = roomID?.trim() ?? '';
    // Caller already in LiveKit but peer not answered — keep waiting UI.
    final outboundWaiting = _isOutboundWaitingRoom(roomKey);
    if (client.hasOverlay) {
      if (outboundWaiting) return;
      if (client.hasMediaFor(roomID) || fromHeadless) {
        _promoteOverlayToInCall(signaling);
      }
      return;
    }

    final mediaType = signaling.invitation?.mediaType;
    final sessionType = signaling.invitation?.sessionType;
    final callType = mediaType == 'audio' ? CallType.audio : CallType.video;
    final callObj = sessionType == ConversationType.single
        ? CallObj.single
        : CallObj.group;
    final overlayContext = Get.overlayContext;
    final mediaReady = client.hasMediaFor(roomID);
    final answered = !outboundWaiting &&
        roomKey.isNotEmpty &&
        (_answeredRoomUntilMs.containsKey(roomKey) ||
            _peerAcceptedRooms.contains(roomKey) ||
            client.peerAcceptedForUi ||
            _isAcceptInProgressForRoom(roomKey) ||
            (fromHeadless && mediaReady));
    final CallState initState;
    if (outboundWaiting) {
      initState = CallState.call;
    } else if (mediaReady || answered) {
      initState = CallState.calling;
    } else {
      initState = CallState.beCalled;
    }
    if (overlayContext == null) {
      _beCalledEvent = CallEvent(initState, signaling);
      return;
    }

    OpenIMLiveClient().start(
      overlayContext,
      callEventSubject: signalingSubject,
      roomID: roomID,
      inviteeUserIDList: signaling.invitation!.inviteeUserIDList!,
      inviterUserID: signaling.invitation!.inviterUserID!,
      groupID: signaling.invitation!.groupID,
      callType: callType,
      callObj: callObj,
      initState: initState,
      onSyncUserInfo: onSyncUserInfo,
      onSyncGroupInfo: onSyncGroupInfo,
      onSyncGroupMemberInfo: onSyncGroupMemberInfo,
      autoPickup: initState == CallState.beCalled ? _autoPickup : false,
      onTapCancel: outboundWaiting
          ? () => onTapCancel(signaling)
          : null,
      onTapPickup: initState == CallState.beCalled
          ? () async {
              final cert = await acceptIncomingCall(
                signaling..userID = OpenIM.iMManager.userID,
                requestPermissions: true,
                presentUiAfter: false,
              );
              final id = signaling.invitation?.roomID;
              _markRoomAnswered(id);
              unawaited(
                  VoipCallkitController.toOrNull?.setConnected(id) ??
                      Future.value());
              return cert;
            }
          : null,
      onTapReject: initState == CallState.beCalled
          ? () => onTapReject(signaling..userID = OpenIM.iMManager.userID)
          : null,
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

  /// Headless accept (CallKit / notification): move existing invite UI to in-call.
  void _promoteOverlayToInCall(SignalingInfo signaling) {
    final roomID = signaling.invitation?.roomID;
    if (_isRoomEnded(roomID)) return;
    final roomKey = roomID?.trim() ?? '';
    // Never kill ringback / start timer while caller is still waiting.
    if (_isOutboundWaitingRoom(roomKey)) {
      Logger.print('skip promote — outbound still ringing roomID=$roomKey');
      CallAudioDebugLog.add(
          'fg', 'skip promote outbound waiting roomID=$roomKey');
      return;
    }
    final client = OpenIMLiveClient();
    final alreadyInCall = client.hasMediaFor(roomID) && client.hasOverlay;
    if (!client.hasOverlay) {
      _presentCallUi(signaling, fromHeadless: true);
      return;
    }
    Logger.print(
        'promote overlay to in-call roomID=$roomID media=${client.hasMediaFor(roomID)}');
    unawaited(_stopRingSound());
    _cancelRingTimeout();
    PackageBridge.clearCallNotification?.call();
    if (client.hasMediaFor(roomID)) {
      if (!alreadyInCall) {
        unawaited(
            VoipCallkitController.toOrNull?.setConnected(roomID) ??
                Future.value());
        final isVideo = signaling.invitation?.mediaType == 'video';
        unawaited(OpenIMLiveClient().onCallActive(
          speakerOn: OpenIMLiveClient().userSpeakerPreference,
          unmuteMic: true,
        ));
        signalingSubject.add(CallEvent(CallState.calling, signaling));
      }
    } else {
      // Media still joining — show connecting, not timer.
      signalingSubject.add(CallEvent(CallState.connecting, signaling));
    }
  }

  /// Caller: peer accepted — leave ringing, unmute, show in-call UI. Safe to call repeatedly.
  void _onPeerAccepted(SignalingInfo info) {
    final merged = _mergeOutboundAcceptSignaling(info);
    final roomID = merged.invitation?.roomID?.trim() ?? '';
    if (roomID.isEmpty || _isRoomEnded(roomID)) return;
    if (!_isOutboundDial(merged)) {
      Logger.print('ignore accept: not outbound dial roomID=$roomID');
      return;
    }

    final isVideo = merged.invitation?.mediaType == 'video';
    if (!_peerAcceptedRooms.contains(roomID)) {
      _peerAcceptedRooms.add(roomID);
      _cancelRingTimeout();
      _ringTimeoutExtendCount = 0;
      unawaited(_stopRingSound());
      _activeCallSignaling = merged;
      _markCallConnected();
      Logger.print('caller peer accepted roomID=$roomID');
      CallAudioDebugLog.add('ring', 'peer accepted — cancel timeout roomID=$roomID');
      final client = OpenIMLiveClient();
      // Waiting dial keeps mic off — clear preference so answer can unmute.
      client.setUserMicPreference(true);
      unawaited(client.onCallActive(
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        unmuteMic: true,
      ));
    } else {
      _markCallConnected();
    }

    signalingSubject.add(CallEvent(CallState.calling, merged));
    OpenIMLiveClient().promoteCallingUi(markAccepted: true);
  }

  /// Accept payload may omit fields — always merge with active outbound session.
  SignalingInfo _mergeOutboundAcceptSignaling(SignalingInfo info) {
    final active = _activeCallSignaling;
    final acceptInv = info.invitation;
    if (active?.invitation == null || acceptInv == null) return info;
    final activeInv = active!.invitation!;
    return SignalingInfo(
      userID: active.userID ?? info.userID ?? activeInv.inviterUserID,
      invitation: InvitationInfo(
        roomID: acceptInv.roomID?.trim().isNotEmpty == true
            ? acceptInv.roomID
            : activeInv.roomID,
        inviterUserID: acceptInv.inviterUserID?.trim().isNotEmpty == true
            ? acceptInv.inviterUserID
            : activeInv.inviterUserID,
        inviteeUserIDList:
            acceptInv.inviteeUserIDList ?? activeInv.inviteeUserIDList,
        groupID: acceptInv.groupID ?? activeInv.groupID,
        timeout: acceptInv.timeout ?? activeInv.timeout,
        mediaType: acceptInv.mediaType ?? activeInv.mediaType,
        sessionType: acceptInv.sessionType ?? activeInv.sessionType,
        platformID: acceptInv.platformID ?? activeInv.platformID,
      ),
    );
  }

  bool _isOutboundDial(SignalingInfo info) {
    final self = OpenIM.iMManager.userID.trim();
    final activeInviter =
        _activeCallSignaling?.invitation?.inviterUserID?.trim() ?? '';
    final roomID = info.invitation?.roomID?.trim() ?? '';
    final activeRoom =
        _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    // Must be the inviter — never treat callee busy-in-room as outbound dial
    // (was falsely promoting caller timer / accept paths).
    if (activeInviter == self) {
      if (roomID.isEmpty || activeRoom.isEmpty || activeRoom == roomID) {
        return true;
      }
    }
    final inviter = info.invitation?.inviterUserID?.trim() ?? '';
    return inviter == self && roomID.isNotEmpty;
  }

  SignalingInfo? _resolveIncomingSignaling(SignalingInfo? primary) {
    final active = _activeCallSignaling;
    if (primary == null) return active;
    if (active == null) return primary;
    final roomA = primary.invitation?.roomID?.trim() ?? '';
    final roomB = active.invitation?.roomID?.trim() ?? '';
    if (roomA.isEmpty || roomB.isEmpty || roomA != roomB) return primary;
    final inviter = primary.invitation?.inviterUserID?.trim() ?? '';
    if (inviter.isNotEmpty) return primary;
    return SignalingInfo(
      userID: active.invitation?.inviterUserID ?? active.userID,
      invitation: InvitationInfo(
        roomID: primary.invitation?.roomID ?? active.invitation?.roomID,
        inviterUserID: active.invitation?.inviterUserID,
        inviteeUserIDList: primary.invitation?.inviteeUserIDList ??
            active.invitation?.inviteeUserIDList,
        mediaType:
            primary.invitation?.mediaType ?? active.invitation?.mediaType,
        sessionType:
            primary.invitation?.sessionType ?? active.invitation?.sessionType,
        groupID: primary.invitation?.groupID ?? active.invitation?.groupID,
        timeout: primary.invitation?.timeout ?? active.invitation?.timeout,
      ),
    );
  }

  void _onCallKitDecline(SignalingInfo signaling) {
    final resolved = _resolveIncomingSignaling(signaling) ?? signaling;
    final roomID = resolved.invitation?.roomID?.trim() ?? '';
    // Programmatic endCall while switching to in-app UI must not reject.
    if (_isCallKitUiDismissArmed(roomID) || _isRoomEnded(roomID)) {
      Logger.print('CallKit decline ignored — uiDismiss/ended roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'decline ignored uiDismiss roomID=$roomID');
      return;
    }
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    _beCalledEvent = null;
    onTapReject(resolved..userID = OpenIM.iMManager.userID);
  }

  /// CallKit ring timed out — missed call. Local cleanup only (never reject).
  void _onCallKitTimeout(SignalingInfo? signaling) {
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    final info = _resolveIncomingSignaling(signaling) ??
        signaling ??
        _activeCallSignaling;
    final roomID = info?.invitation?.roomID?.trim() ??
        OpenIMLiveClient().currentRoomID?.trim() ??
        '';
    final voip = VoipCallkitController.toOrNull;
    // PushKit + Flutter re-show same UUID fires Timeout in ~1s and used to
    // mark the room ended → unlock shows nothing, caller waits forever.
    if (roomID.isNotEmpty &&
        voip != null &&
        voip.isSpuriousEarlyCallKitEnd(roomID) &&
        info != null &&
        !_isRoomEnded(roomID) &&
        !_answeredRoomUntilMs.containsKey(roomID)) {
      Logger.print(
          'CallKit timeout ignored — spurious re-show race roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'timeout ignored spurious roomID=$roomID');
      unawaited(voip.recoverSpuriousIncoming(info));
      return;
    }
    Logger.print('CallKit timeout — local miss only roomID=$roomID');
    CallAudioDebugLog.add('callkit', 'timeout local miss roomID=$roomID');
    // Same as Dart ring timeout for callee: do not send callingReject.
    if (roomID.isNotEmpty &&
        (_answeredRoomUntilMs.containsKey(roomID) ||
            _isAcceptInProgressForRoom(roomID) ||
            OpenIMLiveClient().hasMediaFor(roomID))) {
      // Timeout after answer is treated as hangup path via Ended normally.
      return;
    }
    _terminateCallUi(roomID.isEmpty ? null : roomID);
  }

  /// Lock-screen / system UI End — classify before reject/hangup.
  void _onCallKitEnded(SignalingInfo? signaling) {
    _stopSound();
    PackageBridge.clearCallNotification?.call();

    final info = _resolveIncomingSignaling(signaling) ??
        signaling ??
        _activeCallSignaling;
    final roomID =
        info?.invitation?.roomID ?? OpenIMLiveClient().currentRoomID;
    final roomKey = roomID?.trim() ?? '';

    // 1) We closed CallKit for UI switch (unlock → in-app) — never reject/hangup.
    if (_isCallKitUiDismissArmed(roomID) || _isRoomEnded(roomID)) {
      Logger.print('CallKit ended ignored — uiDismiss/ended roomID=$roomKey');
      CallAudioDebugLog.add(
          'callkit', 'ended ignored uiDismiss roomID=$roomKey');
      return;
    }

    final client = OpenIMLiveClient();
    final inCall = client.hasMediaFor(roomID) ||
        client.mediaRoom?.localParticipant != null;
    final acceptSent = roomKey.isNotEmpty &&
        (_pickupCertRoomID == roomKey ||
            _acceptJoinRoomID == roomKey ||
            _callKitAcceptHandledRoomID == roomKey ||
            _answeredRoomUntilMs.containsKey(roomKey) ||
            _isAcceptInProgressForRoom(roomKey));
    final joining = _isAcceptInProgressForRoom(roomKey) ||
        client.isMediaConnecting ||
        (_acceptJoinInFlight != null &&
            (_acceptJoinRoomID == null || _acceptJoinRoomID == roomKey));

    CallAudioDebugLog.add(
      'callkit',
      'ended roomID=$roomKey inCall=$inCall acceptSent=$acceptSent joining=$joining settle=${_isCallKitAcceptSettleArmed(roomID)}',
    );

    // 2) Accept→active transition noise (short settle only, while not yet in media).
    if (acceptSent &&
        !inCall &&
        joining &&
        _isCallKitAcceptSettleArmed(roomID)) {
      Logger.print(
          'CallKit ended ignored — accept settle joining roomID=$roomKey');
      CallAudioDebugLog.add(
          'callkit', 'ended ignored acceptSettle roomID=$roomKey');
      return;
    }

    final voip = VoipCallkitController.toOrNull;
    // Early Ended without accept — PushKit/Flutter UUID collision, not user reject.
    if (!inCall &&
        !acceptSent &&
        roomKey.isNotEmpty &&
        info != null &&
        voip != null &&
        voip.isSpuriousEarlyCallKitEnd(roomKey)) {
      Logger.print(
          'CallKit ended ignored — spurious re-show race roomID=$roomKey');
      CallAudioDebugLog.add(
          'callkit', 'ended ignored spurious roomID=$roomKey');
      unawaited(voip.recoverSpuriousIncoming(info));
      return;
    }

    _beCalledEvent = null;
    _autoPickup = false;

    // Invalidate in-flight join before hangup/reject.
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
    _callSessionGen++;

    // 3) Already answered — real user End (incl. lock-screen hangup after settle).
    if (info != null && (inCall || acceptSent)) {
      Logger.print('CallKit ended after accept → hangup roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'ended after accept → hangup roomID=$roomKey');
      unawaited(onTapHangup(
          info..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true));
      return;
    }

    // 4) Still ringing — user dismissed incoming CallKit → reject caller.
    if (info != null && !inCall) {
      Logger.print(
          'CallKit ended before connect — reject peer roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'ended before connect → reject roomID=$roomKey');
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
      if (Platform.isIOS) _ensureIosCallKitAudioGate();
      PackageBridge.clearCallNotification?.call();
      final signaling = _resolveIncomingSignaling(_beCalledEvent?.data) ??
          _activeCallSignaling;
      final roomID = signaling?.invitation?.roomID?.trim() ?? '';
      if (roomID.isNotEmpty) {
        _callKitAcceptHandledRoomID = roomID;
        _markRoomAnswered(roomID);
        _armCallKitAcceptSettle(roomID);
      }
      _beCalledEvent = null;
      if (signaling != null) {
        unawaited(_acceptIncomingCall(signaling, requestPermissions: false));
      } else {
        Logger.print('notification accept: no signaling context');
      }
      return;
    }
    final pending = _beCalledEvent;
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    final signaling = _resolveIncomingSignaling(pending?.data) ??
        _activeCallSignaling ??
        pending?.data;
    _beCalledEvent = null;
    if (signaling == null) return;
    onTapReject(signaling..userID = OpenIM.iMManager.userID);
  }

  void _bindLiveAlertButtons() {
    FlutterOpenimLiveAlert.buttonEvent(
      activityName: 'io.openim.MainActivity',
      onAccept: () {
        _autoPickup = true;
        if (Platform.isIOS) _ensureIosCallKitAudioGate();
        final signaling = _resolveIncomingSignaling(_beCalledEvent?.data) ??
            _activeCallSignaling;
        final roomID = signaling?.invitation?.roomID?.trim() ?? '';
        if (roomID.isNotEmpty) {
          _callKitAcceptHandledRoomID = roomID;
          _markRoomAnswered(roomID);
          _armCallKitAcceptSettle(roomID);
        }
        if (signaling != null) {
          unawaited(_acceptIncomingCall(signaling, requestPermissions: false));
        }
      },
      onReject: () {
        final signaling = _resolveIncomingSignaling(_beCalledEvent?.data) ??
            _activeCallSignaling;
        _beCalledEvent = null;
        _stopSound();
        PackageBridge.clearCallNotification?.call();
        if (signaling != null) {
          onTapReject(signaling..userID = OpenIM.iMManager.userID);
        }
      },
    );
  }

  Stream<CallEvent> get _stream => signalingSubject
      .stream /*.where((event) => LiveClient.dispatchSignaling(event))*/;

  _signalingListener() => _stream.listen(
        (event) async {
          // Incoming calls must still ring even if suppress flag raced after
          // kick/relogin — only drop when there is truly no session.
          if (!SessionGuard.shouldNotify &&
              event.state != CallState.beCalled) {
            return;
          }
          if (event.state == CallState.beCalled && !SessionGuard.shouldNotify) {
            Logger.print(
                'beCalled with shouldNotify=false — heal+continue room=${event.data.invitation?.roomID}');
            SessionGuard.markLoggedIn();
          }
          final roomID = event.data.invitation?.roomID;
          if (event.state != CallState.beCalled) {
            _beCalledEvent = null;
            FlutterOpenimLiveAlert.closeLiveAlert();
            PackageBridge.clearCallNotification?.call();
            // Stop ring on terminal / in-call transitions (not via `_stopSound` — keeps timeout).
            if (event.state == CallState.calling ||
                event.state == CallState.beRejected ||
                event.state == CallState.beCanceled ||
                event.state == CallState.beHangup) {
              unawaited(_stopRingSound());
            }
          }
          if (event.state == CallState.beCalled) {
            unawaited(_prefetchPickupToken(event.data.invitation?.roomID));
            _activeCallSignaling = event.data;
            _startRingTimeout(event.data);
            final mediaType = event.data.invitation!.mediaType;
            final callType =
                mediaType == 'audio' ? CallType.audio : CallType.video;

            // Background / lock: CallKit rings; foreground uses overlay below.
            if (_iosShouldUseCallKitForRing(roomID)) {
              // Never play in-app ring under CallKit — cancel may end CallKit
              // while Flutter ringtone keeps looping on home/lock.
              _stopSound();
              _beCalledEvent = event;
              _activeCallSignaling = event.data;
              if (Platform.isAndroid) {
                // Prefer flutter_callkit_incoming full-screen / call notification.
                final voip = VoipCallkitController.toOrNull;
                if (voip != null) {
                  if (OpenIMLiveClient().hasOverlay) {
                    Logger.print('skip background CallKit: in-app overlay visible');
                  } else {
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
                  }
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
                final voip = VoipCallkitController.toOrNull;
                if (voip != null) {
                  if (OpenIMLiveClient().hasOverlay) {
                    OpenIMLiveClient().closeOverlayOnly();
                  }
                  // PushKit may already own CallKit — showIncoming dedupes UUID.
                  await voip.showIncoming(event.data);
                }
              }
              return;
            }
            if (!_autoPickup) {
              _playSound();
            } else {
              _stopSound();
            }
            _activeCallSignaling = event.data;
            final overlayContext = Get.overlayContext;
            if (overlayContext == null) {
              _beCalledEvent = event;
              // Overlay may not be ready on cold unlock — retry shortly.
              Future.delayed(const Duration(milliseconds: 350), () {
                if (_beCalledEvent?.data.invitation?.roomID != roomID) return;
                if (_isRoomEnded(roomID)) return;
                if (Get.overlayContext == null) return;
                final pending = _beCalledEvent;
                if (pending == null) return;
                _beCalledEvent = null;
                PackageBridge.clearCallNotification?.call();
                FlutterOpenimLiveAlert.closeLiveAlert();
                _presentCallUi(pending.data, fromHeadless: _autoPickup);
                _autoPickup = false;
                unawaited(_dismissCallKitIncoming(roomID).then((_) {
                  return _prewarmInAppCallAudio(
                    force: true,
                    afterDismissRoomID: roomID,
                  );
                }));
              });
              return;
            }
            // Foreground in-app: overlay primary, dismiss duplicate CallKit.
            PackageBridge.clearCallNotification?.call();
            FlutterOpenimLiveAlert.closeLiveAlert();
            _presentCallUi(event.data, fromHeadless: _autoPickup);
            _autoPickup = false;
            // Dismiss first, then prewarm — never setActive under live CallKit.
            unawaited(_dismissCallKitIncoming(roomID).then((_) {
              return _prewarmInAppCallAudio(
                force: true,
                afterDismissRoomID: roomID,
              );
            }));
          } else if (event.state == CallState.beRejected) {
            insertSignalingMessageSubject.add(event);
            _terminateCallUi(roomID);
          } else if (event.state == CallState.beHangup) {
            insertSignalingMessageSubject.add(CallEvent(
              CallState.beHangup,
              event.data,
              fields: (event.fields ?? 0) > 0
                  ? event.fields!
                  : _connectedDurationSec(),
            ));
            _terminateCallUi(roomID);
          } else if (event.state == CallState.beCanceled) {
            insertSignalingMessageSubject.add(event);
            _terminateCallUi(roomID);
          } else if (event.state == CallState.calling) {
            _cancelRingTimeout();
          } else if (event.state == CallState.otherReject ||
              event.state == CallState.otherAccepted) {
            await _stopSound();
            if (!existActiveCallFor(roomID)) {
              _terminateCallUi(roomID);
            }
          } else if (event.state == CallState.timeout) {
            _cancelRingTimeout();
            insertSignalingMessageSubject.add(event);
            final data = event.data;
            final roomID = data.invitation?.roomID?.trim() ?? '';
            final isCaller =
                data.invitation?.inviterUserID == OpenIM.iMManager.userID;
            final wasAnswered = roomID.isNotEmpty &&
                (_peerAcceptedRooms.contains(roomID) ||
                    OpenIMLiveClient().peerAcceptedForUi ||
                    (OpenIMLiveClient()
                            .mediaRoom
                            ?.remoteParticipants
                            .isNotEmpty ??
                        false));
            if (isCaller && wasAnswered) {
              // Already in-call — hangup so callee gets hungup/VoIP end (not ring-cancel).
              unawaited(onTapHangup(
                  data..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true));
            } else {
              _terminateCallUi(roomID.isEmpty ? null : roomID);
              if (isCaller) {
                unawaited(onTimeoutCancelled(data));
              } else {
                // Callee miss — local cleanup only. Reject would show "对方已拒绝".
                CallAudioDebugLog.add(
                    'ring', 'callee timeout — local end only roomID=$roomID');
              }
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
        timeout: 60,
        mediaType: mediaType,
        sessionType: sessionType,
        platformID: IMUtils.getPlatform(),
        groupID: groupID,
      ),
    );

    _activeCallSignaling = signal;
    final newRoom = signal.invitation!.roomID?.trim() ?? '';
    _peerAcceptedRooms.remove(newRoom);
    _hangupRecordInsertedRooms.remove(newRoom);
    _ringTimeoutExtendCount = 0;

    OpenIMLiveClient().start(
      Get.overlayContext!,
      callEventSubject: signalingSubject,
      roomID: signal.invitation!.roomID,
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
        unawaited(_stopRingSound());
      },
      onError: onError,
      onRoomDisconnected: () => onRoomDisconnected(signal),
      onClose: () => unawaited(_stopSound()),
    );
    _startRingTimeout(signal);
  }

  onError(error, stack) {
    Logger.print('onError=====> $error $stack');
    // Duplicate Accept (CallKit + in-app / notification) can throw on the
    // second path while the first already joined — never kill a live call.
    final client = OpenIMLiveClient();
    if (client.mediaRoom?.localParticipant != null) {
      Logger.print('onError ignored: media already connected');
      unawaited(client.ensureMediaAudible(
        speakerOn: client.userSpeakerPreference,
      ));
      return;
    }
    client.close();
    _stopSound();
    // HttpUtil already toasted API failures like (errCode, errMsg).
    if (error is (int, String?)) {
      return;
    }
    if (error is String && error.startsWith('接口：')) {
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
    if (msg.contains('dial aborted') || msg.contains('room cancelled') ||
        msg.contains('room ended')) {
      return;
    }
    if (msg.contains('permission') || msg.contains('Permission')) {
      return;
    }
    if (msg.contains('missing liveURL/token') ||
        msg.contains('RTC token or LiveKit URL missing')) {
      IMViews.showToast(StrRes.networkError);
      return;
    }
    if (msg.contains('Connection refused') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Network is unreachable')) {
      IMViews.showToast(StrRes.networkError);
      return;
    }
    IMViews.showToast(StrRes.networkError);
  }

  onRoomDisconnected(SignalingInfo signalingInfo) {
    final roomID = signalingInfo.invitation?.roomID?.trim() ?? '';
    Logger.print('call room disconnected roomID=$roomID');
    CallAudioDebugLog.add('livekit', 'roomDisconnected → hangup roomID=$roomID');
    // Notify peer — bare UI close left the other side timing forever.
    if (roomID.isEmpty || _isRoomEnded(roomID)) {
      _terminateCallUi(roomID.isEmpty ? null : roomID);
      return;
    }
    unawaited(
      onTapHangup(signalingInfo..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true),
    );
  }

  Future<SignalingCertificate> onDialSingle(SignalingInfo signaling) async {
    final invitation = signaling.invitation!;
    final roomID = invitation.roomID;
    if (_isRoomEnded(roomID)) {
      throw StateError('dial aborted: room cancelled $roomID');
    }
    final data = {
      'customType': CustomMessageType.callingInvite,
      'data': invitation.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    if (_isRoomEnded(roomID)) {
      throw StateError('dial aborted after invite: room cancelled $roomID');
    }
    final isVideo = invitation.mediaType == 'video';
    // Await invite IM + VoIP so a quick cancel cannot outrun a late invite push
    // (home/lock CallKit zombie ring).
    try {
      await OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo:
            Config.offlineCallPushInfo(isVideo: isVideo, invitation: invitation),
        userID: invitation.inviteeUserIDList!.first,
        isOnlineOnly: false,
      );
    } catch (e, s) {
      Logger.print('dial invite IM failed: $e $s');
      rethrow;
    }
    if (_isRoomEnded(roomID)) {
      throw StateError('dial aborted after invite send: room cancelled $roomID');
    }
    try {
      await _triggerVoipPush(signaling, action: 'invite');
    } catch (e, s) {
      Logger.print('dial invite VoIP failed: $e $s');
      // Continue — IM invite may still ring in-app; cancel path still works.
    }
    if (_isRoomEnded(roomID)) {
      throw StateError('dial aborted after invite voip: room cancelled $roomID');
    }
    try {
      final certificate = await Apis.getTokenForRTC(
          invitation.roomID!, OpenIM.iMManager.userID);
      if (_isRoomEnded(roomID)) {
        throw StateError('dial aborted after token: room cancelled $roomID');
      }
      return certificate;
    } catch (e, s) {
      // Invite already left the device — must cancel or callee keeps ringing (Bug3).
      if (!_isRoomEnded(roomID)) {
        insertSignalingMessageSubject
            .add(CallEvent(CallState.networkError, signaling));
        unawaited(_abortOutboundDialAfterInvite(signaling));
      }
      Error.throwWithStackTrace(e, s);
    }
  }

  /// After invite was sent but dial cannot continue (RTC/network) — notify callee.
  Future<void> _abortOutboundDialAfterInvite(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    Logger.print('abort outbound dial after invite roomID=$roomID');
    CallAudioDebugLog.add('dial', 'abort after invite → cancel roomID=$roomID');
    try {
      await onTapCancel(signaling);
    } catch (e, s) {
      Logger.print('abort outbound dial cancel failed: $e $s');
      _markRoomEnded(roomID);
      _terminateCallUi(roomID.isEmpty ? null : roomID);
      try {
        await _triggerVoipPush(signaling, action: 'cancel');
      } catch (e2, s2) {
        Logger.print('abort outbound dial voip cancel failed: $e2 $s2');
      }
    }
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
      try {
        await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: Config.offlineCallPushInfo(
              isVideo: isVideo, invitation: invitation),
          userID: userID,
          isOnlineOnly: false,
        );
      } catch (e, s) {
        Logger.print('dial group invite IM failed user=$userID: $e $s');
      }
    }
    final roomID = invitation.roomID;
    if (roomID != null && !_isRoomEnded(roomID)) {
      try {
        await _triggerVoipPush(signaling, action: 'invite');
      } catch (e, s) {
        Logger.print('dial group invite VoIP failed: $e $s');
      }
    }
    try {
      final certificate = await Apis.getTokenForRTC(
        invitation.roomID!,
        OpenIM.iMManager.userID,
      );
      if (roomID != null && _isRoomEnded(roomID)) {
        throw StateError('dial aborted after token: room cancelled $roomID');
      }
      return certificate;
    } catch (e, s) {
      if (roomID != null && !_isRoomEnded(roomID)) {
        insertSignalingMessageSubject
            .add(CallEvent(CallState.networkError, signaling));
        unawaited(_abortOutboundDialAfterInvite(signaling));
      }
      Error.throwWithStackTrace(e, s);
    }
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
    final roomID = inv.roomID?.trim() ?? '';
    await Apis.voipPush(
      action: action,
      inviteeUserIDList: targets,
      roomID: roomID,
      // Stable CallKit id — never let server invent a random UUID.
      callUUID: roomID,
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
    // Deliver accept reliably — online-only can be dropped on some iOS/WS paths.
    await OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: signaling.invitation!.inviterUserID,
        isOnlineOnly: false);
    // VoIP push so caller cancels ring timeout even if IM is slow.
    final inviter = signaling.invitation!.inviterUserID?.trim() ?? '';
    if (inviter.isNotEmpty) {
      try {
        await _triggerVoipPush(
          signaling,
          action: 'accept',
          toUserIDs: [inviter],
        );
      } catch (e, s) {
        Logger.print('accept VoIP push failed: $e $s');
      }
    }
    final certificate = await Apis.getTokenForRTC(
        signaling.invitation!.roomID!, OpenIM.iMManager.userID);

    return certificate;
  }

  onTapReject(SignalingInfo signaling) async {
    final resolved = _resolveIncomingSignaling(signaling) ?? signaling;
    final roomID = resolved.invitation?.roomID;
    final alreadyEnded = _isRoomEnded(roomID);
    // Resolve peer BEFORE terminate (which clears _activeCallSignaling).
    var inviter = resolved.invitation?.inviterUserID?.trim() ?? '';
    if (inviter.isEmpty) {
      inviter = _activeCallSignaling?.invitation?.inviterUserID?.trim() ?? '';
    }
    final self = OpenIM.iMManager.userID;
    final fallbackInvitee =
        _activeCallSignaling?.invitation?.inviteeUserIDList?.firstOrNull;
    final recvUserID = inviter == self
        ? (resolved.invitation?.inviteeUserIDList?.firstOrNull ??
            fallbackInvitee)
        : (inviter.isNotEmpty
            ? inviter
            : resolved.invitation?.inviterUserID);
    // Always tear down local UI — mark-ended-only left zombie overlays.
    _terminateCallUi(roomID);
    _stopSound();
    if (alreadyEnded) {
      Logger.print('onTapReject skip signal — room already ended $roomID');
      return null;
    }
    insertSignalingMessageSubject.add(CallEvent(CallState.reject, resolved));

    if (recvUserID == null || recvUserID.isEmpty) {
      Logger.print('onTapReject: missing inviter — skip signal roomID=$roomID');
      CallAudioDebugLog.add('reject', 'missing inviter roomID=$roomID');
      unawaited(
          VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
      return null;
    }

    try {
      final data = {
        'customType': CustomMessageType.callingReject,
        'data': (resolved.invitation ?? signaling.invitation)!.toJson()
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      final result = await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: recvUserID,
          isOnlineOnly: false);
      try {
        await _triggerVoipPush(
          resolved,
          action: 'reject',
          toUserIDs: [recvUserID],
        );
      } catch (e, s) {
        Logger.print('reject VoIP push failed: $e $s');
      }
      unawaited(
          VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
      return result;
    } catch (e, s) {
      Logger.print('onTapReject send failed: $e $s');
      // Still try VoIP so caller can leave "请求中".
      try {
        await _triggerVoipPush(
          resolved,
          action: 'reject',
          toUserIDs: [recvUserID],
        );
      } catch (e2, s2) {
        Logger.print('reject VoIP fallback failed: $e2 $s2');
      }
      unawaited(
          VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
      return null;
    }
  }
  onTapCancel(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID;
    // Mirror hangup: end session first so in-flight dial/connect cannot reopen UI.
    _markRoomEnded(roomID);
    _callConnectedAtMs = null;
    _callSessionGen++;
    _activeCallSignaling = null;
    _beCalledEvent = null;
    _clearPickupCache();
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    unawaited(
        VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }

    insertSignalingMessageSubject.add(CallEvent(CallState.cancel, signaling));

    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserIDList = _recvUserIDList(signaling);
    // Await IM + VoIP cancel — fire-and-forget is dropped when caller
    // backgrounds immediately after hanging up from the dial UI.
    for (final userID in recvUserIDList) {
      try {
        await OpenIM.iMManager.messageManager.sendMessage(
            message: message,
            offlinePushInfo: OfflinePushInfo(),
            userID: userID,
            isOnlineOnly: false);
      } catch (e, s) {
        Logger.print('cancel IM send failed user=$userID: $e $s');
      }
    }
    try {
      await _triggerVoipPush(
        signaling,
        action: 'cancel',
        toUserIDs: recvUserIDList,
      );
    } catch (e, s) {
      Logger.print('voip cancel push failed: $e $s');
    }
    return true;
  }

  onTimeoutCancelled(SignalingInfo signaling) async {
    _markRoomEnded(signaling.invitation?.roomID);
    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserIDList = _recvUserIDList(signaling);
    for (final userID in recvUserIDList) {
      await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: userID,
          isOnlineOnly: false);
    }
    try {
      await _triggerVoipPush(
        signaling,
        action: 'cancel',
        toUserIDs: recvUserIDList,
      );
    } catch (e, s) {
      Logger.print('voip timeout cancel push failed: $e $s');
    }
    return true;
  }

  onTapHangup(SignalingInfo signaling, int duration, bool isPositive) async {
    final roomID = signaling.invitation?.roomID;
    // UI timer can reset after CallKit/unlock — take the longer of UI vs wall-clock.
    final wall = _connectedDurationSec();
    final sec = duration > wall ? duration : wall;
    // Mark ended + bump session gen FIRST so late invite/accept cannot reopen UI.
    _markRoomEnded(roomID);
    _callConnectedAtMs = null;
    _callSessionGen++;
    _activeCallSignaling = null;
    _beCalledEvent = null;
    _autoPickup = false;
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
    _clearPickupCache();
    _cancelRingTimeout();
    _ringTimeoutExtendCount = 0;
    _suppressCallKitEnded(roomID, duration: const Duration(seconds: 2));
    CallAudioDebugLog.add(
      'hangup',
      'local roomID=$roomID positive=$isPositive duration=$sec (ui=$duration)',
    );
    if (isPositive) {
      final data = {
        'customType': CustomMessageType.callingHungup,
        'data': {
          ...signaling.invitation!.toJson(),
          'duration': sec,
        },
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      final recvUserIDList = _recvUserIDList(signaling);
      for (final userID in recvUserIDList) {
        try {
          await OpenIM.iMManager.messageManager.sendMessage(
              message: message,
              offlinePushInfo: OfflinePushInfo(),
              userID: userID,
              isOnlineOnly: false);
        } catch (e, s) {
          Logger.print('hungup IM send failed user=$userID: $e $s');
        }
      }
      // End peer CallKit even if IM is slow / app backgrounded.
      try {
        await _triggerVoipPush(
          signaling,
          action: 'hungup',
          toUserIDs: recvUserIDList,
        );
      } catch (e, s) {
        Logger.print('voip hungup push failed: $e $s');
      }
    }
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    unawaited(
        VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }

    insertSignalingMessageSubject.add(CallEvent(
      CallState.hangup,
      signaling,
      fields: sec,
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

  Future<void> _stopRingSound() async {
    _ringPlayGen++;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> _stopSound() async {
    await _stopRingSound();
    _cancelRingTimeout();
  }

  /// Connected / hung-up calls keep a chat record but must not leave unread dots.
  Future<void> _markCallConversationRead(SignalingInfo signaling) async {
    try {
      final peer = _recvUserIDList(signaling).firstOrNull;
      if (peer == null || peer.isEmpty) return;
      final conv = await OpenIM.iMManager.conversationManager
          .getOneConversation(sourceID: peer, sessionType: ConversationType.single);
      final id = conv.conversationID;
      if (id.isEmpty) return;
      await OpenIM.iMManager.conversationManager
          .markConversationMessageAsRead(conversationID: id);
    } catch (e, s) {
      Logger.print('markCallConversationRead failed: $e $s');
    }
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
      final roomKey = invitation.roomID?.trim() ?? '';
      // hangup / beHangup both mean "answered then ended" — only one bubble.
      if (state == CallState.hangup || state == CallState.beHangup) {
        if (roomKey.isNotEmpty &&
            !_hangupRecordInsertedRooms.add(roomKey)) {
          Logger.print(
              'skip duplicate hangup record roomID=$roomKey state=${state.name}');
          return;
        }
      }
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
        receiverID: receiverID!,
        senderID: inviterUserID,
        message: message
          ..status = MessageStatus.succeeded
          ..isRead = true,
      );
      // SDK may return status=sending for local-only inserts; never show spinner.
      msg.status = MessageStatus.succeeded;
      msg.isRead = true;

      // Answered / hung-up records only — clear invite unread on the conversation.
      final answered = state == CallState.hangup ||
          state == CallState.beHangup ||
          state == CallState.calling ||
          state == CallState.beAccepted;
      if (answered) {
        unawaited(_markCallConversationRead(signalingInfo));
      }

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
