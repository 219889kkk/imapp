import 'package:flutter/widgets.dart';

/// Text field controller for chat input.
///
/// Uses the platform emoji font (no custom TTF). Splitting spans with
/// NotoColorEmoji previously froze the UI on first emoji insert.
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
    // IME composing (拼音等): keep Flutter default underline path.
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

    return TextSpan(style: style, text: text);
  }
}
