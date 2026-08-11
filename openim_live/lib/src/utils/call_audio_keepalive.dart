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
///
/// Lock-screen CallKit audio is bridged to WebRTC in AppDelegate (RTCAudioSession).
/// Do not fight CallKit with duplicate session logic here.
class CallAudioKeepAlive with WidgetsBindingObserver {
  CallAudioKeepAlive._();
  static final CallAudioKeepAlive instance = CallAudioKeepAlive._();

  bool _active = false;
  String? _roomID;
  bool _isVideo = false;
  String _peerName = '通话中';
  StreamSubscription? _interruptionSub;
  Future<void> Function()? onNeedRepublishMic;
  /// CallKit owns AVAudioSession (lock-screen accept) — do not reconfigure via audio_session.
  bool _callKitOwnsSession = false;

  bool get isActive => _active;
  bool get callKitOwnsSession => _callKitOwnsSession;

  void releaseCallKitSession() {
    _callKitOwnsSession = false;
    CallAudioDebugLog.add('keepalive', 'releaseCallKitSession');
  }

  void markCallKitOwnsSession() {
    _callKitOwnsSession = true;
    CallAudioDebugLog.add('keepalive', 'markCallKitOwnsSession');
  }

  Future<void> prepareForRtc({
    bool speakerOn = false,
    bool skipSessionActivation = false,
  }) async {
    if (skipSessionActivation) _callKitOwnsSession = true;
    if (_callKitOwnsSession || skipSessionActivation) {
      CallAudioDebugLog.add(
        'keepalive',
        'prepareForRtc skip owns=$_callKitOwnsSession skip=$skipSessionActivation',
      );
      return;
    }
    // iOS: IosWebRtcAudio.enable already setCategory+setActive — avoid double activate.
    if (Platform.isIOS) {
      CallAudioDebugLog.add('keepalive', 'prepareForRtc enable speaker=$speakerOn');
      await IosWebRtcAudio.enable(speakerOn: speakerOn);
      return;
    }
    await _activateCallSession(preferSpeaker: speakerOn);
  }

  Future<void> start({
    required String roomID,
    required bool isVideo,
    String? peerName,
    bool speakerOn = false,
    bool skipSessionActivation = false,
  }) async {
    _roomID = roomID;
    _isVideo = isVideo;
    if (skipSessionActivation) _callKitOwnsSession = true;
    CallAudioDebugLog.add(
      'keepalive',
      'start roomID=$roomID video=$isVideo skipSession=$skipSessionActivation owns=$_callKitOwnsSession',
    );
    if (peerName != null && peerName.trim().isNotEmpty) {
      _peerName = peerName.trim();
    }
    if (_active) {
      if (!_callKitOwnsSession && !skipSessionActivation) {
        await _activateCallSession(preferSpeaker: speakerOn);
      }
      return;
    }
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    if (!_callKitOwnsSession && !skipSessionActivation) {
      await _activateCallSession(preferSpeaker: speakerOn);
    }
    await _listenInterruptions();
    if (Platform.isAndroid) {
      await _enableAndroidCallForegroundService();
    }
    // iOS: do NOT setCallConnected here — start() runs before LiveKit ICE.
    // CallKit connected is set by LiveController after join succeeds.
    Logger.print(
        'CallAudioKeepAlive start roomID=$roomID video=$isVideo peer=$_peerName');
  }

  Future<void> stop() async {
    if (!_active && _roomID == null) return;
    final wasCallKit = _callKitOwnsSession;
    _active = false;
    _callKitOwnsSession = false;
    _roomID = null;
    WidgetsBinding.instance.removeObserver(this);
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    onNeedRepublishMic = null;

    if (Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (e, s) {
        Logger.print('CallAudioKeepAlive disable FGS failed: $e $s');
      }
    } else if (Platform.isIOS) {
      // CallKit will didDeactivate — avoid racing disable while system tears down.
      if (!wasCallKit) {
        await IosWebRtcAudio.disable();
      } else {
        CallAudioDebugLog.add(
            'keepalive', 'stop skip disable (CallKit owned session)');
      }
    }
    Logger.print('CallAudioKeepAlive stop');
    CallAudioDebugLog.add('keepalive', 'stop wasCallKit=$wasCallKit');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active || _callKitOwnsSession) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_activateCallSession());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_recoverMic());
    }
  }

  Future<void> _recoverMic() async {
    if (!_callKitOwnsSession) {
      await _activateCallSession();
      if (Platform.isIOS) {
        await IosWebRtcAudio.enable();
      }
    }
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

  Future<void> _activateCallSession({bool preferSpeaker = false}) async {
    try {
      final session = await AudioSession.instance;
      // Do NOT mixWithOthers — it weakens AEC and causes speaker howling/echo.
      var options = AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp;
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
      await session.setActive(true);
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
            'CallAudioKeepAlive setCallConnected anyway (activeCalls miss) roomID=$roomID');
        CallAudioDebugLog.add(
            'keepalive', 'setCallConnected anyway (activeCalls miss) $roomID');
      }
      await FlutterCallkitIncoming.setCallConnected(roomID);
      Logger.print('CallAudioKeepAlive iOS CallKit connected roomID=$roomID');
      CallAudioDebugLog.add('keepalive', 'setCallConnected roomID=$roomID');
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive iOS CallKit promote failed: $e $s');
      CallAudioDebugLog.add('keepalive', 'setCallConnected failed: $e');
    }
  }
}
