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

  bool get isActive => _active;

  Future<void> start({
    required String roomID,
    required bool isVideo,
    String? peerName,
  }) async {
    _roomID = roomID;
    _isVideo = isVideo;
    if (peerName != null && peerName.trim().isNotEmpty) {
      _peerName = peerName.trim();
    }
    if (_active) {
      await _activateCallSession();
      return;
    }
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    await _activateCallSession();
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
    if (!_active && _roomID == null) return;
    _active = false;
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
    }
    // Never endCall here — that looks like a hangup when UI remounts after unlock.
    // CallKit teardown belongs to live hangup / _terminateCallUi only.
    Logger.print('CallAudioKeepAlive stop');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Re-assert VoIP session so OS keeps mic while another app is open.
      unawaited(_activateCallSession());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_recoverMic());
    }
  }

  Future<void> _recoverMic() async {
    await _activateCallSession();
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

  Future<void> _activateCallSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        // Exclusive VoIP session — mixWithOthers can mute LiveKit under CallKit.
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp |
                AVAudioSessionCategoryOptions.defaultToSpeaker,
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
      // One retry after a short delay (first-run permission dialogs).
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      } catch (_) {}
    }
  }

  /// Register an ongoing CallKit call so iOS treats us as an active voice app.
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
        // Never startCall here — that creates a lock-screen "ongoing call"
        // for the caller while ringing, and it can linger after in-app hangup.
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
