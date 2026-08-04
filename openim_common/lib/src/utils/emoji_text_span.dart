import 'package:flutter/material.dart';

import '../res/styles.dart';

/// Fast emoji-range check (avoids expensive `\p{Emoji}` regex on every keystroke).
bool _isEmojiCodePoint(int cp) {
  if (cp == 0x200D || cp == 0xFE0F || cp == 0x20E3) return true;
  if (cp >= 0xFE00 && cp <= 0xFE0F) return true;
  if (cp >= 0x1F1E6 && cp <= 0x1F1FF) return true; // flags
  if (cp >= 0x1F300 && cp <= 0x1FAFF) return true; // emoji blocks
  if (cp >= 0x1F000 && cp <= 0x1F02F) return true;
  if (cp >= 0x2600 && cp <= 0x27BF) return true; // misc symbols
  if (cp >= 0x2300 && cp <= 0x23FF) return true; // technical
  if (cp >= 0x2B00 && cp <= 0x2BFF) return true;
  if (cp >= 0x2900 && cp <= 0x297F) return true;
  return false;
}

bool textLikelyContainsEmoji(String text) {
  if (text.isEmpty) return false;
  for (final cp in text.runes) {
    if (_isEmojiCodePoint(cp)) return true;
  }
  return false;
}

TextStyle? _cachedBaseStyle;
TextStyle? _cachedEmojiStyle;
double? _cachedFontSize;

TextStyle _emojiStyleFor(TextStyle? style) {
  final size = style?.fontSize;
  if (_cachedEmojiStyle != null &&
      identical(_cachedBaseStyle, style) &&
      _cachedFontSize == size) {
    return _cachedEmojiStyle!;
  }
  _cachedBaseStyle = style;
  _cachedFontSize = size;
  _cachedEmojiStyle = (style ?? const TextStyle()).copyWith(
    inherit: false,
    fontFamily: Styles.emojiFontFamily,
    fontSize: size,
    height: style?.height,
    letterSpacing: 0,
  );
  return _cachedEmojiStyle!;
}

String? _cachedText;
TextStyle? _cachedTextStyle;
List<InlineSpan>? _cachedSpans;

/// Builds emoji-aware spans. Plain text uses a fast path (no regex).
List<InlineSpan> buildEmojiAwareTextSpans(
  String text, {
  TextStyle? style,
}) {
  if (text.isEmpty) return const [];

  if (identical(_cachedText, text) &&
      identical(_cachedTextStyle, style) &&
      _cachedSpans != null) {
    return _cachedSpans!;
  }
  // Common case: Chinese/ASCII only — skip scanning splits.
  if (!textLikelyContainsEmoji(text)) {
    final spans = <InlineSpan>[TextSpan(text: text, style: style)];
    _cachedText = text;
    _cachedTextStyle = style;
    _cachedSpans = spans;
    return spans;
  }

  final emojiStyle = _emojiStyleFor(style);
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var emojiRun = false;

  void flush() {
    if (buffer.isEmpty) return;
    final chunk = buffer.toString();
    buffer.clear();
    spans.add(TextSpan(
      text: chunk,
      style: emojiRun ? emojiStyle : style,
    ));
  }

  for (final cp in text.runes) {
    final isEmoji = _isEmojiCodePoint(cp);
    if (buffer.isEmpty) {
      emojiRun = isEmoji;
      buffer.writeCharCode(cp);
      continue;
    }
    if (isEmoji == emojiRun) {
      buffer.writeCharCode(cp);
    } else {
      flush();
      emojiRun = isEmoji;
      buffer.writeCharCode(cp);
    }
  }
  flush();

  _cachedText = text;
  _cachedTextStyle = style;
  _cachedSpans = spans;
  return spans;
}
