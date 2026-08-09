import 'dart:async';

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
  VoidCallback? _onMediaDisconnected;
  /// Last speaker choice from the in-call button (wins over delayed reinforce).
  bool? _userSpeakerPreference;
  String? _uiBoundRoomID;

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

  close() {
    if (_holder != null) {
      _holder?.remove();
      _holder = null;
    }
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
    bool speakerOn = true,
    bool enableCamera = false,
    bool enableMicrophone = true,
    /// Caller waiting for answer: skip keepalive so ringback isn't ducked.
    bool enableKeepAlive = true,
    VoidCallback? onDisconnected,
  }) async {
    final roomID = certificate.roomID?.trim() ?? '';
    if (roomID.isEmpty) {
      throw StateError('connectMedia: empty roomID');
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
  }) async {
    final roomID = certificate.roomID!;
    final busyLineUsers = certificate.busyLineUserIDList ?? [];
    if (busyLineUsers.isNotEmpty) {
      throw StateError('busy line');
    }

    if (_mediaRoom != null && currentRoomID != roomID) {
      await _disposeMedia();
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

    // Audio session MUST be ready before LiveKit connects, otherwise both
    // lock-screen and in-app calls can join a room with silent playback.
    await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: speakerOn);

    final room = Room();
    final listener = room.createListener();
    _mediaRoom = room;
    _mediaListener = listener;
    _mediaCert = certificate;
    _mediaCallType = callType;
    isBusy = true;
    currentRoomID = roomID;

    listener.on<RoomDisconnectedEvent>((event) {
      Logger.print('Headless room disconnected: ${event.reason}');
      _uiOnDisconnected?.call();
      final cb = _onMediaDisconnected;
      scheduleMicrotask(() => cb?.call());
    });

    _wireRoomEvents(listener, room);

    Logger.print(
        'connectMedia connecting roomID=$roomID url=${certificate.liveURL}');
    final liveURL = certificate.liveURL?.trim() ?? '';
    final token = certificate.token?.trim() ?? '';
    if (liveURL.isEmpty || token.isEmpty) {
      throw StateError('missing liveURL/token for roomID=$roomID');
    }
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
        defaultAudioOutputOptions: AudioOutputOptions(speakerOn: speakerOn),
        defaultCameraCaptureOptions: const CameraCaptureOptions(
          params: VideoParametersPresets.h720_169,
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: true,
          videoCodec: 'VP9',
          videoEncoding: const VideoEncoding(
            maxBitrate: 5 * 1000 * 1000,
            maxFramerate: 15,
          ),
        ),
      ),
    );

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
        await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: speakerOn);
        await Hardware.instance.setSpeakerphoneOn(speakerOn);
        await room.setSpeakerOn(speakerOn);
      } catch (_) {}
    }
    WakelockPlus.enable();
    Logger.print('connectMedia connected roomID=$roomID keepAlive=$enableKeepAlive');
  }

  /// Start mic/CallKit keepalive after peer joins (caller left wait-ring state).
  Future<void> ensureCallKeepAlive({bool? speakerOn}) async {
    final roomID = currentRoomID;
    final callType = _mediaCallType ?? CallType.audio;
    if (roomID == null || roomID.isEmpty) return;
    // Match in-call UI default: speaker on unless user toggled earpiece.
    final on = speakerOn ?? _userSpeakerPreference ?? true;
    await _startKeepAlive(roomID, callType, speakerOn: on);
    await ensureMediaAudible(speakerOn: on, forceRestartMic: true);
  }

  /// Make sure remote audio is subscribed and local route/mic are live.
  Future<void> ensureMediaAudible({
    bool? speakerOn,
    bool forceRestartMic = false,
  }) async {
    final room = _mediaRoom;
    if (room == null) return;
    // Default speaker on so answered calls are audible without earpiece.
    final on = speakerOn ?? _userSpeakerPreference ?? true;
    try {
      await CallAudioKeepAlive.instance.prepareForRtc(speakerOn: on);
      await Hardware.instance.setSpeakerphoneOn(on);
      await room.setSpeakerOn(on);
      final local = room.localParticipant;
      if (local != null) {
        if (forceRestartMic && local.isMicrophoneEnabled() == true) {
          await local.setMicrophoneEnabled(false);
        }
        await local.setMicrophoneEnabled(true);
      }
      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          try {
            await pub.subscribe();
          } catch (_) {}
        }
        for (final pub in participant.videoTrackPublications) {
          if (pub.isScreenShare) continue;
          try {
            await pub.subscribe();
          } catch (_) {}
        }
      }
      Logger.print(
          'ensureMediaAudible speaker=$on remotes=${room.remoteParticipants.length} forceMic=$forceRestartMic');
    } catch (e, s) {
      Logger.print('ensureMediaAudible failed: $e $s');
    }
  }

  /// Lock-screen answer: force audible route + mic + remote audio subscribe.
  Future<void> reinforceLockScreenAudio({bool speakerOn = true}) async {
    final roomID = currentRoomID;
    if (roomID == null || roomID.isEmpty) return;
    final prefer = _userSpeakerPreference ?? speakerOn;
    await _startKeepAlive(
      roomID,
      _mediaCallType ?? CallType.audio,
      speakerOn: prefer,
    );
    // Once after lock-screen accept — avoid repeated mic off/on (causes harsh pops).
    await ensureMediaAudible(speakerOn: prefer, forceRestartMic: false);
    final room = _mediaRoom;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 150), () async {
      if (_mediaRoom != room || room == null) return;
      final on = _userSpeakerPreference ?? prefer;
      await ensureMediaAudible(speakerOn: on, forceRestartMic: false);
    }));
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
    bool speakerOn = true,
  }) async {
    final keep = CallAudioKeepAlive.instance;
    keep.onNeedRepublishMic = () async {
      try {
        final p = _mediaRoom?.localParticipant;
        if (p == null) return;
        if (p.isMicrophoneEnabled() == true) {
          await p.setMicrophoneEnabled(false);
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
    );
  }

  void _wireRoomEvents(EventsListener<RoomEvent> listener, Room room) {
    listener
      ..on<LocalTrackPublishedEvent>((_) {
        _uiOnRoom?.call(room);
        unawaited(_armRemoteAudio());
      })
      ..on<LocalTrackUnpublishedEvent>((_) => _uiOnRoom?.call(room))
      ..on<ParticipantConnectedEvent>((_) {
        _uiOnRemotePresent?.call();
        unawaited(_armRemoteAudio(forceMic: true));
      })
      ..on<ParticipantDisconnectedEvent>((_) => _uiOnRemoteLeft?.call())
      ..on<TrackSubscribedEvent>((event) {
        _uiOnRoom?.call(room);
        if (event.track is AudioTrack || event.track is VideoTrack) {
          unawaited(_armRemoteAudio());
        }
      })
      ..on<TrackUnsubscribedEvent>((_) => _uiOnRoom?.call(room));
  }

  /// Subscribe remote audio + unmute as soon as LiveKit has tracks (don't wait IM).
  Future<void> _armRemoteAudio({bool forceMic = false}) async {
    final on = _userSpeakerPreference ?? true;
    await ensureMediaAudible(
      speakerOn: on,
      forceRestartMic: forceMic,
    );
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
