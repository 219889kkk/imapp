import 'package:flutter/widgets.dart';

import 'emoji_text_span.dart';

class ChatEmojiTextEditingController extends TextEditingController {
  ChatEmojiTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    assert(!value.composing.isValid ||
        !withComposing ||
        value.isComposingRangeValid);

    final composingRegionOutOfRange =
        !value.isComposingRangeValid || !withComposing;

    if (composingRegionOutOfRange) {
      return TextSpan(
        style: style,
        children: buildEmojiAwareTextSpans(text, style: style),
      );
    }

    final underlineStyle =
        style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
            const TextStyle(decoration: TextDecoration.underline);

    return TextSpan(
      style: style,
      children: <InlineSpan>[
        TextSpan(
          children: buildEmojiAwareTextSpans(
            value.composing.textBefore(value.text),
            style: style,
          ),
        ),
        TextSpan(
          children: buildEmojiAwareTextSpans(
            value.composing.textInside(value.text),
            style: underlineStyle,
          ),
        ),
        TextSpan(
          children: buildEmojiAwareTextSpans(
            value.composing.textAfter(value.text),
            style: style,
          ),
        ),
      ],
    );
  }
}
