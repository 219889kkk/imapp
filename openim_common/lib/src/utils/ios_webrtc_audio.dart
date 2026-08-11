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

  /// Re-enable if WebRTC audio was left off (CallKit deactivate / failed handoff).
  /// Retries briefly — CallKit tear-down often races the first setActive.
  ///
  /// When [force] is true, always run [enable] once even if the flag looks on
  /// (covers inactive-session races after unlocking into chat).
  static Future<bool> ensureEnabled({
    bool speakerOn = false,
    bool force = false,
  }) async {
    if (!Platform.isIOS) return true;
    for (var i = 0; i < 3; i++) {
      final on = await isEnabled();
      if (on && !(force && i == 0)) {
        CallAudioDebugLog.add('webrtc', 'ensureEnabled already on attempt=$i');
        return true;
      }
      CallAudioDebugLog.add(
        'webrtc',
        'ensureEnabled enable speaker=$speakerOn force=$force attempt=$i wasOn=$on',
      );
      await enable(speakerOn: speakerOn);
      if (await isEnabled()) return true;
      await Future<void>.delayed(Duration(milliseconds: 120 + i * 80));
    }
    CallAudioDebugLog.add('webrtc', 'ensureEnabled still off after retries');
    return false;
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

  /// Earpiece ↔ speaker with voiceChat AEC (works under CallKit ownership).
  static Future<void> setSpeakerRoute(bool speakerOn) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('setSpeakerRoute', {'speakerOn': speakerOn});
      CallAudioDebugLog.add('webrtc', 'setSpeakerRoute speaker=$speakerOn ok');
    } catch (e, s) {
      Logger.print('IosWebRtcAudio setSpeakerRoute failed: $e $s');
      CallAudioDebugLog.add('webrtc', 'setSpeakerRoute failed: $e');
    }
  }
}
