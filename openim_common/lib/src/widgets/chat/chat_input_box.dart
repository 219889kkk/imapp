import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

double kInputBoxMinHeight = 56.h;

class ChatInputBox extends StatefulWidget {
  const ChatInputBox({
    super.key,
    required this.toolbox,
    required this.voiceRecordBar,
    this.controller,
    this.focusNode,
    this.style,
    this.atStyle,
    this.enabled = true,
    this.isNotInGroup = false,
    this.hintText,
    this.forceCloseToolboxSub,
    this.quoteContent,
    this.onClearQuote,
    this.onSend,
    this.directionalText,
    this.onCloseDirectional,
  });
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final TextStyle? style;
  final TextStyle? atStyle;
  final bool enabled;
  final bool isNotInGroup;
  final String? hintText;
  final Widget toolbox;
  final Widget voiceRecordBar;
  final Stream? forceCloseToolboxSub;
  final String? quoteContent;
  final Function()? onClearQuote;
  final ValueChanged<String>? onSend;
  final TextSpan? directionalText;
  final VoidCallback? onCloseDirectional;

  @override
  State<ChatInputBox> createState() => _ChatInputBoxState();
}

class _ChatInputBoxState
    extends State<ChatInputBox> /*with TickerProviderStateMixin */ {
  bool _toolsVisible = false;
  bool _emojiVisible = false;
  bool _leftKeyboardButton = false;

  bool get _showQuoteView => IMUtils.isNotNullEmptyStr(widget.quoteContent);

  double get _opacity => (widget.enabled ? 1 : .4);

  bool get _showDirectionalView => widget.directionalText != null;

  @override
  void initState() {
    widget.focusNode?.addListener(() {
      if (widget.focusNode!.hasFocus) {
        setState(() {
          _toolsVisible = false;
          _emojiVisible = false;
          _leftKeyboardButton = false;
        });
      }
    });

    widget.forceCloseToolboxSub?.listen((value) {
      if (!mounted) return;
      setState(() {
        _toolsVisible = false;
        _emojiVisible = false;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) widget.controller?.clear();
    return widget.isNotInGroup
        ? const ChatDisableInputBox()
        : Column(
            children: [
              Container(
                constraints: BoxConstraints(minHeight: kInputBoxMinHeight),
                color: Styles.c_F0F2F6,
                child: Row(
                  children: [
                    12.horizontalSpace,
                    (_leftKeyboardButton
                            ? ImageRes.openKeyboard
                            : ImageRes.openVoice)
                        .toImage
                      ..width = 32.w
                      ..height = 32.h
                      ..color = Styles.c_0C1C33
                      ..opacity = _opacity
                      ..onTap =
                          _leftKeyboardButton ? onTapLeftKeyboard : onTapVoice,
                    8.horizontalSpace,
                    Expanded(
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: _leftKeyboardButton,
                            child: _textFiled,
                          ),
                          Offstage(
                            offstage: !_leftKeyboardButton,
                            child: widget.voiceRecordBar,
                          ),
                        ],
                      ),
                    ),
                    if (!_leftKeyboardButton) ...[
                      8.horizontalSpace,
                      (_emojiVisible
                              ? ImageRes.openKeyboard
                              : ImageRes.openEmoji)
                          .toImage
                        ..width = 32.w
                        ..height = 32.h
                        ..color = Styles.c_0C1C33
                        ..opacity = _opacity
                        ..onTap = _emojiVisible
                            ? onTapRightKeyboard
                            : toggleEmojiPanel,
                    ],
                    8.horizontalSpace,
                    _buildActionButton(),
                    12.horizontalSpace,
                  ],
                ),
              ),
              if (_showDirectionalView)
                _SubView(
                  textSpan: widget.directionalText,
                  onClose: () {
                    widget.onCloseDirectional?.call();
                  },
                ),
              if (_showQuoteView)
                _SubView(
                  content: widget.quoteContent,
                  onClose: () {
                    widget.onClearQuote?.call();
                  },
                ),
              Visibility(
                visible: _toolsVisible,
                child: FadeInUp(
                  duration: const Duration(milliseconds: 200),
                  child: widget.toolbox,
                ),
              ),
              if (widget.controller != null)
                Offstage(
                  offstage: !_emojiVisible,
                  child: TickerMode(
                    enabled: _emojiVisible,
                    child: ChatEmojiPanel(controller: widget.controller!),
                  ),
                ),
            ],
          );
  }

  Widget get _textFiled => Container(
        margin: EdgeInsets.only(top: 10.h, bottom: _showQuoteView ? 4.h : 10.h),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: ChatTextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: widget.style ?? Styles.ts_0C1C33_17sp,
          atStyle: widget.atStyle ?? Styles.ts_0089FF_17sp,
          enabled: widget.enabled,
          hintText: widget.hintText,
          textAlign: widget.enabled ? TextAlign.start : TextAlign.center,
        ),
      );

  Widget _buildActionButton() {
    final controller = widget.controller;
    if (controller == null) return _buildToolboxButton();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, __) =>
          value.text.isNotEmpty ? _buildSendButton() : _buildToolboxButton(),
    );
  }

  Widget _buildSendButton() => ImageRes.sendMessage.toImage
    ..width = 32.w
    ..height = 32.h
    ..opacity = _opacity
    ..onTap = send;

  Widget _buildToolboxButton() => ImageRes.openToolbox.toImage
    ..width = 32.w
    ..height = 32.h
    ..color = Styles.c_0C1C33
    ..opacity = _opacity
    ..onTap = toggleToolbox;

  void send() {
    if (!widget.enabled) return;
    if (null != widget.onSend && null != widget.controller) {
      widget.onSend!(widget.controller!.text.toString().trim());
    }
  }

  void toggleToolbox() {
    if (!widget.enabled) return;
    setState(() {
      _toolsVisible = !_toolsVisible;
      _emojiVisible = false;
      _leftKeyboardButton = false;
      if (_toolsVisible) {
        unfocus();
      } else {
        focus();
      }
    });
  }

  void toggleEmojiPanel() {
    if (!widget.enabled) return;
    setState(() {
      _emojiVisible = !_emojiVisible;
      _toolsVisible = false;
      _leftKeyboardButton = false;
      if (_emojiVisible) {
        unfocus();
      } else {
        focus();
      }
    });
  }

  void onTapLeftKeyboard() {
    if (!widget.enabled) return;
    setState(() {
      _leftKeyboardButton = false;
      _toolsVisible = false;
      _emojiVisible = false;
      focus();
    });
  }

  void onTapRightKeyboard() {
    if (!widget.enabled) return;
    setState(() {
      _toolsVisible = false;
      _emojiVisible = false;
      focus();
    });
  }

  void onTapVoice() {
    if (!widget.enabled) return;
    setState(() {
      _leftKeyboardButton = true;
      _toolsVisible = false;
      _emojiVisible = false;
      unfocus();
    });
  }

  void focus() => FocusScope.of(context).requestFocus(widget.focusNode);

  void unfocus() => FocusScope.of(context).requestFocus(FocusNode());
}

class _SubView extends StatelessWidget {
  const _SubView({
    this.onClose,
    this.content,
    this.textSpan,
  }) : assert(content != null || textSpan != null,
            'Either content or textSpan must be provided.');
  final VoidCallback? onClose;
  final String? content;
  final InlineSpan? textSpan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: 10.h, left: 56.w, right: 100.w),
      color: Styles.c_F0F2F6,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onClose,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: 4.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  children: [
                    if (content != null)
                      Text(
                        content!,
                        style: Styles.ts_8E9AB0_14sp,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (textSpan != null)
                      Expanded(
                        child: RichText(
                          text: textSpan!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              ImageRes.delQuote.toImage
                ..width = 14.w
                ..height = 14.h,
            ],
          ),
        ),
      ),
    );
  }
}
