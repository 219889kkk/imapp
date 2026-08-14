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
        // Callee pre-joined LiveKit while ringing — keep incoming UI, do not
        // promote to in-call (that would unmute and start the timer).
        if (OpenIMLiveClient().hasRingingPrejoin &&
            !_answeredRoomUntilMs.containsKey(roomID) &&
            !_isAcceptInProgressForRoom(roomID)) {
          Logger.print('ignore invite: ringing prejoin roomID=$roomID');
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
    // Keep answered so a late invite / CallKit Timeout cannot re-open this room
    // after the callee already hung up (lock-screen answer → hangup → invite).
    if (!_answeredRoomUntilMs.containsKey(id)) {
      _answeredRoomUntilMs[id] =
          DateTime.now().millisecondsSinceEpoch + _endedRoomTtlMs;
    }
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
    if (_endedRoomUntilMs.containsKey(id)) return true;
    return VoipCallkitController.toOrNull?.isNativelyEnded(id) == true;
  }

  bool _sameCallRoom(String a, String b) {
    if (a == b) return true;
    final x = a.toLowerCase().replaceAll('-', '');
    final y = b.toLowerCase().replaceAll('-', '');
    return x.isNotEmpty && x == y;
  }

  /// Wall-clock from answer — UI timer alone often stays 0 on CallKit/headless.
  int? _callConnectedAtMs;

  void _markCallConnected() {
    _callConnectedAtMs ??= DateTime.now().millisecondsSinceEpoch;
  }

  int _talkingPromoteGen = 0;

  /// After answer: show 连接中 until audio is actually up, then start the timer.
  void _beginAnsweredConnecting(SignalingInfo signaling) {
    signalingSubject.add(CallEvent(CallState.connecting, signaling));
    unawaited(_promoteTalkingWhenMediaReady(signaling));
  }

  Future<void> _promoteTalkingWhenMediaReady(SignalingInfo signaling) async {
    final gen = ++_talkingPromoteGen;
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    final deadline = DateTime.now().add(const Duration(milliseconds: 2800));
    while (gen == _talkingPromoteGen && !_isRoomEnded(roomID)) {
      final client = OpenIMLiveClient();
      final media = client.hasMediaFor(roomID) || client.isConnectedMedia(roomID);
      var audioUp = !Platform.isIOS;
      if (Platform.isIOS) {
        audioUp = _iosCallKitDidActivateNative ||
            await IosWebRtcAudio.isEnabled();
      }
      if (media && audioUp) break;
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (gen != _talkingPromoteGen || _isRoomEnded(roomID)) return;
    _markCallConnected();
    signalingSubject.add(CallEvent(CallState.calling, signaling));
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
    final id = roomID?.trim() ?? '';
    final active = _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    // Ghost / stale CallKit UUID must not wipe a *connected* live call.
    if (id.isNotEmpty &&
        active.isNotEmpty &&
        !_sameCallRoom(id, active) &&
        (_userHasAnsweredCall(active) || _isAcceptInProgressForRoom(active))) {
      CallAudioDebugLog.add(
          'callkit', 'terminate ignored — room mismatch id=$id active=$active');
      unawaited(
          VoipCallkitController.toOrNull?.endCall(id) ?? Future.value());
      return;
    }
    _markRoomEnded(id.isNotEmpty ? id : active);
    if (active.isNotEmpty) _markRoomEnded(active);
    if (id.isNotEmpty) _peerAcceptedRooms.remove(id);
    if (active.isNotEmpty) _peerAcceptedRooms.remove(active);
    _callConnectedAtMs = null;
    _talkingPromoteGen++;
    _clearPickupCache();
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
    _autoPickup = false;
    _pendingHeadlessMicPermission = false;
    _iosCallKitAudioActivated = false;
    _iosCallKitDidActivateNative = false;
    _callKitAcceptHandledRoomID = null;
    if (id.isNotEmpty) _callKitAcceptAtMs.remove(id);
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
    _suppressCallKitEnded(id.isNotEmpty ? id : active, duration: const Duration(seconds: 2));
    if (active.isNotEmpty) {
      _suppressCallKitEnded(active, duration: const Duration(seconds: 2));
    }
    final closeId = id.isNotEmpty ? id : active;
    unawaited(_endSystemCallUi(closeId));
    if (closeId.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(closeId);
    } else {
      OpenIMLiveClient().close();
    }
  }

  /// End CallKit / system incoming UI. Always wipe leftovers on terminate —
  /// ringing prejoin and UUID mismatch left a lock-screen call in the switcher.
  Future<void> _endSystemCallUi(String? roomID) async {
    final voip = VoipCallkitController.toOrNull;
    if (voip == null) return;
    final id = roomID?.trim() ?? '';
    if (id.isNotEmpty) {
      await voip.endCall(id);
    }
    await voip.endAllCalls(roomID: id.isEmpty ? null : id);
  }

  final backgroundSubject = PublishSubject<bool>();

  final insertSignalingMessageSubject = PublishSubject<CallEvent>();

  /// One chat-record / one cancel-to-caller per missed room.
  final Set<String> _missNotifiedRooms = {};

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

  // --- iOS 被叫：三个状态 × 接听 / 终止 / 超时（每次改通话都必须三种都过）---
  //
  // 1. 锁屏被叫          → 只有系统 CallKit
  // 2. 解锁但不在航讯     → 只有系统 CallKit（桌面 / Safari / 别的 App）
  // 3. 双方都在航讯前台   → 只有应用内全屏邀请，不要 CallKit 顶栏
  //
  // 接听：1/2 走 CallKit Answer（callingAccept + LiveKit，系统通话页保持到挂断）
  //       3 走应用内接听（关掉任何 CallKit，应用内音频）
  // 终止：本端或对端挂断 → 应用内页面关掉，同时 kill 全部 CallKit（响铃 UUID + 接通后的计时 UUID）
  // 超时/未接：三种都要 callingCancel 通知主叫；进 App 不得重放已结束邀请
  // 主叫：自己呼出不要来电横幅；不要给主叫发 VoIP accept。
  // 状态 3 判定：原生 alreadyInHangXunForeground（前台>0.8s），禁止用 VoIP 唤醒的 resumed。

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
      {Duration duration = const Duration(seconds: 4)}) {
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

  /// Keep system CallKit audio only when the user answered via CallKit
  /// (lock / top banner). In-app overlay pickup must dismiss CallKit and
  /// take over AVAudioSession — otherwise the timer runs with no sound.
  bool _shouldKeepCallKitAudio([String? roomID]) {
    final id = (roomID ??
            _activeCallSignaling?.invitation?.roomID ??
            OpenIMLiveClient().currentRoomID)
        ?.trim() ??
        '';
    if (_isRoomEnded(id)) return false;
    if (id.isEmpty) {
      return _callKitAcceptHandledRoomID != null || _iosCallKitDidActivateNative;
    }
    return _callKitAcceptHandledRoomID == id || _iosCallKitDidActivateNative;
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
    final voip = VoipCallkitController.toOrNull;
    await voip?.endCall(id);
    // endCall(roomID) misses a different CXCall UUID — leftover top banner /
    // app-switcher call UI. Unanswered only (answered path never calls this).
    await voip?.endAllCalls(roomID: id);
  }

  /// 状态 3：航讯在前台超过 0.8s。VoIP 唤醒瞬间的 resumed 仍算不在 App（走 CallKit）。
  bool _iosCalleeIsInHangXun() {
    if (!Platform.isIOS) return true;
    if (_isRunningBackground) return false;
    return VoipCallkitController.toOrNull?.inHangXunForeground == true;
  }

  /// 状态 1/2 用 CallKit；状态 3 用应用内全屏。
  /// Native 已经弹出系统来电时，即使 Flutter 被 VoIP 唤醒成 resumed 也要保住 CallKit。
  bool _iosShouldUseCallKitForRing(String? roomID) {
    if (!Platform.isIOS) return false;
    if (roomID != null && _isRoomEnded(roomID)) return false;
    if (_autoPickup || _isAcceptInProgressForRoom(roomID)) return false;
    final voip = VoipCallkitController.toOrNull;
    final incoming = voip?.incomingRoomID?.trim() ?? '';
    final id = roomID?.trim() ?? '';
    if (voip?.ownsIncomingUi == true) return true;
    if (id.isNotEmpty && incoming == id) return true;
    return !_iosCalleeIsInHangXun();
  }

  /// Prefetch/prejoin occupies LiveKit while still ringing. That is not an answer.
  bool _isRingingPrejoinOnly(String? roomID) {
    final client = OpenIMLiveClient();
    if (!client.hasRingingPrejoin) return false;
    final id = roomID?.trim() ?? '';
    final current = client.currentRoomID?.trim() ?? '';
    if (id.isNotEmpty && current.isNotEmpty && current != id) return false;
    return !_userHasAnsweredCall(id);
  }

  /// User actually tapped Answer / in-app pickup — not token prefetch.
  bool _userHasAnsweredCall(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) {
      return _callKitAcceptHandledRoomID != null ||
          _acceptJoinInFlight != null;
    }
    return _answeredRoomUntilMs.containsKey(id) ||
        _callKitAcceptHandledRoomID == id ||
        _isAcceptInProgressForRoom(id);
  }

  bool _isNativeAnswerEndEcho(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    final at = _callKitAcceptAtMs[id];
    if (at == null) return false;
    return DateTime.now().millisecondsSinceEpoch - at < 2000;
  }

  /// LiveKit identity + chat HTTP token — available from disk before IM WS login.
  String _rtcUserID() {
    try {
      final id = OpenIM.iMManager.userID.trim();
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return DataSp.userID?.trim() ?? '';
  }

  Future<String> _waitRtcUserID({int maxMs = 8000}) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + maxMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final id = _rtcUserID();
      final tok = DataSp.chatToken?.trim() ?? '';
      if (id.isNotEmpty && tok.isNotEmpty) return id;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _rtcUserID();
  }

  void _markCallKitAcceptClock(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    _callKitAcceptAtMs[id] = DateTime.now().millisecondsSinceEpoch;
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
  Future<void>? _prefetchTask;
  String? _prefetchTaskRoomID;

  /// Millis when CallKit Answer was handled — ignore native End echo (~2s).
  final Map<String, int> _callKitAcceptAtMs = {};
  int _nativeEndDeferGen = 0;
  int _declineDeferGen = 0;

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
      // Already answered (signal) — never auto-hang as "ring timeout".
      // Remote in LiveKit is not enough: callee pre-joins while still ringing.
      if (_peerAcceptedRooms.contains(roomID) ||
          OpenIMLiveClient().peerAcceptedForUi) {
        Logger.print('call ring timeout ignored: already in-call roomID=$roomID');
        CallAudioDebugLog.add('ring', 'timeout ignored — already answered roomID=$roomID');
        _cancelRingTimeout();
        return;
      }
      final isCaller =
          signaling.invitation?.inviterUserID == OpenIM.iMManager.userID;
      // Only extend after the peer actually accepted — never because the
      // caller sits in an empty LiveKit wait room (callee CallKit already gone).
      if (isCaller &&
          _ringTimeoutExtendCount < 2 &&
          (_peerAcceptedRooms.contains(roomID) ||
              OpenIMLiveClient().peerAcceptedForUi)) {
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

  /// Caller: remote published audio after we already dialed. Fallback if
  /// `callingAccept` is delayed — never fire for the callee's ringing prejoin.
  void markOutboundPeerPresent(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty || _isRoomEnded(id)) return;
    final self = OpenIM.iMManager.userID.trim();
    final inviter =
        _activeCallSignaling?.invitation?.inviterUserID?.trim() ?? '';
    if (self.isEmpty || inviter != self) return;
    if (_peerAcceptedRooms.contains(id)) {
      OpenIMLiveClient().promoteCallingUi(markAccepted: true);
      return;
    }
    _peerAcceptedRooms.add(id);
    _cancelRingTimeout();
    _ringTimeoutExtendCount = 0;
    final client = OpenIMLiveClient();
    client.setUserMicPreference(true);
    unawaited(client.onCallActive(
      speakerOn: client.userSpeakerPreference,
      unmuteMic: true,
    ));
    OpenIMLiveClient().promoteCallingUi(markAccepted: true);
    final info = _activeCallSignaling;
    if (info != null) {
      _beginAnsweredConnecting(info);
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

  /// True if [roomID] is the live invite / answered call — not a ghost CallKit UUID.
  bool _isKnownActiveCallRoom(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    final active = _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    if (active == id) return true;
    final incoming = VoipCallkitController.toOrNull?.incomingRoomID?.trim() ?? '';
    if (incoming == id) return true;
    if (_callKitAcceptHandledRoomID == id) return true;
    if (_answeredRoomUntilMs.containsKey(id)) return true;
    final current = OpenIMLiveClient().currentRoomID?.trim() ?? '';
    return current == id;
  }

  bool _shouldIgnoreDeclineAsAnswerEcho(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    return _userHasAnsweredCall(id) ||
        _isNativeAnswerEndEcho(id) ||
        _isCallKitAcceptSettleArmed(id) ||
        _isAcceptInProgressForRoom(id) ||
        _isOutboundWaitingRoom(id);
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
    if (identical(PackageBridge.onCallKitUserHangup, _onCallKitUserHangup)) {
      PackageBridge.onCallKitUserHangup = null;
    }
    if (identical(PackageBridge.onCallKitTimeout, _onCallKitTimeout)) {
      PackageBridge.onCallKitTimeout = null;
    }
    if (identical(PackageBridge.onVoipRemoteEnd, _onVoipRemoteEnd)) {
      PackageBridge.onVoipRemoteEnd = null;
    }
    if (identical(PackageBridge.onIncomingCallPresented, _onIncomingCallPresented)) {
      PackageBridge.onIncomingCallPresented = null;
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
    PackageBridge.onCallKitUserHangup = _onCallKitUserHangup;
    PackageBridge.onCallKitTimeout = _onCallKitTimeout;
    PackageBridge.onVoipRemoteEnd = _onVoipRemoteEnd;
    PackageBridge.onIncomingCallPresented = _onIncomingCallPresented;
    PackageBridge.suppressCallKitEnded = _suppressCallKitEnded;
    PackageBridge.isCallRoomEnded = _isRoomEnded;
    PackageBridge.onPeerLeftCall = _onPeerLeftCall;
    PackageBridge.markOutboundPeerPresent = markOutboundPeerPresent;
    PackageBridge.onCallKitAudioActivated = _onCallKitAudioActivated;
    PackageBridge.onCallKitAudioDeactivated = _onCallKitAudioDeactivated;
    PackageBridge.connectedCallDurationSec = _connectedDurationSec;
    // VoIP presented before this mixin was wired — start ICE immediately.
    final pendingIncoming = VoipCallkitController.toOrNull?.incomingRoomID;
    if (pendingIncoming != null && pendingIncoming.isNotEmpty) {
      unawaited(_prefetchPickupToken(pendingIncoming));
    }
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
          _isAcceptInProgressForRoom(roomID)) {
        CallAudioDebugLog.add('callkit', 'accept ignored duplicate roomID=$roomID');
        return;
      }
      _callKitAcceptHandledRoomID = roomID;
    }

    _autoPickup = true;
    unawaited(_stopSound());
    unawaited(VoipCallkitController.toOrNull?.setConnected(roomID) ??
        Future.value());
    // Gate must exist before async accept — native audio may activate immediately after fulfill.
    _ensureIosCallKitAudioGate();
    CallAudioDebugLog.add(
      'callkit',
      'accept gate=${_iosCallKitAudioGate != null} activated=$_iosCallKitAudioActivated',
    );
    PackageBridge.clearCallNotification?.call();
    if (roomID.isNotEmpty) {
      _markRoomAnswered(roomID);
      _markCallKitAcceptClock(roomID);
      _armCallKitAcceptSettle(roomID);
    }
    signalingSubject.add(CallEvent(CallState.connecting, resolved));
    unawaited(_promoteTalkingWhenMediaReady(resolved));
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
    final dismissedLeftoverBanner = roomID.isNotEmpty;
    if (!dismissedLeftoverBanner &&
        (CallAudioKeepAlive.instance.callKitOwnsSession ||
            voip?.ownsIncomingUi == true ||
            _iosCallKitDidActivateNative)) {
      CallAudioDebugLog.add(
        'audio',
        'prewarm skipped — CallKit still owns session',
      );
      return;
    }
    if (dismissedLeftoverBanner) {
      CallAudioKeepAlive.instance.releaseCallKitSession();
      _iosCallKitDidActivateNative = false;
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
    // Bridge immediately. Join as soon as WebRTC audio is actually enabled —
    // do not wait 12s, and do not start PeerConnection on a dead session.
    await IosWebRtcAudio.bridgeCallKitSession();
    if (_iosCallKitDidActivateNative ||
        _iosCallKitAudioActivated ||
        await IosWebRtcAudio.isEnabled()) {
      _iosCallKitAudioActivated = true;
      Logger.print('iOS CallKit audio already activated');
      CallAudioDebugLog.add('gate', 'wait skip — already enabled');
      return;
    }
    final gate = _iosCallKitAudioGate!;
    try {
      await Future.any([
        gate.future,
        _pollNativeCallKitDidActivate(),
        _pollWebRtcAudioEnabled(),
      ]).timeout(const Duration(milliseconds: 400));
      Logger.print('iOS CallKit audio session ready');
      CallAudioDebugLog.add(
        'gate',
        'wait ready nativeDidActivate=$_iosCallKitDidActivateNative',
      );
    } on TimeoutException {
      _iosCallKitAudioActivated = true;
      CallAudioDebugLog.add(
          'gate', 'short wait — join now, late didActivate will kickstart');
      Logger.print('iOS CallKit audio: proceed without didActivate');
    }
  }

  Future<void> _pollWebRtcAudioEnabled() async {
    final gen = _callSessionGen;
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (gen == _callSessionGen && DateTime.now().isBefore(deadline)) {
      if (await IosWebRtcAudio.isEnabled()) return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
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
    final roomID = _activeCallSignaling?.invitation?.roomID?.trim() ??
        client.currentRoomID?.trim() ??
        '';
    final answered = roomID.isNotEmpty &&
        (_answeredRoomUntilMs.containsKey(roomID) ||
            _isAcceptInProgressForRoom(roomID) ||
            _callKitAcceptHandledRoomID == roomID);
    if (!answered) {
      CallAudioDebugLog.add(
          'callkit', 'didActivate during ring — keep mic unpublished');
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
    if ((client.hasMediaFor(roomID) || client.isBusy) &&
        !_isRingingPrejoinOnly(roomID)) return;

    final voip = VoipCallkitController.toOrNull;
    if (voip == null) return;

    if (client.hasOverlay) {
      Logger.print('iOS bg: overlay→CallKit roomID=$roomID');
      client.closeOverlayOnly();
    }
    // Overlay ring must not keep looping under CallKit (late answer / cancel).
    unawaited(_stopRingSound());

    _beCalledEvent ??= CallEvent(CallState.beCalled, signaling);
    _activeCallSignaling = signaling;

    if (!voip.ownsIncomingUi) {
      await voip.showIncoming(signaling);
    }
  }

  /// Foreground: attach in-app UI. Keep CallKit while joining/in-call so
  /// Safari/browser accept does not tear down the audio session.
  Future<void> _onIosForegroundResume() async {
    if (!Platform.isIOS) return;
    final voip = VoipCallkitController.toOrNull;
    await voip?.refreshInHangXunForeground();
    await voip?.refreshEndedRoomsFromNative();
    final endedRoom = _activeCallSignaling?.invitation?.roomID?.trim() ??
        OpenIMLiveClient().currentRoomID?.trim() ??
        '';
    if (endedRoom.isNotEmpty && _isRoomEnded(endedRoom)) {
      _activeCallSignaling = null;
      _beCalledEvent = null;
      CallAudioDebugLog.add('fg', 'skip restore — room ended $endedRoom');
      return;
    }
    final keepCallKit = _shouldKeepCallKitAudio();
    final ringingPrejoin = _isRingingPrejoinOnly(endedRoom.isEmpty ? null : endedRoom);
    if (keepCallKit) {
      unawaited(_refreshHeadlessMicPending());
      final client = OpenIMLiveClient();
      if (client.mediaRoom != null && !ringingPrejoin) {
        unawaited(client.kickstartIosCallKitMedia(
          speakerOn: OpenIMLiveClient().userSpeakerPreference,
          unmuteMic: true,
        ));
      }
    } else {
      await _ensureMicPermissionAfterHeadlessAccept();
    }
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

    if (active != null &&
        activeRoom.isNotEmpty &&
        _isRingingPrejoinOnly(activeRoom)) {
      _beCalledEvent ??= CallEvent(CallState.beCalled, active);
    }

    // Live / connecting call — attach UI only; never end media on unlock.
    if (active != null &&
        activeRoom.isNotEmpty &&
        !_isRoomEnded(activeRoom) &&
        !_isRingingPrejoinOnly(activeRoom) &&
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
            'fg', 'answered banner — keep CallKit, attach UI roomID=$pendingRoom');
        _armCallKitAcceptSettle(pendingRoom);
        _activeCallSignaling = pending.data;
        // Do NOT endCall here — that deactivated audio and looked like a hangup
        // while the caller had already received accept and kept timing.
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

      final callKitUp = voip?.ownsIncomingUi == true ||
          (pendingRoom.isNotEmpty && voip?.incomingRoomID == pendingRoom);
      if (!callKitUp) {
        // CallKit already gone (timeout/miss). Do not replay in-app invite.
        CallAudioDebugLog.add(
            'fg', 'unanswered but CallKit gone — miss cleanup roomID=$pendingRoom');
        unawaited(_notifyCallerInviteStopped(pending.data));
        _terminateCallUi(pendingRoom);
        return;
      }

      // VoIP / CallKit wake also looks like "foreground". Keep the system
      // incoming UI — dropping it is the home-screen banner that auto-ends.
      CallAudioDebugLog.add(
          'fg', 'unanswered ringing — keep CallKit roomID=$pendingRoom');
      _beCalledEvent = pending;
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
          !_isRingingPrejoinOnly(activeRoom) &&
          (client.hasMediaFor(activeRoom) ||
              client.isBusy ||
              _isAcceptInProgressForRoom(activeRoom))) {
        Logger.print('iOS fg: attach mid-call UI roomID=$activeRoom');
        _presentCallUi(active, fromHeadless: true);
        await _restoreLiveCallAudio(active);
        return;
      }
      // Unanswered leftover: keep CallKit if it is still showing (lock/home).
      // If CallKit already timed out, do not replay an in-app invite page.
      final leftoverKit = voip?.ownsIncomingUi == true ||
          (activeRoom.isNotEmpty && voip?.incomingRoomID == activeRoom);
      if (!leftoverKit) {
        CallAudioDebugLog.add(
            'fg', 'unanswered leftover CallKit gone — miss cleanup roomID=$activeRoom');
        unawaited(_notifyCallerInviteStopped(active));
        _terminateCallUi(activeRoom);
        return;
      }
      CallAudioDebugLog.add(
          'fg', 'unanswered leftover — keep CallKit roomID=$activeRoom');
      return;
    }
  }

  /// PushKit / CallKit incoming is on screen — start ICE before IM beCalled.
  void _onIncomingCallPresented(String roomID) {
    final id = roomID.trim();
    if (id.isEmpty || _isRoomEnded(id) || _userHasAnsweredCall(id)) return;
    if (_isOutboundWaitingRoom(id)) return;
    CallAudioDebugLog.add('prejoin', 'voip presented — prefetch roomID=$id');
    unawaited(_prefetchPickupToken(id));
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

    if (act != 'hungup' && act != 'end' && act != 'cancel' && act != 'reject') {
      return;
    }

    final active = _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    final sameCall = id.isEmpty || active.isEmpty || active == id;
    // Stale end for an old room must not kill the next incoming CallKit.
    if (!sameCall && id.isNotEmpty && _isRoomEnded(id)) {
      unawaited(
          VoipCallkitController.toOrNull?.endCall(id) ?? Future.value());
      return;
    }

    unawaited(VoipCallkitController.toOrNull?.endAllCalls(roomID: id) ?? Future.value());

    if (id.isNotEmpty && _isRoomEnded(id)) {
      CallAudioDebugLog.add(
          'voip', 'remote end — CallKit wipe, then terminate anyway $id');
      _terminateCallUi(id);
      return;
    }

    if (act == 'hungup' || act == 'end') {
      final info = _activeCallSignaling;
      if (info != null) {
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
    // Ringing prejoin / in-flight ICE is NOT an answered call — still must
    // send callingAccept and publish the mic. Returning here left lock-screen
    // answers silent until some later kickstart.
    final alreadyInCall = client.hasMediaFor(roomID) &&
        client.mediaCertificate != null &&
        !client.hasRingingPrejoin &&
        !client.isMediaConnecting &&
        client.mediaRoom?.localParticipant != null;
    if (alreadyInCall) {
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
    _markRoomAnswered(roomID);
    _beginAnsweredConnecting(signaling);
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
        unawaited(_promoteTalkingWhenMediaReady(signaling));
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
    final owns = CallAudioKeepAlive.instance.callKitOwnsSession;
    final speaker = OpenIMLiveClient().userSpeakerPreference ?? false;
    CallAudioDebugLog.add(
      'fg',
      'mic restore owns=$owns nativeDidActivate=$_iosCallKitDidActivateNative connecting=${client.isMediaConnecting}',
    );
    // CallKit still owns the session — only bridge. setActive here races
    // didDeactivate and drops first audio for ~10s / can end the call.
    if (owns || _iosCallKitDidActivateNative) {
      await IosWebRtcAudio.bridgeCallKitSession();
      if (client.isMediaConnecting) return;
      await client.kickstartIosCallKitMedia(
        speakerOn: speaker,
        unmuteMic: true,
      );
      return;
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
    if (owns || _iosCallKitDidActivateNative) {
      await IosWebRtcAudio.bridgeCallKitSession();
      if (client.isMediaConnecting) {
        CallAudioDebugLog.add('fg', 'skip audio restore — connect in flight');
        return;
      }
      await client.kickstartIosCallKitMedia(
        speakerOn: speaker,
        unmuteMic: true,
      );
      return;
    }
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
    // Token + accept signal in parallel with audio prep so ICE starts immediately.
    if (isCallKitAccept) {
      _ensureIosCallKitAudioGate();
      unawaited(_waitForIosCallKitAudio(
          speakerOn: OpenIMLiveClient().userSpeakerPreference));
    } else if (Platform.isIOS) {
      // Overlay pickup: drop the leftover top CallKit banner first so
      // setActive can own the session (otherwise timer + silence).
      await _dismissCallKitIncoming(roomID);
      CallAudioKeepAlive.instance.releaseCallKitSession();
      _iosCallKitDidActivateNative = false;
      unawaited(_prewarmInAppCallAudio(
        force: true,
        afterDismissRoomID: roomID,
      ));
    }

    // Do not await permission_handler on lock screen — it stalls join and
    // often reports denied, which used to publish no mic. CallKit already
    // owns the mic. In-app already passed requestPermissions above.
    final micGranted = true;
    unawaited(_refreshHeadlessMicPending());

    final pickupFuture =
        onTapPickup(signaling..userID = _rtcUserID());

    if (_prefetchTask != null && _prefetchTaskRoomID == roomID) {
      await _prefetchTask;
    }

    final liveClient = OpenIMLiveClient();
    final SignalingCertificate cert;
    if (liveClient.mediaCertificate != null &&
        (liveClient.hasMediaFor(roomID) || liveClient.isMediaConnecting)) {
      cert = liveClient.mediaCertificate!;
    } else if (_pickupCertRoomID == roomID && _pickupCertCache != null) {
      cert = _pickupCertCache!;
    } else {
      cert = await pickupFuture;
    }
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

    CallAudioDebugLog.add(
      'accept',
      'pre-connect micGranted=$micGranted pendingMic=$_pendingHeadlessMicPermission skipSession=$isCallKitAccept',
    );

    if (roomID != null && roomID.isNotEmpty) {
      unawaited(CallAudioKeepAlive.instance.start(
        roomID: roomID,
        isVideo: isVideo,
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        skipSessionActivation: isCallKitAccept,
      ));
    }

    var workingCert = cert;
    final prejoined = OpenIMLiveClient().hasMediaFor(roomID) &&
        (OpenIMLiveClient().mediaRoom?.localParticipant != null ||
            OpenIMLiveClient().isMediaConnecting);
    if (prejoined) {
      OpenIMLiveClient().endIncomingPrejoin();
      CallAudioDebugLog.add(
        'accept',
        'prejoin hit — publish mic only roomID=$roomID',
      );
      if (isCallKitAccept) {
        await IosWebRtcAudio.bridgeCallKitSession();
      }
      await OpenIMLiveClient().connectMedia(
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
          if (_isAcceptInProgressForRoom(id) ||
              OpenIMLiveClient().isMediaConnecting) {
            return;
          }
          if (!OpenIMLiveClient().isConnectedMedia(id) ||
              (OpenIMLiveClient().mediaRoom?.remoteParticipants.isEmpty ??
                  true)) {
            _terminateCallUi(id);
          }
        },
      );
      if (gen != _callSessionGen || _isRoomEnded(roomID)) {
        throw StateError('accept aborted after prejoin publish');
      }
      _markRoomAnswered(roomID);
      unawaited(OpenIMLiveClient().onCallActive(
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        unmuteMic: micGranted,
      ));
      if (isVideo && micGranted) {
        unawaited(OpenIMLiveClient().enableCameraWhenReady());
      }
      if (isCallKitAccept) {
        unawaited(OpenIMLiveClient().kickstartIosCallKitMedia(
          speakerOn: OpenIMLiveClient().userSpeakerPreference,
          unmuteMic: micGranted,
        ));
      }
      Logger.print('accept prejoin published roomID=${cert.roomID}');
      CallAudioDebugLog.add(
        'accept',
        'prejoin published roomID=${cert.roomID} remotes=${OpenIMLiveClient().mediaRoom?.remoteParticipants.length ?? 0}',
      );
      return cert;
    }

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
            _rtcUserID(),
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
    unawaited(OpenIMLiveClient().onCallActive(
      speakerOn: OpenIMLiveClient().userSpeakerPreference,
      unmuteMic: micGranted,
    ));
    if (isVideo && micGranted) {
      unawaited(OpenIMLiveClient().enableCameraWhenReady());
    }
    if (isCallKitAccept) {
      unawaited(OpenIMLiveClient().kickstartIosCallKitMedia(
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        unmuteMic: true,
      ));
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
      if (_isRingingPrejoinOnly(roomKey)) return;
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
    final ringingPrejoin = _isRingingPrejoinOnly(roomKey);
    final mediaReady = client.hasMediaFor(roomID) && !ringingPrejoin;
    final answered = !outboundWaiting &&
        !ringingPrejoin &&
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
      initState = _callConnectedAtMs != null
          ? CallState.calling
          : CallState.connecting;
    } else {
      initState = CallState.beCalled;
    }
    if (answered || initState == CallState.calling) {
      unawaited(_stopRingSound());
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
    if (_isRingingPrejoinOnly(roomKey)) {
      Logger.print('skip promote — ringing prejoin roomID=$roomKey');
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
        _beginAnsweredConnecting(signaling);
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
    // Caller already left 邀请中 (cancel/timeout). A late accept must not
    // resurrect an incoming/connecting UI on the caller's phone.
    final activeRoom =
        _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    final client = OpenIMLiveClient();
    if (activeRoom != roomID && !client.isBusy && !client.hasOverlay) {
      Logger.print('ignore accept: no active outbound session roomID=$roomID');
      _markRoomEnded(roomID);
      return;
    }

    if (!_peerAcceptedRooms.contains(roomID)) {
      _peerAcceptedRooms.add(roomID);
      _cancelRingTimeout();
      _ringTimeoutExtendCount = 0;
      unawaited(_stopRingSound());
      _activeCallSignaling = merged;
      Logger.print('caller peer accepted roomID=$roomID');
      CallAudioDebugLog.add('ring', 'peer accepted — start timer roomID=$roomID');
      final client = OpenIMLiveClient();
      client.setUserMicPreference(true);
      client.markPeerAcceptedForUi();
      unawaited(client.onCallActive(
        speakerOn: OpenIMLiveClient().userSpeakerPreference,
        unmuteMic: true,
      ));
    }

    // Show 连接中 until audio is up, then start the timer.
    _beginAnsweredConnecting(merged);
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
    var roomID = resolved.invitation?.roomID?.trim() ?? '';
    if (roomID.isEmpty) {
      roomID = _activeCallSignaling?.invitation?.roomID?.trim() ?? '';
    }
    // Programmatic endCall while switching to in-app UI must not reject.
    if (roomID.isEmpty) {
      CallAudioDebugLog.add('callkit', 'decline ignored empty room');
      return;
    }
    if (_isCallKitUiDismissArmed(roomID) || _isRoomEnded(roomID)) {
      Logger.print('CallKit decline ignored — uiDismiss/ended roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'decline ignored uiDismiss roomID=$roomID');
      return;
    }
    if (roomID.isNotEmpty && !_isKnownActiveCallRoom(roomID)) {
      CallAudioDebugLog.add(
          'callkit', 'decline ignored unknown roomID=$roomID');
      unawaited(
          VoipCallkitController.toOrNull?.endCall(roomID) ?? Future.value());
      return;
    }
    if (_shouldIgnoreDeclineAsAnswerEcho(roomID)) {
      CallAudioDebugLog.add(
          'callkit', 'decline ignored answer-echo roomID=$roomID');
      return;
    }
    // Plugin maps CXEndCallAction to Decline whenever answerCall is still nil.
    // Lock-screen Answer often delivers End before Accept — wait before reject.
    unawaited(_deferredDeclineWhileRinging(resolved, roomID));
  }

  Future<void> _deferredDeclineWhileRinging(
    SignalingInfo resolved,
    String roomID,
  ) async {
    final gen = ++_declineDeferGen;
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (gen != _declineDeferGen) return;
    if (_isCallKitUiDismissArmed(roomID) || _isRoomEnded(roomID)) return;
    if (_shouldIgnoreDeclineAsAnswerEcho(roomID)) {
      CallAudioDebugLog.add(
          'callkit', 'deferred decline dropped — already answered roomID=$roomID');
      return;
    }
    final voip = VoipCallkitController.toOrNull;
    if (voip?.ownsIncomingUi == true) {
      CallAudioDebugLog.add(
          'callkit', 'deferred decline dropped — still ringing roomID=$roomID');
      return;
    }
    CallAudioDebugLog.add(
        'callkit', 'decline confirmed — reject roomID=$roomID');
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
          'CallKit timeout — try recover roomID=$roomID');
      CallAudioDebugLog.add(
          'callkit', 'timeout recover roomID=$roomID');
      unawaited(_recoverOrDropIncoming(info, roomID));
      return;
    }
    Logger.print('CallKit timeout — stop both sides roomID=$roomID');
    CallAudioDebugLog.add('callkit', 'timeout → cancel caller roomID=$roomID');
    if (roomID.isNotEmpty &&
        (_userHasAnsweredCall(roomID) ||
            (OpenIMLiveClient().hasMediaFor(roomID) &&
                !_isRingingPrejoinOnly(roomID)))) {
      return;
    }
    unawaited(_dropIncomingAndNotifyCaller(info, roomID));
  }

  /// Native CXEndCallAction — lock-screen red button after the user answered.
  /// Plugin UUID swap on Answer also fires this; ignore that echo (~1.5s).
  /// After Answer the connected CXCall UUID is often not roomID — still hang up.
  void _onCallKitUserHangup(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (_isCallKitUiDismissArmed(id) || _isRoomEnded(id)) {
      CallAudioDebugLog.add(
          'callkit', 'native user end ignored uiDismiss/ended roomID=$id');
      return;
    }
    final info = _resolveIncomingSignaling(_activeCallSignaling) ??
        _activeCallSignaling;
    final infoRoom = info?.invitation?.roomID?.trim() ?? '';
    final answeredActive = infoRoom.isNotEmpty && _userHasAnsweredCall(infoRoom);
    final known = _isKnownActiveCallRoom(id) ||
        (id.isEmpty && answeredActive) ||
        (answeredActive && !_isNativeAnswerEndEcho(infoRoom));

    if (id.isNotEmpty && !known) {
      if (answeredActive &&
          (_isNativeAnswerEndEcho(id) ||
              _isNativeAnswerEndEcho(_callKitAcceptHandledRoomID))) {
        CallAudioDebugLog.add(
            'callkit', 'native end ignored — Answer UUID-swap echo uuid=$id');
        return;
      }
      if (!answeredActive) {
        CallAudioDebugLog.add(
            'callkit', 'native user end ignored unknown roomID=$id');
        return;
      }
    }

    CallAudioDebugLog.add(
      'callkit',
      'native user end roomID=$id active=$infoRoom answered=${_userHasAnsweredCall(id)} echo=${_isNativeAnswerEndEcho(id)} prejoin=${_isRingingPrejoinOnly(id)}',
    );

    if (_isNativeAnswerEndEcho(id) ||
        (answeredActive && _isNativeAnswerEndEcho(infoRoom) && !_isKnownActiveCallRoom(id))) {
      CallAudioDebugLog.add(
          'callkit', 'native end ignored — Answer UUID-swap echo roomID=$id');
      return;
    }

    if (_userHasAnsweredCall(id) || answeredActive) {
      Logger.print('CallKit native user end → hangup roomID=$id active=$infoRoom');
      if (info != null) {
        unawaited(onTapHangup(
            info..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true));
        return;
      }
      _terminateCallUi(id.isEmpty ? null : (infoRoom.isNotEmpty ? infoRoom : id));
      return;
    }

    // Still ringing: this may be Answer's incoming-CXCall end arriving before
    // Dart Accept. Wait briefly; if Accept wins, keep the call.
    unawaited(_deferredNativeEndWhileRinging(id));
  }

  Future<void> _deferredNativeEndWhileRinging(String id) async {
    final gen = ++_nativeEndDeferGen;
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (gen != _nativeEndDeferGen) return;
    if (_isRoomEnded(id) || _isCallKitUiDismissArmed(id)) return;
    if (_userHasAnsweredCall(id) || _isNativeAnswerEndEcho(id)) {
      CallAudioDebugLog.add(
          'callkit', 'deferred native end dropped — already answered roomID=$id');
      return;
    }
    final voip = VoipCallkitController.toOrNull;
    if (voip?.ownsIncomingUi == true) {
      CallAudioDebugLog.add(
          'callkit', 'deferred native end dropped — CallKit still ringing roomID=$id');
      return;
    }
    if (voip != null && voip.isSpuriousEarlyCallKitEnd(id)) {
      CallAudioDebugLog.add(
          'callkit', 'deferred native end — Ended handler will recover/drop roomID=$id');
      return;
    }
    CallAudioDebugLog.add(
        'callkit', 'native end while ringing — stop both sides roomID=$id');
    Logger.print('CallKit native end while ringing — stop both sides roomID=$id');
    final info = _resolveIncomingSignaling(_activeCallSignaling) ??
        _activeCallSignaling;
    unawaited(_dropIncomingAndNotifyCaller(info, id));
  }

  /// Lock-screen / system UI End — classify before reject/hangup.
  void _onCallKitEnded(SignalingInfo? signaling) {
    PackageBridge.clearCallNotification?.call();

    final info = _resolveIncomingSignaling(signaling) ??
        signaling ??
        _activeCallSignaling;
    final roomID =
        info?.invitation?.roomID ?? OpenIMLiveClient().currentRoomID;
    final roomKey = roomID?.trim() ?? '';

    // 1) We closed CallKit for UI switch (unlock → in-app) — never reject/hangup.
    if (_isCallKitUiDismissArmed(roomID) || _isRoomEnded(roomID)) {
      if (_isRoomEnded(roomID) || _userHasAnsweredCall(roomID)) {
        unawaited(_stopRingSound());
      }
      Logger.print('CallKit ended ignored — uiDismiss/ended roomID=$roomKey');
      CallAudioDebugLog.add(
          'callkit', 'ended ignored uiDismiss roomID=$roomKey');
      return;
    }
    _stopSound();
    if (roomKey.isNotEmpty && !_isKnownActiveCallRoom(roomKey)) {
      CallAudioDebugLog.add(
          'callkit', 'ended ignored unknown roomID=$roomKey');
      return;
    }
    if (_isOutboundWaitingRoom(roomKey)) {
      CallAudioDebugLog.add(
          'callkit', 'ended ignored outbound waiting roomID=$roomKey');
      return;
    }

    final client = OpenIMLiveClient();
    final ringingPrejoin = _isRingingPrejoinOnly(roomKey);
    final inCall = !ringingPrejoin &&
        (client.hasMediaFor(roomID) ||
            client.mediaRoom?.localParticipant != null);
    final acceptSent = _userHasAnsweredCall(roomKey);
    final joining = _isAcceptInProgressForRoom(roomKey) ||
        (!ringingPrejoin && client.isMediaConnecting) ||
        (_acceptJoinInFlight != null &&
            (_acceptJoinRoomID == null || _acceptJoinRoomID == roomKey));

    CallAudioDebugLog.add(
      'callkit',
      'ended roomID=$roomKey inCall=$inCall acceptSent=$acceptSent joining=$joining prejoin=$ringingPrejoin settle=${_isCallKitAcceptSettleArmed(roomID)}',
    );

    // Plugin Ended after Answer is the incoming→active UUID swap, not the red
    // button. After the settle window, Ended on a connected call is hangup
    // (iOS 18 sometimes skips native onEnd for the swapped UUID).
    if (acceptSent || joining || inCall) {
      if (_isCallKitAcceptSettleArmed(roomID) || _isNativeAnswerEndEcho(roomKey)) {
        Logger.print(
            'CallKit ended ignored — Answer UUID-swap roomID=$roomKey');
        CallAudioDebugLog.add(
            'callkit', 'ended ignored answered swap roomID=$roomKey');
        return;
      }
      Logger.print('CallKit ended after answer → hangup roomID=$roomKey');
      CallAudioDebugLog.add(
          'callkit', 'ended connected → hangup roomID=$roomKey');
      if (info != null) {
        unawaited(onTapHangup(
            info..userID = OpenIM.iMManager.userID, _connectedDurationSec(), true));
      } else {
        _terminateCallUi(roomKey.isEmpty ? null : roomKey);
      }
      return;
    }

    // Still ringing — CallKit UI is gone. Recover once if this is a UUID
    // collision; otherwise stop BOTH sides (caller must not stay on 邀请).
    final voip = VoipCallkitController.toOrNull;
    if (info != null &&
        roomKey.isNotEmpty &&
        voip != null &&
        voip.isSpuriousEarlyCallKitEnd(roomKey) &&
        !_isRoomEnded(roomKey) &&
        !_userHasAnsweredCall(roomKey)) {
      unawaited(_recoverOrDropIncoming(info, roomKey));
      return;
    }

    Logger.print(
        'CallKit ended while ringing — stop both sides roomID=$roomKey');
    CallAudioDebugLog.add(
        'callkit', 'ended ringing → cancel caller roomID=$roomKey');
    unawaited(_dropIncomingAndNotifyCaller(info, roomKey));
  }

  Future<void> _recoverOrDropIncoming(SignalingInfo info, String roomID) async {
    if (_isRoomEnded(roomID) || _userHasAnsweredCall(roomID)) {
      CallAudioDebugLog.add(
          'callkit', 'recover skipped — ended/answered roomID=$roomID');
      return;
    }
    // In-app full-page invite: CallKit ended is the silent dummy — do not
    // re-show CallKit and do not treat it as a missed call.
    if (!_iosShouldUseCallKitForRing(roomID) &&
        OpenIMLiveClient().hasOverlay) {
      CallAudioDebugLog.add(
          'callkit', 'recover skipped — in-app overlay roomID=$roomID');
      return;
    }
    if (!_iosShouldUseCallKitForRing(roomID)) {
      // Home/lock CallKit died while Flutter looked "resumed". Tell caller.
      CallAudioDebugLog.add(
          'callkit', 'CallKit gone while ringing — notify caller roomID=$roomID');
      await _dropIncomingAndNotifyCaller(info, roomID);
      return;
    }
    final voip = VoipCallkitController.toOrNull;
    final recovered = await voip?.recoverSpuriousIncoming(info) ?? false;
    if (recovered) {
      CallAudioDebugLog.add(
          'callkit', 'recovered incoming CallKit roomID=$roomID');
      return;
    }
    if (_isRoomEnded(roomID) || _userHasAnsweredCall(roomID)) return;
    CallAudioDebugLog.add(
        'callkit', 'recover failed — drop invite both sides roomID=$roomID');
    await _dropIncomingAndNotifyCaller(info, roomID);
  }

  /// CallKit UI died while still ringing. Stop callee locally and tell the
  /// caller the invite is over (callingCancel, not reject).
  Future<void> _dropIncomingAndNotifyCaller(
    SignalingInfo? info,
    String? roomID,
  ) async {
    final id = roomID?.trim() ?? info?.invitation?.roomID?.trim() ?? '';
    if (_userHasAnsweredCall(id)) return;
    // Still tell the caller even if we already cleared local UI (Dart timeout
    // used to mark ended first, then CallKit timeout skipped the cancel).
    unawaited(_notifyCallerInviteStopped(info));
    if (id.isNotEmpty && _isRoomEnded(id)) return;
    _terminateCallUi(id.isEmpty ? null : id);
  }

  Future<void> _notifyCallerInviteStopped(SignalingInfo? info) async {
    if (info?.invitation == null) return;
    final id = info!.invitation?.roomID?.trim() ?? '';
    if (id.isNotEmpty && !_missNotifiedRooms.add(id)) {
      CallAudioDebugLog.add('ring', 'miss notify skipped — already sent $id');
      return;
    }
    final peers = _peerUserIDs(info);
    if (peers.isEmpty) return;
    try {
      await _triggerVoipPush(info, action: 'cancel', toUserIDs: peers);
    } catch (e) {
      Logger.print('notify caller cancel voip failed: $e');
    }
    try {
      final data = {
        'customType': CustomMessageType.callingCancel,
        'data': info.invitation!.toJson(),
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      for (final userID in peers) {
        try {
          await OpenIM.iMManager.messageManager.sendMessage(
            message: message,
            offlinePushInfo: OfflinePushInfo(),
            userID: userID,
            isOnlineOnly: false,
          );
        } catch (e) {
          Logger.print('notify caller cancel IM failed user=$userID: $e');
        }
      }
    } catch (e) {
      Logger.print('notify caller cancel IM skipped: $e');
    }
  }

  List<String> _peerUserIDs(SignalingInfo signaling) {
    try {
      return _recvUserIDList(signaling);
    } catch (_) {
      final inviter = signaling.invitation?.inviterUserID?.trim() ?? '';
      return inviter.isEmpty ? const <String>[] : [inviter];
    }
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
        _markCallKitAcceptClock(roomID);
        _armCallKitAcceptSettle(roomID);
      }
      _beCalledEvent = null;
      if (signaling != null) {
        _beginAnsweredConnecting(signaling);
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
          _markCallKitAcceptClock(roomID);
          _armCallKitAcceptSettle(roomID);
        }
        if (signaling != null) {
          _beginAnsweredConnecting(signaling);
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
                event.state == CallState.connecting ||
                event.state == CallState.beRejected ||
                event.state == CallState.beCanceled ||
                event.state == CallState.beHangup) {
              unawaited(_stopRingSound());
            }
          }
          if (event.state == CallState.beCalled) {
            if (Platform.isIOS) {
              await VoipCallkitController.toOrNull
                  ?.refreshInHangXunForeground();
            }
            unawaited(_prefetchPickupToken(event.data.invitation?.roomID));
            _activeCallSignaling = event.data;
            _startRingTimeout(event.data);
            final mediaType = event.data.invitation!.mediaType;
            final callType =
                mediaType == 'audio' ? CallType.audio : CallType.video;

            // 状态 1/2：锁屏或解锁不在航讯 → 只响 CallKit。状态 3 走下面全屏邀请。
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
            if (!_autoPickup && !_userHasAnsweredCall(roomID)) {
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
            // 状态 3：双方都在航讯 — 只出全屏邀请，顺手清掉可能残留的 CallKit 顶栏。
            PackageBridge.clearCallNotification?.call();
            FlutterOpenimLiveAlert.closeLiveAlert();
            _presentCallUi(event.data, fromHeadless: _autoPickup);
            _autoPickup = false;
            // VoIP may have already shown a top CallKit banner while the app
            // is in the foreground — always dismiss so only the full page remains.
            unawaited(() async {
              await _dismissCallKitIncoming(roomID);
              await _prewarmInAppCallAudio(
                force: true,
                afterDismissRoomID: roomID,
              );
            }());
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
              // Missed ring: caller AND callee must send cancel so the other
              // side does not stay on 邀请中 / replay a stale invite later.
              if (isCaller) {
                unawaited(onTimeoutCancelled(data));
              } else {
                unawaited(_notifyCallerInviteStopped(data));
              }
              _terminateCallUi(roomID.isEmpty ? null : roomID);
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
        _markCallConnected();
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
    final tokenFuture =
        Apis.getTokenForRTC(invitation.roomID!, OpenIM.iMManager.userID);
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
      final certificate = await tokenFuture;
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
    if (id.isEmpty || _isRoomEnded(id)) return;
    if (_userHasAnsweredCall(id) || _isOutboundWaitingRoom(id)) return;
    if (_prefetchTask != null && _prefetchTaskRoomID == id) return;
    if (_pickupInFlight != null && _pickupRoomID == id) return;
    if (OpenIMLiveClient().hasMediaFor(id) &&
        (OpenIMLiveClient().mediaRoom?.localParticipant != null ||
            OpenIMLiveClient().isMediaConnecting)) {
      return;
    }
    _prefetchTaskRoomID = id;
    final task = () async {
      final userID = await _waitRtcUserID();
      if (userID.isEmpty) {
        Logger.print('prefetch skipped: no userID roomID=$id');
        return;
      }
      if (_isRoomEnded(id) || _userHasAnsweredCall(id)) return;
      try {
        if (_pickupCertRoomID != id || _pickupCertCache == null) {
          final cert = await Apis.getTokenForRTC(id, userID);
          _pickupCertCache = cert;
          _pickupCertRoomID = id;
          Logger.print('prefetch rtc token ok roomID=$id');
        }
        final cert = _pickupCertCache;
        if (cert != null && Platform.isIOS) {
          unawaited(_warmIncomingIce(cert));
        }
      } catch (e, s) {
        Logger.print('prefetch rtc token failed roomID=$id: $e $s');
      }
    }();
    _prefetchTask = task;
    try {
      await task;
    } finally {
      if (_prefetchTaskRoomID == id) {
        _prefetchTask = null;
        _prefetchTaskRoomID = null;
      }
    }
  }

  /// Join LiveKit while CallKit is still ringing: TURN/ICE only.
  /// Must not publish mic, subscribe remote audio, or setActive — that kills
  /// the incoming CXCall. Accept then only enables mic + subscribe.
  Future<void> _warmIncomingIce(SignalingCertificate cert) async {
    final roomID = cert.roomID?.trim() ?? '';
    if (roomID.isEmpty || _isRoomEnded(roomID) || _userHasAnsweredCall(roomID)) {
      return;
    }
    if (_isOutboundWaitingRoom(roomID)) return;
    final client = OpenIMLiveClient();
    if (client.hasMediaFor(roomID) || client.isMediaConnecting) return;
    client.beginIncomingPrejoin(roomID);
    CallAudioDebugLog.add('prejoin', 'ICE warmup start roomID=$roomID');
    try {
      await client.connectMedia(
        certificate: cert,
        callType: CallType.audio,
        speakerOn: false,
        enableCamera: false,
        enableMicrophone: false,
        enableKeepAlive: false,
        skipSessionActivation: true,
        ringingIceWarmup: true,
      );
      CallAudioDebugLog.add(
        'prejoin',
        'ICE warmup ready roomID=$roomID remotes=${client.mediaRoom?.remoteParticipants.length ?? 0}',
      );
    } catch (e, s) {
      client.endIncomingPrejoin();
      Logger.print('ICE warmup failed roomID=$roomID: $e $s');
      CallAudioDebugLog.add('prejoin', 'ICE warmup failed roomID=$roomID err=$e');
    }
  }

  Future<SignalingCertificate> onTapPickup(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID;
    // Never skip _doPickup on a cached token — that used to skip callingAccept.
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
    _prefetchTask = null;
    _prefetchTaskRoomID = null;
    _acceptJoinInFlight = null;
    _acceptJoinRoomID = null;
  }

  Future<SignalingCertificate> _doPickup(SignalingInfo signaling) async {
    _beCalledEvent = null; // ios bug
    _stopSound();
    final roomID = signaling.invitation!.roomID!;
    // Accept signal must still go out even when RTC token was prefetched.
    unawaited(_sendCallingAccept(signaling));
    if (_pickupCertRoomID == roomID && _pickupCertCache != null) {
      return _pickupCertCache!;
    }
    var userID = _rtcUserID();
    if (userID.isEmpty) {
      userID = await _waitRtcUserID();
    }
    if (userID.isEmpty) {
      throw StateError('pickup: empty userID roomID=$roomID');
    }
    return Apis.getTokenForRTC(roomID, userID);
  }

  Future<void> _sendCallingAccept(SignalingInfo signaling) async {
    for (var i = 0; i < 10; i++) {
      try {
        if (OpenIM.iMManager.userID.trim().isNotEmpty) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    try {
      final data = {
        'customType': CustomMessageType.callingAccept,
        'data': signaling.invitation!.toJson()
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: signaling.invitation!.inviterUserID,
          isOnlineOnly: false);
      // Do NOT VoIP-push accept to the caller. That PushKit wake was reported
      // as a new incoming CallKit banner on the caller's phone.
    } catch (e, s) {
      Logger.print('send callingAccept failed: $e $s');
    }
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
      unawaited(_endSystemCallUi(roomID));
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
      unawaited(_endSystemCallUi(roomID));
      return null;
    }
  }
  onTapCancel(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID;
    // Mirror hangup: end session first so in-flight dial/connect cannot reopen UI.
    _markRoomEnded(roomID);
    _callConnectedAtMs = null;
    _talkingPromoteGen++;
    _callSessionGen++;
    _activeCallSignaling = null;
    _beCalledEvent = null;
    _clearPickupCache();
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    unawaited(_endSystemCallUi(roomID));
    if (roomID != null && roomID.isNotEmpty) {
      OpenIMLiveClient().closeByRoomID(roomID);
    } else {
      OpenIMLiveClient().close();
    }

    insertSignalingMessageSubject.add(CallEvent(CallState.cancel, signaling));

    final recvUserIDList = _recvUserIDList(signaling);
    // VoIP cancel first so lock-screen CallKit stops without waiting on IM.
    try {
      await _triggerVoipPush(
        signaling,
        action: 'cancel',
        toUserIDs: recvUserIDList,
      );
    } catch (e, s) {
      Logger.print('voip cancel push failed: $e $s');
    }
    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
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
    return true;
  }

  onTimeoutCancelled(SignalingInfo signaling) async {
    final roomID = signaling.invitation?.roomID?.trim() ?? '';
    if (roomID.isNotEmpty) _missNotifiedRooms.add(roomID);
    _markRoomEnded(signaling.invitation?.roomID);
    final recvUserIDList = _recvUserIDList(signaling);
    try {
      await _triggerVoipPush(
        signaling,
        action: 'cancel',
        toUserIDs: recvUserIDList,
      );
    } catch (e, s) {
      Logger.print('voip timeout cancel push failed: $e $s');
    }
    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    for (final userID in recvUserIDList) {
      await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: userID,
          isOnlineOnly: false);
    }
    return true;
  }

  onTapHangup(SignalingInfo signaling, int duration, bool isPositive) async {
    final roomID = signaling.invitation?.roomID;
    if (_isRoomEnded(roomID)) {
      Logger.print('onTapHangup skip — already ended $roomID');
      return;
    }
    // UI timer can reset after CallKit/unlock — take the longer of UI vs wall-clock.
    final wall = _connectedDurationSec();
    final sec = duration > wall ? duration : wall;
    // Mark ended + bump session gen FIRST so late invite/accept cannot reopen UI.
    _markRoomEnded(roomID);
    _callConnectedAtMs = null;
    _talkingPromoteGen++;
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
    // Drop LiveKit + mic + AVAudioSession BEFORE IM/VoIP. Waiting on send
    // left the peer in-call for ~1s and kept the system mic bar until kill.
    _stopSound();
    PackageBridge.clearCallNotification?.call();
    FlutterOpenimLiveAlert.closeLiveAlert();
    unawaited(CallAudioKeepAlive.instance.stop());
    if (Platform.isIOS) {
      unawaited(IosWebRtcAudio.disable());
    }
    unawaited(_endSystemCallUi(roomID));
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

    if (!isPositive) return;
    final recvUserIDList = _recvUserIDList(signaling);
    try {
      await _triggerVoipPush(
        signaling,
        action: 'hungup',
        toUserIDs: recvUserIDList,
      );
    } catch (e, s) {
      Logger.print('voip hungup push failed: $e $s');
    }
    final data = {
      'customType': CustomMessageType.callingHungup,
      'data': {
        ...signaling.invitation!.toJson(),
        'duration': sec,
      },
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
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

  bool _shouldSkipRingPlayback() {
    final roomID = _activeCallSignaling?.invitation?.roomID ??
        _beCalledEvent?.data.invitation?.roomID;
    if (_isRoomEnded(roomID) || _userHasAnsweredCall(roomID)) return true;
    final id = roomID?.trim() ?? '';
    return id.isNotEmpty && _peerAcceptedRooms.contains(id);
  }

  void _playSound() async {
    if (_shouldSkipRingPlayback()) {
      unawaited(_stopRingSound());
      return;
    }
    final gen = ++_ringPlayGen;
    try {
      if (_audioPlayer.playerState.playing) {
        await _audioPlayer.stop();
      }
      if (gen != _ringPlayGen || _shouldSkipRingPlayback()) return;
      await _audioPlayer.setAsset(_ring, package: 'openim_common');
      if (gen != _ringPlayGen || _shouldSkipRingPlayback()) return;
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setVolume(1.0);
      if (gen != _ringPlayGen || _shouldSkipRingPlayback()) return;
      await _audioPlayer.play();
    } catch (e, s) {
      Logger.print('play ring failed: $e $s');
    }
  }

  Future<void> _stopRingSound() async {
    _ringPlayGen++;
    try {
      await _audioPlayer.setVolume(0);
    } catch (_) {}
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _audioPlayer.pause();
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
