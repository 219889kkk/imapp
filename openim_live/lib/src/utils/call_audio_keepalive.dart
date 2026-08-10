import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:openim_common/openim_common.dart';

/// Keeps call mic/audio alive when the app is backgrounded (e.g. switch to WeChat text).
///
/// Android: phone-call / microphone foreground service.
/// iOS: playAndRecord + voiceChat session, optional ongoing CallKit, recover after interruptions.
class CallAudioKeepAlive with WidgetsBindingObserver {
  CallAudioKeepAlive._();
  static final CallAudioKeepAlive instance = CallAudioKeepAlive._();

  bool _active = false;
  String? _roomID;
  bool _isVideo = false;
  String _peerName = '通话中';
  StreamSubscription? _interruptionSub;
  Future<void> Function()? onNeedRepublishMic;
  /// CallKit already activated AVAudioSession — never call setActive again.
  bool _callKitOwnsSession = false;
  bool _callKitAudioActivated = false;
  Completer<void>? _callKitAudioReady;

  bool get isActive => _active;
  bool get callKitOwnsSession => _callKitOwnsSession;
  bool get callKitAudioActivated => _callKitAudioActivated;

  /// Lock-screen CallKit accept: wait for native RTCAudioSession bridge.
  void beginCallKitAudioSession() {
    _callKitOwnsSession = true;
    _callKitAudioActivated = false;
    _callKitAudioReady = Completer<void>();
    Logger.print('CallAudioKeepAlive: waiting for CallKit audio session');
  }

  void markCallKitAudioActivated() {
    if (_callKitAudioActivated) return;
    _callKitAudioActivated = true;
    Logger.print('CallAudioKeepAlive: CallKit audio session ready');
    final pending = _callKitAudioReady;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> waitForCallKitAudioReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_callKitOwnsSession || _callKitAudioActivated) return;
    final pending = _callKitAudioReady ??= Completer<void>();
    try {
      await pending.future.timeout(timeout);
    } on TimeoutException {
      Logger.print('CallAudioKeepAlive: CallKit audio ready timeout');
    }
  }

  Future<void> endCallKitAudioSession() async {
    _callKitOwnsSession = false;
    _callKitAudioActivated = false;
    _callKitAudioReady = null;
  }

  /// Configure a LiveKit/WebRTC-friendly session BEFORE room.connect.
  /// When [callKitCoexist] is true, category/mode only — CallKit keeps activation.
  Future<void> prepareForRtc({
    bool speakerOn = false,
    bool callKitCoexist = false,
  }) async {
    if (callKitCoexist) beginCallKitAudioSession();
    await _activateCallSession(
      preferSpeaker: speakerOn,
      skipSessionActivation: callKitCoexist || _callKitOwnsSession,
    );
  }

  Future<void> start({
    required String roomID,
    required bool isVideo,
    String? peerName,
    bool speakerOn = false,
  }) async {
    _roomID = roomID;
    _isVideo = isVideo;
    if (peerName != null && peerName.trim().isNotEmpty) {
      _peerName = peerName.trim();
    }
    if (_active) {
      await _activateCallSession(
        preferSpeaker: speakerOn,
        skipSessionActivation: _callKitOwnsSession,
      );
      return;
    }
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    await _activateCallSession(
      preferSpeaker: speakerOn,
      skipSessionActivation: _callKitOwnsSession,
    );
    await _listenInterruptions();
    if (Platform.isAndroid) {
      await _enableAndroidCallForegroundService();
    } else if (Platform.isIOS) {
      await _promoteIosOngoingCall();
    }
    Logger.print(
        'CallAudioKeepAlive start roomID=$roomID video=$isVideo peer=$_peerName');
  }

  Future<void> stop() async {
    if (!_active && _roomID == null && !_callKitOwnsSession) return;
    _active = false;
    _roomID = null;
    WidgetsBinding.instance.removeObserver(this);
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    onNeedRepublishMic = null;
    await endCallKitAudioSession();

    if (Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (e, s) {
        Logger.print('CallAudioKeepAlive disable FGS failed: $e $s');
      }
    }
    // Never endCall here — that looks like a hangup when UI remounts after unlock.
    Logger.print('CallAudioKeepAlive stop');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_activateCallSession(
        skipSessionActivation: _callKitOwnsSession,
      ));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_recoverMic());
    }
  }

  Future<void> _recoverMic() async {
    await _activateCallSession(
      skipSessionActivation: _callKitOwnsSession,
    );
    if (onNeedRepublishMic == null) return;
    try {
      await onNeedRepublishMic?.call();
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive republish mic failed: $e $s');
    }
  }

  Future<void> _listenInterruptions() async {
    await _interruptionSub?.cancel();
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (!_active) return;
        if (event.begin) {
          Logger.print('CallAudioKeepAlive audio interruption began');
          return;
        }
        Logger.print('CallAudioKeepAlive audio interruption ended');
        unawaited(_recoverMic());
      });
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive interrupt listen failed: $e $s');
    }
  }

  Future<void> _activateCallSession({
    bool preferSpeaker = false,
    bool skipSessionActivation = false,
  }) async {
    try {
      final session = await AudioSession.instance;
      // mixWithOthers is required so LiveKit/WebRTC can keep its audio unit.
      // Exclusive playAndRecord (no mix) was silencing in-app call audio.
      var options = AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp |
          AVAudioSessionCategoryOptions.mixWithOthers;
      if (preferSpeaker) {
        options = options | AVAudioSessionCategoryOptions.defaultToSpeaker;
      }
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: options,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      if (!skipSessionActivation) {
        await session.setActive(true);
      } else {
        Logger.print(
            'CallAudioKeepAlive: skip setActive (CallKit owns session)');
      }
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive activate session failed: $e $s');
    }
  }

  Future<void> _enableAndroidCallForegroundService() async {
    try {
      var hasPermissions = await FlutterBackground.hasPermissions;
      hasPermissions = await FlutterBackground.initialize(
        androidConfig: FlutterBackgroundAndroidConfig(
          notificationTitle: '航讯通话中',
          notificationText: '与$_peerName通话中，点此返回',
          notificationImportance: AndroidNotificationImportance.high,
          notificationIcon:
              const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          shouldRequestBatteryOptimizationsOff: false,
        ),
      );
      if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
        final ok = await FlutterBackground.enableBackgroundExecution();
        Logger.print('CallAudioKeepAlive Android FGS enabled=$ok');
      }
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive Android FGS failed: $e $s');
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      } catch (_) {}
    }
  }

  /// Reinforce existing CallKit only — never invent a new lock-screen call.
  Future<void> _promoteIosOngoingCall() async {
    final roomID = _roomID;
    if (roomID == null || roomID.isEmpty) return;
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      var already = false;
      if (active is List) {
        already = active.any((c) {
          if (c is CallKitParams) return c.id == roomID;
          if (c is Map) return '${c['id']}' == roomID;
          return false;
        });
      }
      if (!already) {
        Logger.print(
            'CallAudioKeepAlive skip startCall (no existing CallKit) roomID=$roomID');
        return;
      }
      await FlutterCallkitIncoming.setCallConnected(roomID);
      Logger.print('CallAudioKeepAlive iOS CallKit connected roomID=$roomID');
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive iOS CallKit promote failed: $e $s');
    }
  }
}
