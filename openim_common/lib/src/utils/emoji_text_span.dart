import 'package:flutter/material.dart';

/// Fast emoji-range check (avoids expensive `\p{Emoji}` regex).
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

/// Builds text spans for chat content.
///
/// Uses the platform emoji font — do NOT force NotoColorEmoji.ttf (~23MB);
/// loading that TTF on the UI thread freezes the app when tapping an emoji.
List<InlineSpan> buildEmojiAwareTextSpans(
  String text, {
  TextStyle? style,
}) {
  if (text.isEmpty) return const [];
  return [TextSpan(text: text, style: style)];
}
