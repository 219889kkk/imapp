import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/widgets/live_button.dart';

import '../../../live_client.dart';
import '../../../widgets/loading_view.dart';

class ControlsView extends StatefulWidget {
  const ControlsView({
    Key? key,
    this.initState = CallState.call,
    this.callType = CallType.video,
    this.initialSpeakerOn,
    required this.callStateStream,
    required this.roomDidUpdateStream,
    this.userInfo,
    this.onMinimize,
    this.onCallingDuration,
    this.onEnabledMicrophone,
    this.onEnabledSpeaker,
    this.onCancel,
    this.onHangUp,
    this.onPickUp,
    this.onReject,
    this.onChangedCallState,
  }) : super(key: key);
  final Stream<Room> roomDidUpdateStream;
  final Stream<CallState> callStateStream;
  final CallState initState;
  final CallType callType;
  /// Prefer parent call-page speaker state (e.g. lock-screen forced speaker).
  final bool? initialSpeakerOn;
  final UserInfo? userInfo;
  final Function()? onMinimize;
  final Function(int duration)? onCallingDuration;
  final Function(bool enabled)? onEnabledMicrophone;
  final Function(bool enabled)? onEnabledSpeaker;
  final Function()? onPickUp;
  final Function()? onCancel;
  final Function()? onReject;
  final Function(bool isPositive)? onHangUp;
  final Function(CallState state)? onChangedCallState;

  @override
  State<ControlsView> createState() => _ControlsViewState();
}

class _ControlsViewState extends State<ControlsView> {
  late CallState _callState;
  Timer? _callingTimer;
  int _callingDuration = 0;
  String _callingDurationStr = "00:00";

  CameraPosition position = CameraPosition.front;

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;

  StreamSubscription<CallState>? _callStateChangedSub;
  StreamSubscription? _deviceChangeSub;
  StreamSubscription<Room>? _roomDidUpdateSub;

  Room? _room;
  LocalParticipant? _participant;

  bool _enabledMicrophone = true;
  bool _enabledCamera = true;

  late bool _enabledSpeaker;
  bool _speakerRouteApplied = false;
  int _speakerApplyGen = 0;
  bool _terminalActionBusy = false;
  bool _pickupPressed = false;
  bool _cameraBusy = false;

  @override
  void dispose() {
    _callStateChangedSub?.cancel();
    _roomDidUpdateSub?.cancel();
    _callingTimer?.cancel();
    _deviceChangeSub?.cancel();
    _participant?.removeListener(_onChange);
    super.dispose();
  }

  @override
  void initState() {
    _enabledSpeaker =
        widget.initialSpeakerOn ?? (widget.callType == CallType.video);
    _enabledCamera = widget.callType == CallType.video;
    _onChangedCallState(widget.initState);
    _callStateChangedSub = widget.callStateStream.listen(_onChangedCallState);
    _roomDidUpdateSub = widget.roomDidUpdateStream.listen(_roomDidUpdate);

    _deviceChangeSub =
        Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    Hardware.instance.enumerateDevices().then(_loadDevices);
    super.initState();
  }

  _roomDidUpdate(Room room) {
    _room ??= room;
    if (!_speakerRouteApplied) {
      _speakerRouteApplied = true;
      unawaited(_applySpeakerRoute(_enabledSpeaker));
    }
    if (room.localParticipant != null && _participant == null) {
      _participant = room.localParticipant;
      _participant?.addListener(_onChange);
    }
  }

  _onChangedCallState(CallState state) {
    if (!mounted) return;
    widget.onChangedCallState?.call(state);
    setState(() {
      _callState = state;
      if (_callState == CallState.beCalled) {
        // Allow retry after a failed answer attempt.
        _pickupPressed = false;
        _terminalActionBusy = false;
      }
      if (_callState == CallState.calling) {
        _startCallingTimer();
      }
    });
  }

  void _startCallingTimer() {
    _callingTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _callingDurationStr = IMUtils.seconds2HMS(++_callingDuration);
        widget.onCallingDuration?.call(_callingDuration);
      });
    });
  }

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
  }

  void _onChange() {
    setState(() {});
  }

  void _toggleAudio() async {
    final next = !_enabledMicrophone;
    setState(() => _enabledMicrophone = next);
    widget.onEnabledMicrophone?.call(next);
    try {
      if (next) {
        await _enableAudio();
      } else {
        await _disableAudio();
      }
    } catch (e, s) {
      Logger.print('toggle mic failed: $e $s');
    }
  }

  void _toggleSpeaker() {
    final next = !_enabledSpeaker;
    // Optimistic UI — don't wait for native route before flipping the icon.
    setState(() => _enabledSpeaker = next);
    widget.onEnabledSpeaker?.call(next);
    OpenIMLiveClient().setUserSpeakerPreference(next);
    unawaited(_applySpeakerRoute(next));
  }

  void _onHangUpPressed() {
    if (_terminalActionBusy) return;
    _terminalActionBusy = true;
    widget.onHangUp?.call(true);
  }

  void _onCancelPressed() {
    if (_terminalActionBusy) return;
    _terminalActionBusy = true;
    widget.onCancel?.call();
  }

  void _onRejectPressed() {
    if (_terminalActionBusy) return;
    _terminalActionBusy = true;
    widget.onReject?.call();
  }

  void _onPickUpPressed() {
    // Do NOT set _terminalActionBusy — user must still be able to hang up
    // if LiveKit connect is slow/stuck after answering.
    if (_pickupPressed) return;
    _pickupPressed = true;
    widget.onPickUp?.call();
  }

  Future<void> _applySpeakerRoute(bool on) async {
    final gen = ++_speakerApplyGen;
    try {
      await Hardware.instance.setSpeakerphoneOn(on);
      if (gen != _speakerApplyGen) return;
      await _room?.setSpeakerOn(on);
      if (gen != _speakerApplyGen) return;
      // iOS/CallKit sometimes snaps route back — reinforce once.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (gen != _speakerApplyGen || !mounted) return;
      if (_enabledSpeaker != on) return;
      await Hardware.instance.setSpeakerphoneOn(on);
      await _room?.setSpeakerOn(on);
    } catch (e, s) {
      Logger.print('apply speaker failed: $e $s');
    }
  }

  Future<void> _disableAudio() async {
    await _participant?.setMicrophoneEnabled(false);
  }

  Future<void> _enableAudio() async {
    await _participant?.setMicrophoneEnabled(true);
  }

  Future<void> _disableVideo() async {
    await _participant?.setCameraEnabled(false);
  }

  Future<void> _enableVideo() async {
    await _participant?.setCameraEnabled(true,
        cameraCaptureOptions: CameraCaptureOptions(cameraPosition: position));
  }

  void _toggleCameraEnabled() {
    if (_cameraBusy) return;
    final next = !_enabledCamera;
    setState(() => _enabledCamera = next);
    _cameraBusy = true;
    unawaited(() async {
      try {
        if (next) {
          await _enableVideo();
        } else {
          await _disableVideo();
        }
      } catch (e, s) {
        Logger.print('toggle camera failed: $e $s');
        if (mounted) setState(() => _enabledCamera = !next);
      } finally {
        _cameraBusy = false;
      }
    }());
  }

  void _toggleCamera() {
    final track = _participant?.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    unawaited(Helper.switchCamera(track.mediaStreamTrack));
  }

  Widget _topIconButton({
    required String icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22.r),
        child: Padding(
          padding: EdgeInsets.all(10.w),
          child: icon.toImage
            ..width = 30.w
            ..height = 30.h,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 6.w,
              top: 0,
              child: _topIconButton(
                icon: ImageRes.liveClose,
                onTap: widget.onMinimize,
              ),
            ),
            if (null != _participant)
              Positioned(
                right: 6.w,
                top: 0,
                child: Visibility(
                  visible: isVideo,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _topIconButton(
                        icon: _enabledCamera
                            ? ImageRes.liveCameraOff
                            : ImageRes.liveCameraOn,
                        onTap: _toggleCameraEnabled,
                      ),
                      _topIconButton(
                        icon: ImageRes.liveSwitchCamera,
                        onTap: _toggleCamera,
                      ),
                    ],
                  ),
                ),
              ),
            if (null != widget.userInfo)
              Positioned(
                top: 166.h,
                width: 1.sw,
                child: _userInfoView,
              ),
            Positioned(
              bottom: 32.h,
              width: 1.sw,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buttonGroup,
              ),
            ),
            Positioned(
              bottom: 156.h,
              width: 1.sw,
              child: Center(child: _videoCallingDurationView),
            ),
            if (_callState == CallState.connecting)
              const Positioned.fill(
                // Must not block cancel/hangup taps underneath.
                child: IgnorePointer(child: LiveLoadingView()),
              ),
          ],
        ),
      );

  List<Widget> get _buttonGroup {
    // Outbound ringing / connecting as caller.
    if (_callState == CallState.call ||
        (_callState == CallState.connecting &&
            widget.initState == CallState.call)) {
      return [
        LiveButton.microphone(on: _enabledMicrophone, onTap: _toggleAudio),
        LiveButton.cancel(onTap: _onCancelPressed),
        LiveButton.speaker(on: _enabledSpeaker, onTap: _toggleSpeaker),
      ];
    }
    // Incoming ringing — not yet answered.
    if (_callState == CallState.beCalled) {
      return [
        LiveButton.reject(onTap: _onRejectPressed),
        LiveButton.pickUp(onTap: _onPickUpPressed),
      ];
    }
    // Answered / in-call (incl. connecting after pickup) — always show hangup.
    if (_callState == CallState.calling ||
        _callState == CallState.connecting) {
      return [
        LiveButton.microphone(on: _enabledMicrophone, onTap: _toggleAudio),
        LiveButton.hungUp(onTap: _onHangUpPressed),
        LiveButton.speaker(on: _enabledSpeaker, onTap: _toggleSpeaker),
      ];
    }
    return [];
  }

  bool get isVideo => widget.callType == CallType.video;

  bool get isCalling => _callState == CallState.calling;

  Widget get _videoCallingDurationView => Visibility(
        visible: isVideo && isCalling,
        child: _callingDurationStr.toText
          ..style = Styles.ts_FFFFFF_opacity70_17sp,
      );

  Widget get _userInfoView {
    String text;
    if (_callState == CallState.call) {
      text = isVideo ? StrRes.waitingVideoCallHint : StrRes.waitingVoiceCallHint;
    } else if (_callState == CallState.beCalled) {
      text = isVideo ? StrRes.invitedVideoCallHint : StrRes.invitedVoiceCallHint;
    } else if (_callState == CallState.connecting) {
      text = StrRes.connecting;
    } else {
      text = isVideo ? '' : _callingDurationStr;
    }

    String? nickname =
        IMUtils.emptyStrToNull(widget.userInfo!.remark) ??
            widget.userInfo!.nickname;
    String? faceURL = widget.userInfo!.faceURL;

    return Visibility(
      visible: !(isVideo && isCalling),
      child: Column(
        children: [
          AvatarView(width: 70.w, height: 70.h, text: nickname, url: faceURL),
          10.verticalSpace,
          (nickname ?? '').toText..style = Styles.ts_FFFFFF_20sp_medium,
          10.verticalSpace,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: text.toText
              ..style = Styles.ts_FFFFFF_opacity70_17sp
              ..maxLines = 1
              ..overflow = TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
