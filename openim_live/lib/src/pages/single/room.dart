import 'dart:async';

import 'package:collection/collection.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';

import '../../live_client.dart';
import '../../utils/call_audio_keepalive.dart';
import 'widgets/call_state.dart';
import 'widgets/participant.dart';

class SingleRoomView extends SignalView {
  const SingleRoomView({
    super.key,
    required super.callType,
    required super.initState,
    required super.userID,
    required super.callEventSubject,
    required super.autoPickup,
    super.roomID,
    super.onClose,
    super.onBindRoomID,
    super.onBusyLine,
    super.onDial,
    super.onStartCalling,
    super.onTapCancel,
    super.onTapHangup,
    super.onTapPickup,
    super.onTapReject,
    super.onWaitingAccept,
    super.onSyncUserInfo,
    super.onError,
    super.onRoomDisconnected,
    super.adoptExistingMedia = false,
  });

  @override
  SignalState<SingleRoomView> createState() => _SingleRoomViewState();
}

class _SingleRoomViewState extends SignalState<SingleRoomView> {
  Room? _room;
  bool _sharedMediaAttached = false;
  Timer? _remoteLeaveTimer;
  Timer? _disconnectCloseTimer;

  @override
  void dispose() {
    _remoteLeaveTimer?.cancel();
    _disconnectCloseTimer?.cancel();
    // Media room is owned by OpenIMLiveClient — do not disconnect here.
    // Otherwise unlocking into the app would tear down an active lock-screen call.
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomDidUpdate);
    }
    _room = null;
    super.dispose();
  }

  @override
  Future<void> connect() async {
    final client = OpenIMLiveClient();
    final targetRoomID = certificate.roomID ?? roomID ?? widget.roomID;
    if (PackageBridge.isCallRoomEnded?.call(targetRoomID) == true) {
      Logger.print('connect aborted: room ended $targetRoomID');
      return;
    }

    // Already talking from lock-screen / headless accept — attach only.
    if (widget.adoptExistingMedia || client.hasMediaFor(targetRoomID)) {
      await _attachSharedMedia(client);
      return;
    }

    final speakerOn = enabledSpeaker;
    // Caller waiting for answer: join room but skip CallKit/keepalive so
    // ringback isn't ducked and no lock-screen "ongoing call" is created.
    final waitingForPeer = widget.initState == CallState.call;
    await client.connectMedia(
      certificate: certificate,
      callType: widget.callType,
      speakerOn: speakerOn,
      enableCamera: widget.callType == CallType.video && !waitingForPeer,
      // Waiting caller: mute mic so ringback doesn't feedback.
      enableMicrophone: !waitingForPeer,
      enableKeepAlive: !waitingForPeer,
      onDisconnected: _onLiveKitDisconnected,
    );
    await _attachSharedMedia(client);
    if (CallState.call == callState || CallState.connecting == callState) {
      widget.onWaitingAccept?.call();
    }
  }

  Future<void> _attachSharedMedia(OpenIMLiveClient client) async {
    final room = client.mediaRoom;
    final cert = client.mediaCertificate;
    if (room == null || cert == null) {
      throw StateError('no shared media room to attach');
    }
    if (_sharedMediaAttached) {
      _room = room;
      _sortParticipants();
      _syncMicStateFromRoom();
      roomDidUpdateSubject.add(room);
      if (room.remoteParticipants.isNotEmpty) {
        onParticipantConnected();
      }
      return;
    }
    _sharedMediaAttached = true;
    certificate = cert;
    roomID = cert.roomID ?? roomID;
    widget.onBindRoomID?.call(roomID!);
    _room = room;

    room.addListener(_onRoomDidUpdate);
    _sortParticipants();
    roomDidUpdateSubject.add(room);

    client.bindUiToMediaRoom(
      onRoom: (r) {
        if (!mounted) return;
        _room = r;
        _sortParticipants();
        roomDidUpdateSubject.add(r);
      },
      onRemotePresent: () {
        if (!mounted) return;
        onParticipantConnected();
      },
      onRemoteLeft: () {
        if (!mounted) return;
        onParticipantDisconnected();
      },
      onDisconnected: _onLiveKitDisconnected,
    );

    // Ensure tracks still published after unlock / in-app join.
    // If peer already joined (or we already left waiting state), unmute now.
    await _publish();
    _syncMicStateFromRoom();
    if (!_deferMicrophone) {
      await OpenIMLiveClient().onCallActive(
        speakerOn: enabledSpeaker,
        unmuteMic: enabledMicrophone,
      );
      _syncMicStateFromRoom();
    } else {
      // Waiting: route only — do not unmute over deferred mic.
      try {
        await Hardware.instance.setSpeakerphoneOn(enabledSpeaker);
        await room.setSpeakerOn(enabledSpeaker);
      } catch (_) {}
    }
    if (room.remoteParticipants.isNotEmpty) {
      onParticipantConnected();
    } else if (callState == CallState.connecting) {
      // Callee: LiveKit is up even if peer track arrives a moment later.
      promoteInCallUi(reason: 'attach-no-remote-yet');
    } else if (widget.initState == CallState.call &&
        OpenIMLiveClient().peerAcceptedForUi) {
      promoteInCallUi(reason: 'attach-after-accept', force: true);
    }
    unawaited(_refreshCallAudio());
    _notifyRoomUi();
  }

  Future<void> _refreshCallAudio() async {
    final client = OpenIMLiveClient();
    if (!client.isBusy || _room == null) return;
    final unmute = enabledMicrophone && !_deferMicrophone;
    await client.onCallActive(speakerOn: enabledSpeaker, unmuteMic: unmute);
    if (!mounted) return;
    _syncMicStateFromRoom();
    if (!mounted) return;
    _notifyRoomUi();
  }

  void _onLiveKitDisconnected() {
    if (!mounted) return;
    widget.onRoomDisconnected?.call();
    _disconnectCloseTimer?.cancel();
    _disconnectCloseTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final room = _room;
      if (room?.connectionState == ConnectionState.connected) return;
      if (room?.remoteParticipants.isNotEmpty == true) return;
      widget.onClose?.call();
    });
  }

  void _syncMicStateFromRoom() {
    final mic = _room?.localParticipant?.isMicrophoneEnabled();
    if (mic == null) return;
    enabledMicrophone = mic;
  }

  void _notifyRoomUi() {
    final room = _room;
    if (room != null) roomDidUpdateSubject.add(room);
  }

  /// Caller still waiting for answer: keep mic off while ring plays.
  bool get _deferMicrophone =>
      widget.initState == CallState.call && callState != CallState.calling;

  Future<void> _applySpeakerRoute() async {
    final speakerOn = enabledSpeaker;
    try {
      await Hardware.instance.setSpeakerphoneOn(speakerOn);
      await _room?.setSpeakerOn(speakerOn);
    } catch (error, stackTrace) {
      Logger.print('could not set speaker: $error $stackTrace');
    }
  }

  Future<void> _publish() async {
    await _applySpeakerRoute();
    try {
      final enabled = widget.callType == CallType.video && !_deferMicrophone;
      await _room?.localParticipant?.setCameraEnabled(enabled);
    } catch (error, stackTrace) {
      Logger.print('could not publish video: $error $stackTrace');
    }
    try {
      final micOn = enabledMicrophone && !_deferMicrophone;
      await _room?.localParticipant?.setMicrophoneEnabled(micOn);
    } catch (error, stackTrace) {
      Logger.print('could not publish audio: $error $stackTrace');
    }
  }

  @override
  void onParticipantConnected() {
    _remoteLeaveTimer?.cancel();
    _disconnectCloseTimer?.cancel();
    if (_deferMicrophone) {
      promoteInCallUi(reason: 'remote-joined-livekit');
    }
    super.onParticipantConnected();
    if (widget.callType == CallType.video) {
      unawaited(_publish());
    }
    unawaited(_refreshCallAudio());
  }

  @override
  void onParticipantDisconnected() {
    if (callState != CallState.calling) return;
    _remoteLeaveTimer?.cancel();
    _remoteLeaveTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final room = _room;
      if (room?.connectionState == ConnectionState.connected &&
          room!.remoteParticipants.isNotEmpty) {
        return;
      }
      if (room?.remoteParticipants.isEmpty ?? true) {
        onTapHangup(false);
      }
    });
  }

  void _onRoomDidUpdate() {
    _sortParticipants();
    if (null != _room) roomDidUpdateSubject.add(_room!);
  }

  void _sortParticipants() {
    if (null == _room) return;

    final localParticipant = _room!.localParticipant;
    if (null != localParticipant) {
      VideoTrack? videoTrack;
      for (var t in localParticipant.videoTrackPublications) {
        if (!t.isScreenShare) {
          videoTrack = t.track;
          break;
        }
      }
      localParticipantTrack = ParticipantTrack(
        participant: localParticipant,
        videoTrack: videoTrack,
        isScreenShare: false,
      );
    }

    final participant = _room!.remoteParticipants.values.firstOrNull;
    if (null != participant) {
      VideoTrack? videoTrack;
      for (var t in participant.videoTrackPublications) {
        if (!t.isScreenShare) {
          videoTrack = t.track;
          break;
        }
      }
      remoteParticipantTrack = ParticipantTrack(
        participant: participant,
        videoTrack: videoTrack,
        isScreenShare: false,
      );
    }

    if (mounted) setState(() {});
  }

  @override
  bool existParticipants() {
    return _room?.remoteParticipants.isNotEmpty == true;
  }
}
