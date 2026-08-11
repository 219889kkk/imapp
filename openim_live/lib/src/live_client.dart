import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'pages/single/room.dart';
import 'utils/call_audio_keepalive.dart';

enum CallType { audio, video }

enum CallObj { single, group }

enum CallState {
  call,
  beCalled,
  reject,
  beRejected,
  calling,
  beAccepted,
  hangup,
  beHangup,
  connecting,
  otherAccepted,
  otherReject,
  cancel,
  beCanceled,
  timeout,
  join,
  networkError,
}

class CallEvent {
  CallState state;
  SignalingInfo data;
  dynamic fields;

  CallEvent(this.state, this.data, {this.fields});

  @override
  String toString() {
    return 'CallEvent{state: $state, data: $data, fields: $fields}';
  }
}

/// Owns LiveKit media so lock-screen accept can talk before Flutter UI exists.
class OpenIMLiveClient implements RTCBridge {
  OpenIMLiveClient._();

  static final OpenIMLiveClient singleton = OpenIMLiveClient._();

  factory OpenIMLiveClient() {
    PackageBridge.rtcBridge = singleton;
    return singleton;
  }

  @override
  bool get hasConnection => isBusy;

  @override
  bool get hasCallOverlay => _holder != null;

  @override
  void dismiss() {
    close();
  }

  static OverlayEntry? _holder;

  bool isBusy = false;

  String? currentRoomID;
  Future Function(int duration, bool isPositive)? onTapHangup;

  Room? _mediaRoom;
  EventsListener<RoomEvent>? _mediaListener;
  SignalingCertificate? _mediaCert;
  CallType? _mediaCallType;
  Future<void>? _mediaConnectInFlight;
  String? _mediaConnectRoomID;
  Completer<void>? _connectAbort;
  VoidCallback? _onMediaDisconnected;

  /// True while [connectMedia] / LiveKit join is still in flight.
  bool get isMediaConnecting => _mediaConnectInFlight != null;
  /// Last speaker choice from the in-call button (wins over delayed reinforce).
  bool? _userSpeakerPreference;
  String? _uiBoundRoomID;
  Future<void>? _callActiveInFlight;
  DateTime? _lastCallActiveAt;
  int _liveKitReconnectAttempts = 0;
  static const _maxLiveKitReconnectAttempts = 2;

  void Function(Room room)? _uiOnRoom;
  VoidCallback? _uiOnRemotePresent;
  VoidCallback? _uiOnRemoteLeft;
  VoidCallback? _uiOnDisconnected;

  Room? get mediaRoom => _mediaRoom;
  SignalingCertificate? get mediaCertificate => _mediaCert;
  CallType? get mediaCallType => _mediaCallType;

  void setUserSpeakerPreference(bool on) {
    _userSpeakerPreference = on;
  }

  bool get hasOverlay => _holder != null;

  bool hasMediaFor(String? roomID) {
    if (roomID == null || roomID.isEmpty) return _mediaRoom != null;
    return _mediaRoom != null && currentRoomID == roomID;
  }

  bool isConnectedMedia(String? roomID) {
    if (!hasMediaFor(roomID)) return false;
    return _mediaRoom?.localParticipant != null;
  }

  quitClose(String roomID) async {
    if (currentRoomID == roomID) {
      await onTapHangup?.call(0, true);
      closeByRoomID(roomID);
    }
  }

  closeByRoomID(String roomID) {
    if (currentRoomID == roomID) {
      close();
    }
  }

  /// Remove Flutter overlay only — keep LiveKit media (background → CallKit handoff).
  void closeOverlayOnly() {
    if (_holder != null) {
      _holder?.remove();
      _holder = null;
      WakelockPlus.disable();
    }
  }

  void Function()? _promoteCallingUi;
  bool _peerAcceptedForUi = false;

  bool get peerAcceptedForUi => _peerAcceptedForUi;

  void setPromoteCallingUiHandler(void Function()? handler) {
    _promoteCallingUi = handler;
  }

  /// Bypass signaling stream filter — push caller overlay to in-call immediately.
  void promoteCallingUi() {
    _peerAcceptedForUi = true;
    _promoteCallingUi?.call();
  }

  close() {
    if (_holder != null) {
      _holder?.remove();
      _holder = null;
    }
    _promoteCallingUi = null;
    _peerAcceptedForUi = false;
    unawaited(_disposeMedia());
    isBusy = false;
    currentRoomID = null;
    onTapHangup = null;
    _onMediaDisconnected = null;
    _userSpeakerPreference = null;
    _uiBoundRoomID = null;
    _uiOnRoom = null;
    _uiOnRemotePresent = null;
    _uiOnRemoteLeft = null;
    _uiOnDisconnected = null;
    // The next line disables the wakelock again.
    WakelockPlus.disable();
  }

  Future<void> _disposeMedia() async {
    final room = _mediaRoom;
    final listener = _mediaListener;
    _mediaRoom = null;
    _mediaListener = null;
    _mediaCert = null;
    _mediaCallType = null;
    _mediaConnectInFlight = null;
    _mediaConnectRoomID = null;
    unawaited(CallAudioKeepAlive.instance.stop());
    try {
      room?.removeListener(_noopRoomListener);
      await listener?.dispose();
      await room?.disconnect();
      await room?.dispose();
    } catch (e, s) {
      Logger.print('dispose media failed: $e $s');
    }
  }

  void _noopRoomListener() {}

  /// Connect LiveKit + publish mic without requiring call UI (lock-screen answer).
  Future<void> connectMedia({
    required SignalingCertificate certificate,
    required CallType callType,
    bool speakerOn = false,
    bool enableCamera = false,
    bool enableMicrophone = true,
    /// Caller waiting for answer: skip keepalive so ringback isn't ducked.
    bool enableKeepAlive = true,
    /// CallKit already activated AVAudioSession (lock-screen accept).
    bool skipSessionActivation = false,
    VoidCallback? onDisconnected,
  }) async {
    final roomID = certificate.roomID?.trim() ?? '';
    if (roomID.isEmpty) {
      throw StateError('connectMedia: empty roomID');
    }
    if (PackageBridge.isCallRoomEnded?.call(roomID) == true) {
      Logger.print('connectMedia skipped: room ended $roomID');
      return;
    }

    if (onDisconnected != null) {
      _onMediaDisconnected = onDisconnected;
    }

    if (hasMediaFor(roomID) && _mediaRoom?.localParticipant != null) {
      isBusy = true;
      currentRoomID = roomID;
      await _ensurePublished(
        callType: callType,
        speakerOn: speakerOn,
        enableCamera: enableCamera,
        enableMicrophone: enableMicrophone,
      );
      if (enableKeepAlive) {
        await _startKeepAlive(roomID, callType, speakerOn: speakerOn);
      }
      // Respect explicit mic-off while caller still waits for answer.
      if (enableMicrophone) {
        await ensureMediaAudible(speakerOn: speakerOn);
      }
      return;
    }

    if (_mediaConnectInFlight != null && _mediaConnectRoomID == roomID) {
      await _mediaConnectInFlight;
      // Apply latest publish flags (e.g. unmute after peer accepts).
      if (hasMediaFor(roomID) && _mediaRoom?.localParticipant != null) {
        await _ensurePublished(
          callType: callType,
          speakerOn: speakerOn,
          enableCamera: enableCamera,
          enableMicrophone: enableMicrophone,
        );
        if (enableKeepAlive) {
          await _startKeepAlive(roomID, callType, speakerOn: speakerOn);
        }
        if (enableMicrophone) {
          await ensureMediaAudible(speakerOn: speakerOn);
        }
      }
      return;
    }

    final future = _doConnectMedia(
      certificate: certificate,
      callType: callType,
      speakerOn: speakerOn,
      enableCamera: enableCamera,
      enableMicrophone: enableMicrophone,
      enableKeepAlive: enableKeepAlive,
      skipSessionActivation: skipSessionActivation,
    );
    _mediaConnectInFlight = future;
    _mediaConnectRoomID = roomID;
    try {
      await future;
    } finally {
      if (_mediaConnectRoomID == roomID) {
        _mediaConnectInFlight = null;
        _mediaConnectRoomID = null;
      }
    }
  }

  Future<void> _doConnectMedia({
    required SignalingCertificate certificate,
    required CallType callType,
    required bool speakerOn,
    required bool enableCamera,
    required bool enableMicrophone,
    required bool enableKeepAlive,
    bool skipSessionActivation = false,
  }) async {
    final roomID = certificate.roomID!;
    if (PackageBridge.isCallRoomEnded?.call(roomID) == true) {
      Logger.print('_doConnectMedia aborted: room ended $roomID');
      return;
    }
    final busyLineUsers = certificate.busyLineUserIDList ?? [];
    if (busyLineUsers.isNotEmpty) {
      throw StateError('busy line');
    }

    if (_mediaRoom != null && currentRoomID != roomID) {
      await _disposeMedia();
    }

    if (PackageBridge.isCallRoomEnded?.call(roomID) == true) {
      Logger.print('_doConnectMedia aborted before join: room ended $roomID');
      return;
    }

    isBusy = true;
    currentRoomID = roomID;
    _mediaCert = certificate;
    _mediaCallType = callType;

    if (_mediaRoom != null && _mediaRoom!.localParticipant != null) {
      await _ensurePublished(
        callType: callType,
        speakerOn: speakerOn,
        enableCamera: enableCamera,
        enableMicrophone: enableMicrophone,
      );
      if (enableKeepAlive) {
        await _startKeepAlive(roomID, callType, speakerOn: speakerOn);
      }
      if (enableMicrophone) {
        await ensureMediaAudible(speakerOn: speakerOn);
      }
      return;
    }

    await _disposeMediaRoomOnly();

    if (Platform.isIOS) {
      Hardware.instance.setAutomaticConfigurationEnabled(
        enable: !skipSessionActivation,
      );
    }

    CallAudioDebugLog.add(
      'livekit',
      'connect start roomID=$roomID skipSession=$skipSessionActivation mic=$enableMicrophone cam=$enableCamera',
    );

    if (!skipSessionActivation) {
      await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: speakerOn);
    }

    if (PackageBridge.isCallRoomEnded?.call(roomID) == true) {
      Logger.print('_doConnectMedia aborted before LiveKit: room ended $roomID');
      await _disposeMedia();
      isBusy = false;
      currentRoomID = null;
      return;
    }

    final room = Room();
    final listener = room.createListener();
    _mediaRoom = room;
    _mediaListener = listener;
    _mediaCert = certificate;
    _mediaCallType = callType;
    isBusy = true;
    currentRoomID = roomID;

    listener.on<RoomDisconnectedEvent>((event) {
      unawaited(_handleRoomDisconnected(room, event));
    });

    listener
      ..on<RoomReconnectingEvent>((_) {
        Logger.print('LiveKit reconnecting roomID=$roomID');
      })
      ..on<RoomReconnectedEvent>((_) {
        Logger.print('LiveKit reconnected roomID=$roomID');
        _liveKitReconnectAttempts = 0;
        unawaited(_subscribeRemoteTracks());
      });

    _wireRoomEvents(listener, room);

    Logger.print(
        'connectMedia connecting roomID=$roomID url=${certificate.liveURL}');
    final liveURL = certificate.liveURL?.trim() ?? '';
    final token = certificate.token?.trim() ?? '';
    if (liveURL.isEmpty || token.isEmpty) {
      throw StateError('missing liveURL/token for roomID=$roomID');
    }
    CallAudioDebugLog.add(
      'livekit',
      'room.connect begin roomID=$roomID url=$liveURL tokenLen=${token.length} skipSession=$skipSessionActivation',
    );
    // CallKit path: re-bridge + brief settle so PeerConnection starts on a live session.
    if (skipSessionActivation && Platform.isIOS) {
      await IosWebRtcAudio.bridgeCallKitSession();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _connectAbort = Completer<void>();
    final abortFuture = _connectAbort!.future;
    try {
      await Future.any<void>([
        room
            .connect(
          liveURL,
          token,
          connectOptions: const ConnectOptions(
            autoSubscribe: true,
            // Default peerConnection is 10s — lock-screen ICE often needs longer.
            timeouts: Timeouts(
              connection: Duration(seconds: 25),
              debounce: Duration(milliseconds: 100),
              publish: Duration(seconds: 10),
              peerConnection: Duration(seconds: 25),
              iceRestart: Duration(seconds: 10),
            ),
          ),
          roomOptions: RoomOptions(
            dynacast: true,
            adaptiveStream: true,
            defaultAudioCaptureOptions: const AudioCaptureOptions(
              echoCancellation: true,
              noiseSuppression: true,
              autoGainControl: true,
              highPassFilter: true,
            ),
            defaultAudioOutputOptions: AudioOutputOptions(speakerOn: speakerOn),
            defaultCameraCaptureOptions: const CameraCaptureOptions(
              params: VideoParametersPresets.h720_169,
            ),
            defaultVideoPublishOptions: const VideoPublishOptions(
              simulcast: true,
              videoCodec: 'VP8',
            ),
          ),
          // CallKit: publish mic during join so ADM/ICE start under an active session.
          fastConnectOptions: FastConnectOptions(
            microphone: TrackOption(enabled: enableMicrophone),
          ),
        )
            .timeout(const Duration(seconds: 30)),
        abortFuture,
      ]);
      CallAudioDebugLog.add(
        'livekit',
        'room.connect ok roomID=$roomID remotes=${room.remoteParticipants.length}',
      );
    } on TimeoutException {
      CallAudioDebugLog.add('livekit', 'room.connect TIMEOUT 30s roomID=$roomID');
      await _disposeMediaRoomOnly();
      isBusy = false;
      currentRoomID = null;
      rethrow;
    } catch (e) {
      CallAudioDebugLog.add('livekit', 'room.connect failed roomID=$roomID err=$e');
      await _disposeMediaRoomOnly();
      isBusy = false;
      currentRoomID = null;
      rethrow;
    } finally {
      final abort = _connectAbort;
      _connectAbort = null;
      if (abort != null && !abort.isCompleted) {
        abort.complete();
      }
    }

    room.addListener(_noopRoomListener);
    await _ensurePublished(
      callType: callType,
      speakerOn: speakerOn,
      enableCamera: enableCamera,
      enableMicrophone: enableMicrophone,
    );
    if (enableKeepAlive) {
      await _startKeepAlive(roomID, callType, speakerOn: speakerOn);
    }
    // Waiting caller keeps mic off; unmute happens on peer accept.
    if (enableMicrophone) {
      await ensureMediaAudible(speakerOn: speakerOn);
    } else {
      try {
        if (!skipSessionActivation) {
          await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: speakerOn);
        }
        await Hardware.instance.setSpeakerphoneOn(speakerOn);
        await room.setSpeakerOn(speakerOn);
        // CallKit lock-screen: subscribe remote audio even when mic deferred.
        if (skipSessionActivation) {
          await _subscribeRemoteTracks();
          CallAudioDebugLog.add(
            'livekit',
            'connect mic-off CallKit path subscribed remotes=${room.remoteParticipants.length}',
          );
        }
      } catch (_) {}
    }
    WakelockPlus.enable();
    Logger.print('connectMedia connected roomID=$roomID keepAlive=$enableKeepAlive');
    CallAudioDebugLog.add(
      'livekit',
      'connected roomID=$roomID remotes=${room.remoteParticipants.length} keepAlive=$enableKeepAlive',
    );
    // Peer may still be joining — do not end immediately on empty remotes.
    if (room.remoteParticipants.isEmpty) {
      CallAudioDebugLog.add(
          'livekit', 'connected with 0 remotes — wait for peer');
    }
  }

  /// Accumulated while another onCallActive is in flight (fixes caller mic stuck off).
  bool _pendingUnmuteMic = false;
  bool? _pendingSpeakerOn;

  /// Single debounced path when call becomes active (peer joined / accepted).
  Future<void> onCallActive({bool? speakerOn, bool unmuteMic = true}) async {
    if (unmuteMic) _pendingUnmuteMic = true;
    if (speakerOn != null) _pendingSpeakerOn = speakerOn;

    if (_callActiveInFlight != null) {
      await _callActiveInFlight;
      await _applyPendingCallActive();
      return;
    }

    final now = DateTime.now();
    if (_lastCallActiveAt != null &&
        now.difference(_lastCallActiveAt!) < const Duration(milliseconds: 400)) {
      await Future<void>.delayed(
        Duration(
          milliseconds: 400 - now.difference(_lastCallActiveAt!).inMilliseconds,
        ),
      );
      await _applyPendingCallActive();
      return;
    }

    await _applyPendingCallActive();
  }

  Future<void> _applyPendingCallActive() async {
    if (!_pendingUnmuteMic && _pendingSpeakerOn == null) return;
    final unmute = _pendingUnmuteMic;
    final spk = _pendingSpeakerOn;
    _pendingUnmuteMic = false;
    _pendingSpeakerOn = null;
    _lastCallActiveAt = DateTime.now();
    _callActiveInFlight = _doCallActive(speakerOn: spk, unmuteMic: unmute);
    try {
      await _callActiveInFlight;
    } finally {
      _callActiveInFlight = null;
      if (_pendingUnmuteMic || _pendingSpeakerOn != null) {
        await _applyPendingCallActive();
      }
    }
  }

  Future<void> _doCallActive({bool? speakerOn, bool unmuteMic = true}) async {
    final room = _mediaRoom;
    if (room == null) return;
    final on = speakerOn ??
        _userSpeakerPreference ??
        (_mediaCallType == CallType.video);
    final roomID = currentRoomID;
    final callType = _mediaCallType ?? CallType.audio;
    if (roomID != null && roomID.isNotEmpty) {
      await _startKeepAlive(roomID, callType, speakerOn: on);
    }
    try {
      await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: on);
      await Hardware.instance.setSpeakerphoneOn(on);
      await room.setSpeakerOn(on);
      if (unmuteMic) {
        final local = room.localParticipant;
        if (local != null && local.isMicrophoneEnabled() != true) {
          await local.setMicrophoneEnabled(true);
        }
      }
      await _subscribeRemoteTracks();
      Logger.print(
          'onCallActive speaker=$on unmuteMic=$unmuteMic remotes=${room.remoteParticipants.length}');
    } catch (e, s) {
      Logger.print('onCallActive failed: $e $s');
    }
  }

  /// Start mic/CallKit keepalive after peer joins (caller left wait-ring state).
  Future<void> ensureCallKeepAlive({bool? speakerOn}) async {
    await onCallActive(speakerOn: speakerOn, unmuteMic: true);
  }

  /// Make sure remote audio is subscribed and local route/mic are live.
  Future<void> ensureMediaAudible({bool? speakerOn}) async {
    final room = _mediaRoom;
    if (room == null) return;
    final on = speakerOn ??
        _userSpeakerPreference ??
        (_mediaCallType == CallType.video);
    try {
      await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: on);
      await Hardware.instance.setSpeakerphoneOn(on);
      await room.setSpeakerOn(on);
      final local = room.localParticipant;
      if (local != null && local.isMicrophoneEnabled() != true) {
        await local.setMicrophoneEnabled(true);
      }
      await _subscribeRemoteTracks();
      Logger.print(
          'ensureMediaAudible speaker=$on remotes=${room.remoteParticipants.length}');
    } catch (e, s) {
      Logger.print('ensureMediaAudible failed: $e $s');
    }
  }

  Future<void> _subscribeRemoteTracks() async {
    final room = _mediaRoom;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        try {
          if (!pub.subscribed) {
            await pub.subscribe();
          }
          final track = pub.track;
          if (track is RemoteAudioTrack && !track.muted) {
            await track.start();
          }
        } catch (e, s) {
          Logger.print('subscribe remote audio failed: $e $s');
        }
      }
      for (final pub in participant.videoTrackPublications) {
        if (pub.isScreenShare) continue;
        try {
          await pub.subscribe();
        } catch (_) {}
      }
    }
  }

  void _onRemoteParticipantLeft(Room room) {
    if (room.remoteParticipants.isNotEmpty) return;
    final roomID = currentRoomID;
    if (roomID == null || roomID.isEmpty) return;
    // Peer already left while we are still joining — abort (do NOT ICE-retry an empty room).
    if (_mediaConnectInFlight != null) {
      CallAudioDebugLog.add(
        'livekit',
        'remote left during connect — peer gone, abort join roomID=$roomID',
      );
      final abort = _connectAbort;
      if (abort != null && !abort.isCompleted) {
        abort.completeError(StateError('peer left during connect'));
      }
      PackageBridge.onPeerLeftCall?.call(roomID);
      return;
    }
    Logger.print('LiveKit remote participant left roomID=$roomID');
    CallAudioDebugLog.add('livekit', 'remote left — end call roomID=$roomID');
    PackageBridge.onPeerLeftCall?.call(roomID);
  }

  Future<void> _handleRoomDisconnected(
      Room room, RoomDisconnectedEvent event) async {
    final roomID = currentRoomID;
    Logger.print('Headless room disconnected: ${event.reason} roomID=$roomID');
    CallAudioDebugLog.add(
      'livekit',
      'disconnected reason=${event.reason} remotes=${room.remoteParticipants.length} roomID=$roomID',
    );

    // Connect still running — fail-fast so accept can retry with a clean Room
    // (do not sit on a dead PC until the full ICE timeout).
    if (_mediaConnectInFlight != null) {
      CallAudioDebugLog.add(
        'livekit',
        'disconnect during connect — abort join reason=${event.reason}',
      );
      final abort = _connectAbort;
      if (abort != null && !abort.isCompleted) {
        abort.completeError(
          MediaConnectException(
            'disconnect during connect: ${event.reason}',
          ),
        );
      }
      return;
    }

    // Peer hangup / room already ended / alone in room — never revive a zombie call.
    final roomEnded =
        roomID != null && PackageBridge.isCallRoomEnded?.call(roomID) == true;
    final alone = room.remoteParticipants.isEmpty;
    if (roomEnded || alone) {
      if (roomID != null && roomID.isNotEmpty) {
        PackageBridge.onPeerLeftCall?.call(roomID);
      }
      _dispatchRoomDisconnected();
      return;
    }

    if (roomID != null &&
        _liveKitReconnectAttempts < _maxLiveKitReconnectAttempts &&
        _isRecoverableDisconnect(event.reason)) {
      _liveKitReconnectAttempts++;
      final cert = _mediaCert;
      final liveURL = cert?.liveURL?.trim() ?? '';
      final token = cert?.token?.trim() ?? '';
      if (liveURL.isNotEmpty && token.isNotEmpty) {
        try {
          Logger.print(
              'LiveKit manual reconnect attempt $_liveKitReconnectAttempts roomID=$roomID');
          await room.connect(
            liveURL,
            token,
            roomOptions: RoomOptions(
              dynacast: true,
              adaptiveStream: true,
              defaultAudioCaptureOptions: const AudioCaptureOptions(
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
                highPassFilter: true,
              ),
              defaultAudioOutputOptions: AudioOutputOptions(
                speakerOn: _userSpeakerPreference ??
                    (_mediaCallType == CallType.video),
              ),
            ),
          );
          await _ensurePublished(
            callType: _mediaCallType ?? CallType.audio,
            speakerOn: _userSpeakerPreference ??
                (_mediaCallType == CallType.video),
            enableCamera: _mediaCallType == CallType.video,
            enableMicrophone: true,
          );
          await _subscribeRemoteTracks();
          _liveKitReconnectAttempts = 0;
          // Reconnected but peer gone — end call instead of empty forever-timer.
          if (room.remoteParticipants.isEmpty) {
            PackageBridge.onPeerLeftCall?.call(roomID);
            _dispatchRoomDisconnected();
          }
          return;
        } catch (e, s) {
          Logger.print('LiveKit manual reconnect failed: $e $s');
        }
      }
    }
    _dispatchRoomDisconnected();
  }

  bool _isRecoverableDisconnect(DisconnectReason? reason) {
    if (reason == null) return true;
    return reason != DisconnectReason.clientInitiated &&
        reason != DisconnectReason.duplicateIdentity;
  }

  void _dispatchRoomDisconnected() {
    _uiOnDisconnected?.call();
    final cb = _onMediaDisconnected;
    scheduleMicrotask(() => cb?.call());
  }

  /// Re-arm mic, speaker route, keepalive, and remote track subscribe after unlock.
  Future<void> restoreActiveCallAudio({bool? speakerOn}) async {
    await onCallActive(speakerOn: speakerOn, unmuteMic: true);
  }

  /// Lock-screen CallKit: republish mic + start remote playout after WebRTC bridge.
  Future<void> kickstartIosCallKitMedia({
    bool speakerOn = false,
    bool unmuteMic = true,
  }) async {
    if (!Platform.isIOS) return;
    if (_mediaConnectInFlight != null) {
      CallAudioDebugLog.add('kickstart', 'skip — connect in flight');
      return;
    }
    final room = _mediaRoom;
    if (room == null) {
      CallAudioDebugLog.add('kickstart', 'skip — no media room');
      return;
    }
    try {
      CallAudioDebugLog.add(
        'kickstart',
        'start unmuteMic=$unmuteMic speaker=$speakerOn remotes=${room.remoteParticipants.length}',
      );
      await onCallActive(speakerOn: speakerOn, unmuteMic: unmuteMic);
      if (unmuteMic) {
        final local = room.localParticipant;
        if (local != null) {
          if (local.isMicrophoneEnabled() == true) {
            await local.setMicrophoneEnabled(false);
          }
          await local.setMicrophoneEnabled(true);
        }
      }
      await _subscribeRemoteTracks();
      Logger.print(
          'kickstartIosCallKitMedia remotes=${room.remoteParticipants.length}');
      CallAudioDebugLog.add(
        'kickstart',
        'done remotes=${room.remoteParticipants.length} mic=${room.localParticipant?.isMicrophoneEnabled()}',
      );
    } catch (e, s) {
      Logger.print('kickstartIosCallKitMedia failed: $e $s');
      CallAudioDebugLog.add('kickstart', 'failed: $e');
    }
  }

  Future<void> _disposeMediaRoomOnly() async {
    final room = _mediaRoom;
    final listener = _mediaListener;
    _mediaRoom = null;
    _mediaListener = null;
    try {
      room?.removeListener(_noopRoomListener);
      await listener?.dispose();
      await room?.disconnect();
      await room?.dispose();
    } catch (_) {}
  }

  Future<void> _ensurePublished({
    required CallType callType,
    required bool speakerOn,
    required bool enableCamera,
    required bool enableMicrophone,
  }) async {
    final room = _mediaRoom;
    if (room == null) return;
    try {
      await Hardware.instance.setSpeakerphoneOn(speakerOn);
      await room.setSpeakerOn(speakerOn);
    } catch (e, s) {
      Logger.print('connectMedia speaker failed: $e $s');
    }
    try {
      await room.localParticipant?.setMicrophoneEnabled(enableMicrophone);
    } catch (e, s) {
      Logger.print('connectMedia mic failed: $e $s');
    }
    if (callType == CallType.video && enableCamera) {
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (e, s) {
        Logger.print('connectMedia camera failed: $e $s');
      }
    }
  }

  Future<void> _startKeepAlive(
    String roomID,
    CallType callType, {
    bool speakerOn = false,
  }) async {
    final keep = CallAudioKeepAlive.instance;
    keep.onNeedRepublishMic = () async {
      try {
        final p = _mediaRoom?.localParticipant;
        if (p == null) return;
        if (p.isMicrophoneEnabled() == true) {
          Logger.print('republish mic skipped: already enabled');
          return;
        }
        await p.setMicrophoneEnabled(true);
      } catch (e, s) {
        Logger.print('connectMedia republish mic failed: $e $s');
      }
    };
    await keep.start(
      roomID: roomID,
      isVideo: callType == CallType.video,
      speakerOn: speakerOn,
      skipSessionActivation: keep.callKitOwnsSession,
    );
  }

  void _wireRoomEvents(EventsListener<RoomEvent> listener, Room room) {
    listener
      ..on<LocalTrackPublishedEvent>((_) {
        _uiOnRoom?.call(room);
        unawaited(_subscribeRemoteTracks());
      })
      ..on<LocalTrackUnpublishedEvent>((_) => _uiOnRoom?.call(room))
      ..on<ParticipantConnectedEvent>((event) {
        CallAudioDebugLog.add(
          'livekit',
          'remote joined identity=${event.participant.identity} remotes=${room.remoteParticipants.length}',
        );
        _uiOnRemotePresent?.call();
        PackageBridge.markOutboundPeerPresent?.call(currentRoomID);
        unawaited(_subscribeRemoteTracks());
      })
      ..on<ParticipantDisconnectedEvent>((_) {
        _uiOnRemoteLeft?.call();
        _onRemoteParticipantLeft(room);
      })
      ..on<TrackSubscribedEvent>((event) {
        _uiOnRoom?.call(room);
        if (event.track is AudioTrack || event.track is VideoTrack) {
          unawaited(_subscribeRemoteTracks());
        }
      })
      ..on<TrackUnsubscribedEvent>((_) => _uiOnRoom?.call(room));
  }

  /// Bind UI listeners onto the shared media room (no second connect).
  void bindUiToMediaRoom({
    required void Function(Room room) onRoom,
    required VoidCallback onRemotePresent,
    required VoidCallback onRemoteLeft,
    required VoidCallback onDisconnected,
  }) {
    final room = _mediaRoom;
    if (room == null) return;

    _uiOnRoom = onRoom;
    _uiOnRemotePresent = onRemotePresent;
    _uiOnRemoteLeft = onRemoteLeft;
    _uiOnDisconnected = onDisconnected;

    if (_uiBoundRoomID == currentRoomID) {
      onRoom(room);
      if (room.remoteParticipants.isNotEmpty) {
        onRemotePresent();
      }
      return;
    }
    _uiBoundRoomID = currentRoomID;

    onRoom(room);
    if (room.remoteParticipants.isNotEmpty) {
      onRemotePresent();
    }

    room.addListener(() => _uiOnRoom?.call(room));
  }

  start(
    BuildContext ctx, {
    required PublishSubject<CallEvent> callEventSubject,
    String? roomID,
    CallState initState = CallState.call,
    CallType callType = CallType.video,
    CallObj callObj = CallObj.single,
    required String inviterUserID,
    required List<String> inviteeUserIDList,
    String? groupID,
    Future<SignalingCertificate> Function()? onDialSingle,
    Future<SignalingCertificate> Function()? onDialGroup,
    Future<SignalingCertificate> Function()? onJoinGroup,
    Future<SignalingCertificate> Function()? onTapPickup,
    Future Function()? onTapCancel,
    Future Function(int duration, bool isPositive)? onTapHangup,
    Future Function()? onTapReject,
    Future<UserInfo?> Function(String userID)? onSyncUserInfo,
    Future<GroupInfo?> Function(String groupID)? onSyncGroupInfo,
    Future<List<GroupMembersInfo>> Function(
            String groupID, List<String> memberIDList)?
        onSyncGroupMemberInfo,
    bool autoPickup = false,
    Function()? onWaitingAccept,
    Function()? onBusyLine,
    Function()? onStartCalling,
    Function(dynamic error, dynamic stack)? onError,
    Function()? onClose,
    Function()? onRoomDisconnected,
  }) {
    // Already showing UI — never replace mid-call.
    if (_holder != null) return;

    // Busy on a different room — ignore.
    if (isBusy &&
        currentRoomID != null &&
        roomID != null &&
        currentRoomID != roomID &&
        !hasMediaFor(roomID)) {
      return;
    }

    final mediaReady = hasMediaFor(roomID);
    // Headless media already up: show calling UI, do not re-pickup/reconnect.
    final effectiveInit =
        mediaReady ? CallState.calling : initState;
    final effectiveAutoPickup = mediaReady ? false : autoPickup;

    isBusy = true;
    currentRoomID = roomID ?? currentRoomID;
    _peerAcceptedForUi = false;
    this.onTapHangup = onTapHangup;

    FocusScope.of(ctx).requestFocus(FocusNode());

    _holder = OverlayEntry(
        builder: (context) => SingleRoomView(
              callType: callType,
              initState: effectiveInit,
              callEventSubject: callEventSubject,
              roomID: roomID ?? currentRoomID,
              userID: effectiveInit == CallState.call
                  ? inviteeUserIDList.first
                  : inviterUserID,
              onDial: callObj == CallObj.single ? onDialSingle : onDialGroup,
              onTapCancel: onTapCancel,
              onTapHangup: onTapHangup,
              onTapReject: onTapReject,
              onTapPickup: onTapPickup,
              onSyncUserInfo: onSyncUserInfo,
              autoPickup: effectiveAutoPickup,
              adoptExistingMedia: mediaReady,
              onBindRoomID: (id) => currentRoomID = id,
              onWaitingAccept: onWaitingAccept,
              onBusyLine: onBusyLine,
              onStartCalling: onStartCalling,
              onError: onError,
              onRoomDisconnected: onRoomDisconnected,
              onClose: () {
                onClose?.call();
                close();
              },
            ));

    Overlay.of(ctx).insert(_holder!);
    WakelockPlus.enable();
  }
}
