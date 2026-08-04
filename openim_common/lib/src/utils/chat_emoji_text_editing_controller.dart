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

    final text = value.text;
    // IME composing (拼音等): keep Flutter default underline path without
    // splitting emoji spans — major win for Chinese typing latency.
    final composing = value.composing;
    if (withComposing && value.isComposingRangeValid) {
      final underlineStyle =
          style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
              const TextStyle(decoration: TextDecoration.underline);
      return TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(
            text: composing.textBefore(text),
            style: style,
          ),
          TextSpan(
            text: composing.textInside(text),
            style: underlineStyle,
          ),
          TextSpan(
            text: composing.textAfter(text),
            style: style,
          ),
        ],
      );
    }

    if (!textLikelyContainsEmoji(text)) {
      return TextSpan(style: style, text: text);
    }

    return TextSpan(
      style: style,
      children: buildEmojiAwareTextSpans(text, style: style),
    );
  }
}
