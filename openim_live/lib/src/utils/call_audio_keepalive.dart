import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
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

  static const _voipChannel = MethodChannel('top.hangxun.app/voip');
  static bool _imKeepAliveWanted = false;
  static String? _androidFgsTitle;

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

  /// Keep IM websocket alive while Android is locked / backgrounded.
  /// No Getui wake-up — Doze otherwise freezes the socket after ~5 minutes.
  /// Call FGS takes over if a call is already active.
  static Future<void> startImBackgroundKeepAlive() async {
    if (!Platform.isAndroid) return;
    if (!SessionGuard.shouldNotify) return;
    _imKeepAliveWanted = true;
    if (instance.isActive) return;
    await _startNativeImKeepAlive();
  }

  static Future<void> stopImBackgroundKeepAlive() async {
    _imKeepAliveWanted = false;
    if (!Platform.isAndroid) return;
    await _stopNativeImKeepAlive();
    if (instance.isActive) return;
    await instance._disableAndroidForegroundService();
  }

  static Future<void> _startNativeImKeepAlive() async {
    try {
      await _voipChannel.invokeMethod('startImKeepAlive');
      Logger.print('IM keep-alive native FGS start');
    } catch (e, s) {
      Logger.print('IM keep-alive native FGS start failed: $e $s');
    }
  }

  static Future<void> _stopNativeImKeepAlive() async {
    try {
      await _voipChannel.invokeMethod('stopImKeepAlive');
    } catch (e, s) {
      Logger.print('IM keep-alive native FGS stop failed: $e $s');
    }
  }

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
      // CallKit path: only skip setActive while session is actually live.
      if (Platform.isIOS) {
        final on = await IosWebRtcAudio.isEnabled();
        if (on) {
          CallAudioDebugLog.add(
            'keepalive',
            'prepareForRtc skip owns=$_callKitOwnsSession skip=$skipSessionActivation enabled=true',
          );
          return;
        }
        // Audio off is normal while CallKit is still RINGING (and in the
        // brief window before didActivate). setActive here steals the
        // session and iOS hangs the incoming CXCall after one ring.
        CallAudioDebugLog.add(
          'keepalive',
          'prepareForRtc no takeover — CallKit audio not live yet',
        );
        return;
      }
      CallAudioDebugLog.add(
        'keepalive',
        'prepareForRtc skip owns=$_callKitOwnsSession skip=$skipSessionActivation',
      );
      return;
    }
    // iOS: IosWebRtcAudio.enable already setCategory+setActive — avoid double activate.
    if (Platform.isIOS) {
      CallAudioDebugLog.add('keepalive', 'prepareForRtc enable speaker=$speakerOn');
      await IosWebRtcAudio.ensureEnabled(speakerOn: speakerOn);
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
      await _stopNativeImKeepAlive();
      await _enableAndroidForegroundService(
        title: '航讯通话中',
        text: '与$_peerName通话中，点此返回',
        importance: AndroidNotificationImportance.high,
      );
    }
    // iOS: do NOT setCallConnected here — start() runs before LiveKit ICE.
    // CallKit connected is set by LiveController after join succeeds.
    Logger.print(
        'CallAudioKeepAlive start roomID=$roomID video=$isVideo peer=$_peerName');
  }

  Future<void> stop() async {
    final wasCallKit = _callKitOwnsSession;
    final wasActive = _active || _roomID != null;
    _active = false;
    _callKitOwnsSession = false;
    _roomID = null;
    WidgetsBinding.instance.removeObserver(this);
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    onNeedRepublishMic = null;

    if (Platform.isAndroid) {
      await _disableAndroidForegroundService();
      if (_imKeepAliveWanted && SessionGuard.shouldNotify) {
        await _startNativeImKeepAlive();
      }
    } else if (Platform.isIOS) {
      // Drop the system mic indicator immediately. Do not wait for CallKit —
      // that delay left playAndRecord active until the user killed the app.
      await IosWebRtcAudio.disable();
    }
    if (wasActive) {
      Logger.print('CallAudioKeepAlive stop');
      CallAudioDebugLog.add('keepalive', 'stop wasCallKit=$wasCallKit');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_callKitOwnsSession) {
        unawaited(_activateCallSession());
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_recoverMic());
    }
  }

  Future<void> _recoverMic() async {
    if (Platform.isIOS) {
      final on = await IosWebRtcAudio.isEnabled();
      if (!on) {
        // CallKit may have deactivated while owns flag was still true.
        _callKitOwnsSession = false;
        await IosWebRtcAudio.ensureEnabled();
      } else if (!_callKitOwnsSession) {
        await _activateCallSession();
        await IosWebRtcAudio.ensureEnabled();
      }
    } else if (!_callKitOwnsSession) {
      await _activateCallSession();
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
      // HFP bluetooth only — A2DP + mixWithOthers both weaken / disable AEC.
      var options = AVAudioSessionCategoryOptions.allowBluetooth;
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

  Future<void> _disableAndroidForegroundService() async {
    _androidFgsTitle = null;
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive disable FGS failed: $e $s');
    }
  }

  Future<void> _enableAndroidForegroundService({
    required String title,
    required String text,
    required AndroidNotificationImportance importance,
  }) async {
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled &&
          _androidFgsTitle == title) {
        return;
      }
      var hasPermissions = await FlutterBackground.hasPermissions;
      hasPermissions = await FlutterBackground.initialize(
        androidConfig: FlutterBackgroundAndroidConfig(
          notificationTitle: title,
          notificationText: text,
          notificationImportance: importance,
          notificationIcon:
              const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          shouldRequestBatteryOptimizationsOff: false,
        ),
      );
      if (!hasPermissions) return;
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
      final ok = await FlutterBackground.enableBackgroundExecution();
      if (ok) _androidFgsTitle = title;
      Logger.print('CallAudioKeepAlive Android FGS enabled=$ok title=$title');
    } catch (e, s) {
      Logger.print('CallAudioKeepAlive Android FGS failed: $e $s');
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          final ok = await FlutterBackground.enableBackgroundExecution();
          if (ok) _androidFgsTitle = title;
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
