import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatNoticeView extends StatelessWidget {
  const ChatNoticeView({
    Key? key,
    required this.isISend,
    required this.content,
  }) : super(key: key);
  final bool isISend;
  final String content;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Styles.ts_0C1C33_14sp.copyWith(fontWeight: FontWeight.w500);
    final contentStyle = Styles.ts_8E9AB0_14sp;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Styles.noticeBanner,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImageRes.notice.toImage
            ..width = 16.w
            ..height = 16.h
            ..color = Styles.c_0089FF,
          6.horizontalSpace,
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${StrRes.groupAc}：', style: labelStyle),
                  TextSpan(text: content, style: contentStyle),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class TopNoticeView extends StatelessWidget {
  const TopNoticeView({
    Key? key,
    required this.content,
    this.onPreview,
    this.onClose,
  }) : super(key: key);
  final String content;
  final Function()? onPreview;
  final Function()? onClose;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Styles.ts_0C1C33_14sp.copyWith(fontWeight: FontWeight.w500);
    final contentStyle = Styles.ts_8E9AB0_14sp;
    final iconColor = Styles.isDark ? Styles.textSecondary : Styles.c_0089FF;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Styles.noticeBanner,
          child: InkWell(
            onTap: onPreview,
            child: Container(
              width: double.infinity,
              height: 40.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Row(
                children: [
                  ImageRes.notice.toImage
                    ..width = 16.w
                    ..height = 16.h
                    ..color = iconColor,
                  6.horizontalSpace,
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${StrRes.groupAc} ',
                            style: titleStyle,
                          ),
                          TextSpan(text: content, style: contentStyle),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Padding(
                      padding: EdgeInsets.only(left: 8.w),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18.w,
                        color: Styles.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: Styles.divider),
      ],
    );
  }
}
