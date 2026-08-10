import 'package:flutter/foundation.dart';

/// In-app ring buffer for CallKit / WebRTC audio diagnosis.
///
/// Unlike [Logger.print], this keeps entries in Release builds so ad-hoc IPA
/// testers can copy logs without Xcode.
class CallAudioDebugLog {
  CallAudioDebugLog._();

  static const int maxEntries = 300;
  static final List<_Entry> _entries = <_Entry>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String> get lines =>
      List<String>.unmodifiable(_entries.map((e) => e.format()));

  static void add(String tag, String message) {
    final entry = _Entry(
      at: DateTime.now(),
      tag: tag,
      message: message,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    revision.value++;
    // Also mirror to console in debug for developers.
    if (kDebugMode) {
      debugPrint('[CallAudioDebug] ${entry.format()}');
    }
  }

  static void clear() {
    _entries.clear();
    revision.value++;
  }

  static String exportText({String? snapshot}) {
    final buf = StringBuffer();
    buf.writeln('=== HangXun Call Audio Debug ===');
    buf.writeln('exportedAt=${DateTime.now().toIso8601String()}');
    if (snapshot != null && snapshot.trim().isNotEmpty) {
      buf.writeln('--- snapshot ---');
      buf.writeln(snapshot.trim());
    }
    buf.writeln('--- events (${_entries.length}) ---');
    for (final e in _entries) {
      buf.writeln(e.format());
    }
    return buf.toString();
  }
}

class _Entry {
  _Entry({
    required this.at,
    required this.tag,
    required this.message,
  });

  final DateTime at;
  final String tag;
  final String message;

  String format() {
    final t = at.toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    return '$t [$tag] $message';
  }
}
