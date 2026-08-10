import 'dart:io';

import 'package:flutter/services.dart';

import 'logger.dart';

/// Bridges AVAudioSession → WebRTC when [useManualAudio] is enabled (iOS).
///
/// CallKit lock-screen: AppDelegate [didActivateAudioSession] enables audio.
/// In-app / unlocked calls: Dart must invoke [enable] before LiveKit capture/play.
class IosWebRtcAudio {
  IosWebRtcAudio._();

  static const _channel = MethodChannel('top.hangxun.app/voip');

  static Future<void> enable({bool speakerOn = false}) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('enableWebRtcAudio', {'speakerOn': speakerOn});
      Logger.print('IosWebRtcAudio enabled speaker=$speakerOn');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio enable failed: $e $s');
    }
  }

  static Future<void> disable() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('disableWebRtcAudio');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio disable failed: $e $s');
    }
  }
}
