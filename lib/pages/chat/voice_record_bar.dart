import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecordBar extends StatefulWidget {
  const VoiceRecordBar({
    super.key,
    required this.onRecordComplete,
  });

  final Future<void> Function(String path, int duration) onRecordComplete;

  @override
  State<VoiceRecordBar> createState() => _VoiceRecordBarState();
}

class _VoiceRecordBarState extends State<VoiceRecordBar> {
  final _recorder = AudioRecorder();
  DateTime? _recordStartedAt;
  String? _recordPath;
  bool _recording = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecord() async {
    if (_recording) return;
    if (!await _recorder.hasPermission()) {
      IMViews.showToast(StrRes.permissionDeniedTitle);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordStartedAt = DateTime.now();
      _recordPath = path;
    });
  }

  Future<void> _stopRecord() async {
    if (!_recording) return;
    final startedAt = _recordStartedAt;
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordStartedAt = null;
    });
    final duration =
        startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds;
    final soundPath = path ?? _recordPath;
    if (duration < 1 || soundPath == null || !File(soundPath).existsSync()) {
      if (soundPath != null) {
        try {
          File(soundPath).deleteSync();
        } catch (_) {}
      }
      IMViews.showToast(StrRes.tapTooShort);
      return;
    }
    await widget.onRecordComplete(soundPath, duration);
  }

  Future<void> _cancelRecord() async {
    if (!_recording) return;
    await _recorder.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordStartedAt = null;
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _startRecord(),
        onLongPressEnd: (_) => _stopRecord(),
        onLongPressCancel: _cancelRecord,
        child: Container(
          height: 36.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _recording ? Styles.c_0089FF_opacity20 : Styles.c_FFFFFF,
            borderRadius: BorderRadius.circular(4.r),
            border: Border.all(color: Styles.c_E8EAEF, width: 0.5),
          ),
          child: (_recording ? StrRes.releaseToSend : StrRes.holdTalk).toText
            ..style = Styles.ts_0C1C33_17sp,
        ),
      );
}
