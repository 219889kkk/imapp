import 'dart:io';

import 'package:flutter/services.dart';

import 'call_audio_debug_log.dart';
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
      CallAudioDebugLog.add('webrtc', 'enable speaker=$speakerOn ok');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio enable failed: $e $s');
      CallAudioDebugLog.add('webrtc', 'enable failed: $e');
    }
  }

  static Future<void> disable() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('disableWebRtcAudio');
      CallAudioDebugLog.add('webrtc', 'disable ok');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio disable failed: $e $s');
      CallAudioDebugLog.add('webrtc', 'disable failed: $e');
    }
  }

  /// Whether native WebRTC audio is enabled (useManualAudio path).
  static Future<bool> isEnabled() async {
    if (!Platform.isIOS) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isWebRtcAudioEnabled');
      return v == true;
    } catch (e, s) {
      Logger.print('IosWebRtcAudio isEnabled failed: $e $s');
      return false;
    }
  }

  /// CallKit owns AVAudioSession — bridge WebRTC without setCategory/setActive.
  static Future<void> bridgeCallKitSession() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('bridgeCallKitWebRtcAudio');
      Logger.print('IosWebRtcAudio CallKit bridge invoked');
      CallAudioDebugLog.add('webrtc', 'bridgeCallKitSession ok');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio CallKit bridge failed: $e $s');
      CallAudioDebugLog.add('webrtc', 'bridgeCallKitSession failed: $e');
    }
  }
}
