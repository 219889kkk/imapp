import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:permission_handler/permission_handler.dart';

class CallAudioDebugLogic extends GetxController {
  final snapshotText = ''.obs;

  @override
  void onReady() {
    super.onReady();
    refreshSnapshot();
  }

  Future<void> refreshSnapshot() async {
    final lines = <String>[];
    try {
      final mic = await Permission.microphone.status;
      lines.add('micPermission=$mic');
    } catch (e) {
      lines.add('micPermission=error:$e');
    }

    if (Platform.isIOS) {
      final enabled = await IosWebRtcAudio.isEnabled();
      lines.add('isWebRtcAudioEnabled=$enabled');
    } else {
      lines.add('isWebRtcAudioEnabled=n/a');
    }

    lines.add(
        'callKitOwnsSession=${CallAudioKeepAlive.instance.callKitOwnsSession}');

    final client = OpenIMLiveClient();
    lines.add('isBusy=${client.isBusy}');
    lines.add('roomID=${client.currentRoomID}');
    lines.add('hasMedia=${client.mediaRoom != null}');
    lines.add('remotes=${client.mediaRoom?.remoteParticipants.length ?? 0}');
    lines.add(
        'localMic=${client.mediaRoom?.localParticipant?.isMicrophoneEnabled()}');
    lines.add('peerAcceptedForUi=${client.peerAcceptedForUi}');
    lines.add('events=${CallAudioDebugLog.lines.length}');

    snapshotText.value = lines.join('\n');
  }

  Future<void> copyAll() async {
    await refreshSnapshot();
    final text = CallAudioDebugLog.exportText(snapshot: snapshotText.value);
    await Clipboard.setData(ClipboardData(text: text));
    IMViews.showToast('已复制通话音频日志');
  }

  void clearLogs() {
    CallAudioDebugLog.clear();
    refreshSnapshot();
    IMViews.showToast('已清空');
  }
}
