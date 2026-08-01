import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class MomentsCommentInput {
  static Future<String?> show(
    BuildContext context, {
    String? replyToNickname,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MomentsCommentInputSheet(
        replyToNickname: replyToNickname,
      ),
    );
  }
}

class _MomentsCommentInputSheet extends StatefulWidget {
  const _MomentsCommentInputSheet({this.replyToNickname});

  final String? replyToNickname;

  @override
  State<_MomentsCommentInputSheet> createState() =>
      _MomentsCommentInputSheetState();
}

class _MomentsCommentInputSheetState extends State<_MomentsCommentInputSheet> {
  final _inputCtrl = TextEditingController();

  String get _hintText {
    final nickname = widget.replyToNickname?.trim();
    if (nickname == null || nickname.isEmpty) {
      return StrRes.momentCommentHint;
    }
    return '${StrRes.reply} $nickname';
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(content);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        color: Styles.c_FFFFFF,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  autofocus: true,
                  style: Styles.ts_0C1C33_17sp,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _hintText,
                    hintStyle: Styles.ts_8E9AB0_17sp,
                    filled: true,
                    fillColor: Styles.inputBackground,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 10.h,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              8.horizontalSpace,
              GestureDetector(
                onTap: _submit,
                child: ImageRes.sendMessage.toImage
                  ..width = 28.w
                  ..height = 28.h,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
