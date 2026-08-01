import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji;
import 'package:flutter/material.dart';

import '../res/styles.dart';

/// Matches emoji tokens including keycap sequences, ZWJ, and variation selectors.
const _emojiTokenRegex =
    r'((\u0023|\u002a|[\u0030-\u0039])\ufe0f?\u20e3)|\p{Emoji}|\u200D|\uFE0F';

final _emojiTokenRegExp = RegExp(_emojiTokenRegex, unicode: true);

bool _isBareKeycapBase(String segment) {
  if (segment.length != 1) return false;
  final code = segment.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || code == 0x23 || code == 0x2a;
}

List<InlineSpan> buildEmojiAwareTextSpans(
  String text, {
  TextStyle? style,
}) {
  if (text.isEmpty) return const [];

  final emojiStyle = emoji.DefaultEmojiTextStyle.copyWith(
    inherit: false,
    fontFamily: Styles.emojiFontFamily,
    fontSize: style?.fontSize,
  );
  final composedEmojiStyle = (style ?? const TextStyle())
      .merge(emoji.DefaultEmojiTextStyle)
      .merge(emojiStyle);

  final matches = _emojiTokenRegExp
      .allMatches(text)
      .where(
        (match) => !_isBareKeycapBase(text.substring(match.start, match.end)),
      )
      .toList();

  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (cursor != match.start) {
      spans
        ..add(TextSpan(text: text.substring(cursor, match.start), style: style))
        ..add(TextSpan(
          text: text.substring(match.start, match.end),
          style: composedEmojiStyle,
        ));
    } else if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: composedEmojiStyle,
      ));
    } else {
      final lastIndex = spans.length - 1;
      final lastText = spans[lastIndex].text ?? '';
      final currentText = text.substring(match.start, match.end);
      spans[lastIndex] = TextSpan(
        text: '$lastText$currentText',
        style: composedEmojiStyle,
      );
    }
    cursor = match.end;
  }

  if (cursor != text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return spans;
}
