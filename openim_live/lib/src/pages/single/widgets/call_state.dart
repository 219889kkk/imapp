import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/utils/live_utils.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sprintf/sprintf.dart';

import '../../../../openim_live.dart';
import '../../../widgets/small_window.dart';
import 'controls.dart';
import 'participant.dart';

abstract class SignalView extends StatefulWidget {
  const SignalView({
    Key? key,
    required this.callType,
    required this.initState,
    this.roomID,
    required this.userID,
    required this.callEventSubject,
    this.onDial,
    this.onSyncUserInfo,
    this.onTapCancel,
    this.onTapHangup,
    this.onTapPickup,
    this.onTapReject,
    this.onClose,
    required this.autoPickup,
    this.onBindRoomID,
    this.onWaitingAccept,
    this.onBusyLine,
    this.onStartCalling,
    this.onError,
    this.onRoomDisconnected,
    this.adoptExistingMedia = false,
  }) : super(key: key);
  final CallType callType;
  final CallState initState;
  final String? roomID;
  final String userID;
  final PublishSubject<CallEvent> callEventSubject;
  final Future<SignalingCertificate> Function()? onDial;
  final Future<SignalingCertificate> Function()? onTapPickup;
  final Future Function()? onTapCancel;
  final Future Function(int duration, bool isPositive)? onTapHangup;
  final Future Function()? onTapReject;
  final Function()? onClose;
  final bool autoPickup;
  /// Lock-screen already joined LiveKit — UI only attaches, no reconnect.
  final bool adoptExistingMedia;
  final Function(String roomID)? onBindRoomID;
  final Function()? onWaitingAccept;
  final Function()? onBusyLine;
  final Function()? onStartCalling;
  final Function()? onRoomDisconnected;
  final Function(dynamic error, dynamic stack)? onError;
  final Future<UserInfo?> Function(String userID)? onSyncUserInfo;
}

abstract class SignalState<T extends SignalView> extends State<T>
    with WidgetsBindingObserver {
  final callStateSubject = BehaviorSubject<CallState>();
  final roomDidUpdateSubject = PublishSubject<Room>();
  late CallState callState;
  late SignalingCertificate certificate;
  String? roomID;
  UserInfo? userInfo;
  StreamSubscription? callEventSub;
  bool minimize = false;
  int duration = 0;
  bool enabledMicrophone = true;
  bool enabledSpeaker = true;

  ParticipantTrack? remoteParticipantTrack;
  ParticipantTrack? localParticipantTrack;

  @override
  void initState() {
    roomID ??= widget.roomID;
    callState = widget.initState;
    // Audio: earpiece by default; video: speaker for preview.
    enabledSpeaker = widget.callType == CallType.video;
    callEventSub = sameRoomSignalStream.listen(_onStateDidUpdate);
    widget.onSyncUserInfo?.call(widget.userID).then(_onUpdateUserInfo);
    WidgetsBinding.instance.addObserver(this);
    onDail();
    autoPickup();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    callStateSubject.close();
    callEventSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncUiAfterForeground();
    }
  }

  void _syncUiAfterForeground() {
    if (!mounted) return;
    final client = OpenIMLiveClient();
    if (client.isConnectedMedia(_callRoomID) &&
        callState != CallState.calling) {
      promoteInCallUi(reason: 'app-resumed');
    }
  }

  Stream<CallEvent> get sameRoomSignalStream =>
      widget.callEventSubject.stream.where((event) => LiveUtils.isSameRoom(event, roomID));

  _onUpdateUserInfo(UserInfo? info) {
    if (!mounted && null != info) return;
    setState(() {
      userInfo = info;
    });
  }

  _onStateDidUpdate(CallEvent event) {
    Logger.print("CallEvent current：$callState  event：$event");
    if (!mounted) {
      // Apply terminal events even when overlay was inactive (WeChat / lock screen).
      if (event.state == CallState.beRejected ||
          event.state == CallState.beCanceled ||
          event.state == CallState.beHangup ||
          event.state == CallState.timeout) {
        widget.onClose?.call();
      }
      return;
    }

    if (event.state == CallState.call ||
        event.state == CallState.beCalled ||
        event.state == CallState.connecting ||
        event.state == CallState.calling) {
      callStateSubject.add(event.state);
    }

    if (event.state == CallState.beRejected ||
        event.state == CallState.beCanceled ||
        event.state == CallState.beHangup) {
      // Peer ended the call — close local UI (do not send another hungup).
      widget.onClose?.call();
    } else if (event.state == CallState.otherReject ||
        event.state == CallState.otherAccepted) {
      if (existParticipants()) {
        return;
      }
      widget.onClose?.call();
      IMViews.showToast(sprintf(StrRes.otherCallHandle, [
        event.state == CallState.otherReject ? StrRes.rejectCall : StrRes.accept
      ]));
    } else if (event.state == CallState.timeout) {
      widget.onClose?.call();
    } else if (event.state == CallState.beAccepted) {
      // Caller: leave waiting UI — audio unmute handled in room/controller.
      onParticipantConnected();
    }
  }

  String? get _callRoomID => roomID ?? widget.roomID;

  /// Move UI off "connecting" once shared LiveKit media is live.
  void promoteInCallUi({String? reason}) {
    if (!mounted) return;
    if (callState == CallState.calling) return;
    final client = OpenIMLiveClient();
    if (!client.isConnectedMedia(_callRoomID)) return;
    Logger.print(
        'promote in-call UI reason=$reason from=$callState roomID=$_callRoomID');
    callState = CallState.calling;
    callStateSubject.add(CallState.calling);
    widget.onStartCalling?.call();
  }

  onParticipantConnected() {
    // Sync field so _deferMicrophone flips off before any re-_publish.
    promoteInCallUi(reason: 'peer-joined');
  }

  onParticipantDisconnected() {
    onTapHangup(false);
  }

  onDail() async {
    try {
      if (widget.initState == CallState.call) {
        if (!_isSessionActive()) return;
        certificate = await widget.onDial!.call();
        if (!_isSessionActive()) return;
        widget.onBindRoomID?.call(roomID = certificate.roomID!);
        if (!_isSessionActive()) return;
        await connect();
      } else if (widget.adoptExistingMedia ||
          widget.initState == CallState.calling) {
        // Unlock into an already-connected lock-screen call.
        if (!_isSessionActive()) return;
        await _adoptActiveCall();
      }
    } catch (e, s) {
      if (_sessionClosed) {
        Logger.print('onDail ignored after cancel/hangup: $e');
        return;
      }
      Logger.print('onDail failed: $e $s');
      widget.onError?.call(e, s);
    }
  }

  autoPickup() {
    if (widget.autoPickup) {
      onTapPickup();
    }
  }

  Future<void> _adoptActiveCall() async {
    final client = OpenIMLiveClient();
    final cert = client.mediaCertificate;
    if (cert != null) {
      certificate = cert;
      widget.onBindRoomID?.call(roomID = certificate.roomID!);
    } else if (!client.isConnectedMedia(_callRoomID)) {
      Logger.print('adoptActiveCall: no media to attach roomID=$_callRoomID');
      return;
    }
    await connect();
    promoteInCallUi(reason: 'adopt');
    Logger.print('adoptActiveCall attached roomID=$roomID');
  }

  bool _hangupBusy = false;
  bool _pickupBusy = false;
  bool _sessionClosed = false;

  bool _isSessionActive() => mounted && !_sessionClosed;

  onTapPickup() async {
    if (_pickupBusy || _hangupBusy) return;
    _pickupBusy = true;
    try {
      final client = OpenIMLiveClient();
      final target = roomID ?? widget.roomID;
      if (widget.adoptExistingMedia || client.hasMediaFor(target)) {
        await _adoptActiveCall();
        return;
      }

      Logger.print('accept from UI roomID=$target');
      callState = CallState.connecting;
      callStateSubject.add(CallState.connecting);
      // Unified pipeline: permissions + accept signal + token + LiveKit join.
      await widget.onTapPickup!.call();
      // Media is live after accept — leave "connecting" even if UI attach is slow.
      promoteInCallUi(reason: 'after-accept');
      try {
        await _adoptActiveCall();
      } catch (e, s) {
        Logger.print('adopt after accept failed: $e $s');
        promoteInCallUi(reason: 'adopt-error-fallback');
      }
      Logger.print('accept from UI attached roomID=$roomID');
    } catch (e, s) {
      Logger.print('onTapPickup failed: $e $s');
      final client = OpenIMLiveClient();
      final target = roomID ?? widget.roomID;
      if (client.hasMediaFor(target)) {
        try {
          await _adoptActiveCall();
          return;
        } catch (e2, s2) {
          Logger.print('adopt after pickup error failed: $e2 $s2');
          promoteInCallUi(reason: 'pickup-error-fallback');
          return;
        }
      }
      if (mounted && widget.initState == CallState.beCalled) {
        callState = CallState.beCalled;
        callStateSubject.add(CallState.beCalled);
      }
      widget.onError?.call(e, s);
    } finally {
      _pickupBusy = false;
      promoteInCallUi(reason: 'pickup-finally');
    }
  }

  onTapHangup(bool isPositive) {
    if (_hangupBusy) return;
    _hangupBusy = true;
    _sessionClosed = true;
    // Close UI immediately — don't wait for hangup signaling / VoIP.
    final hangup = widget.onTapHangup;
    final d = duration;
    unawaited(hangup?.call(d, isPositive) ?? Future.value());
    widget.onClose?.call();
  }

  onTapCancel() {
    if (_hangupBusy) return;
    _hangupBusy = true;
    _sessionClosed = true;
    final cancel = widget.onTapCancel;
    unawaited(cancel?.call() ?? Future.value());
    widget.onClose?.call();
  }

  onTapReject() {
    if (_hangupBusy) return;
    _hangupBusy = true;
    _sessionClosed = true;
    final reject = widget.onTapReject;
    unawaited(reject?.call() ?? Future.value());
    widget.onClose?.call();
  }

  onTapMinimize() {
    setState(() {
      minimize = true;
    });
  }

  onTapMaximize() {
    setState(() {
      minimize = false;
    });
  }

  callingDuration(int duration) {
    this.duration = duration;
  }

  onChangedMicStatus(bool enabled) {
    enabledMicrophone = enabled;
  }

  onChangedSpeakerStatus(bool enabled) {
    enabledSpeaker = enabled;
    OpenIMLiveClient().setUserSpeakerPreference(enabled);
  }

  //Alignment(0.9, -0.9),
  double alignX = 0.9;
  double alignY = -0.9;

  Alignment get moveAlign => Alignment(alignX, alignY);

  onMoveSmallWindow(DragUpdateDetails details) {
    final globalDy = details.globalPosition.dy;
    final globalDx = details.globalPosition.dx;
    setState(() {
      alignX = (globalDx - .5.sw) / .5.sw;
      alignY = (globalDy - .5.sh) / .5.sh;
    });
  }

  Future<void> connect();

  bool existParticipants();

  bool smallScreenIsRemote = true;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          AnimatedScale(
            scale: minimize ? 0 : 1,
            alignment: moveAlign,
            duration: const Duration(milliseconds: 200),
            onEnd: () {},
            child: Container(
              color: Styles.c_000000,
              child: Stack(
                children: [
                  // ImageRes.liveBg.toImage
                  //   ..fit = BoxFit.cover
                  //   ..width = 1.sw
                  //   ..height = 1.sh,
                  if (null != remoteParticipantTrack)
                    ParticipantWidget.widgetFor(smallScreenIsRemote ? remoteParticipantTrack! : localParticipantTrack!),

                  if (null != localParticipantTrack)
                    Positioned(
                      top: 97.h,
                      right: 12.w,
                      child: GestureDetector(
                        child: SizedBox(
                          width: 120.w,
                          height: 180.h,
                          child: ParticipantWidget.widgetFor(
                              smallScreenIsRemote ? localParticipantTrack! : remoteParticipantTrack!),
                        ),
                        onTap: () {
                          if (remoteParticipantTrack != null) {
                            setState(() {
                              smallScreenIsRemote = !smallScreenIsRemote;
                            });
                          }
                        },
                      ),
                    ),

                  ControlsView(
                    callStateStream: callStateSubject.stream,
                    roomDidUpdateStream: roomDidUpdateSubject.stream,
                    initState: widget.initState,
                    callType: widget.callType,
                    initialSpeakerOn: enabledSpeaker,
                    initialMicOn: enabledMicrophone,
                    userInfo: userInfo,
                    onMinimize: onTapMinimize,
                    onCallingDuration: callingDuration,
                    onEnabledMicrophone: onChangedMicStatus,
                    onEnabledSpeaker: onChangedSpeakerStatus,
                    onHangUp: onTapHangup,
                    onPickUp: onTapPickup,
                    onReject: onTapReject,
                    onCancel: onTapCancel,
                    onChangedCallState: (state) => callState = state,
                  ),
                ],
              ),
            ),
          ),
          if (minimize)
            Align(
              alignment: moveAlign,
              child: AnimatedOpacity(
                opacity: minimize ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SmallWindowView(
                  opacity: minimize ? 1 : 0,
                  userInfo: userInfo,
                  callState: callState,
                  onTapMaximize: onTapMaximize,
                  onPanUpdate: onMoveSmallWindow,
                  child: (state) {
                    // if (null != remoteParticipantTrack &&
                    //     state == CallState.calling &&
                    //     widget.callType == CallType.video) {
                    //   return SizedBox(
                    //     width: 120.w,
                    //     height: 180.h,
                    //     child: ParticipantWidget.widgetFor(
                    //         remoteParticipantTrack!),
                    //   );
                    // }
                    return null;
                  },
                ),
              ),
            ),
        ],
      );
}
