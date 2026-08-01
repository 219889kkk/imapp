import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_setup_logic.dart';

class ChatSetupPage extends StatelessWidget {
  final logic = Get.find<ChatSetupLogic>();

  ChatSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(),
      backgroundColor: Styles.pageBackground,
      body: SingleChildScrollView(
        child: Obx(() => Column(
              children: [
                _buildBaseInfoView(),
                10.verticalSpace,
                _buildItemView(
                  text: StrRes.topChat,
                  switchOn: logic.isPinned,
                  showSwitchButton: true,
                  isTopRadius: true,
                  onChanged: logic.togglePinned,
                ),
                _buildItemView(
                  text: StrRes.messageNotDisturb,
                  switchOn: logic.isNotDisturb,
                  showSwitchButton: true,
                  onChanged: logic.toggleNotDisturb,
                ),
                _buildItemView(
                  text: StrRes.burnAfterReading,
                  hintText: StrRes.burnAfterReadingDescription,
                  switchOn: logic.isPrivateChat,
                  showSwitchButton: true,
                  isBottomRadius: !logic.isPrivateChat,
                  onChanged: logic.togglePrivateChat,
                ),
                if (logic.isPrivateChat)
                  _buildItemView(
                    text: StrRes.burnDuration,
                    value: logic.burnDurationText,
                    showRightArrow: true,
                    isBottomRadius: true,
                    onTap: logic.showBurnDurationSheet,
                  ),
                10.verticalSpace,
                _buildItemView(
                  text: StrRes.quicklyFindChatHistory,
                  showRightArrow: true,
                  isTopRadius: true,
                  onTap: logic.searchChatHistory,
                ),
                _buildItemView(
                  text: StrRes.clearChatHistory,
                  textStyle: Styles.ts_FF381F_17sp,
                  isBottomRadius: true,
                  onTap: logic.clearChatHistory,
                ),
              ],
            )),
      ),
    );
  }

  Widget _buildBaseInfoView() => Container(
        margin: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: logic.viewUserInfo,
              child: SizedBox(
                width: 60.w,
                child: Column(
                  children: [
                    AvatarView(
                      width: 44.w,
                      height: 44.h,
                      text: logic.conversationInfo.value.showName,
                      url: logic.conversationInfo.value.faceURL,
                    ),
                    8.verticalSpace,
                    (logic.conversationInfo.value.showName ?? '').toText
                      ..style = Styles.ts_8E9AB0_14sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 60.w,
              child: Column(
                children: [
                  ImageRes.addFriendTobeGroup.toImage
                    ..width = 44.w
                    ..height = 44.h
                    ..onTap = logic.createGroup,
                  8.verticalSpace,
                  ''.toText
                    ..style = Styles.ts_8E9AB0_14sp
                    ..maxLines = 1
                    ..overflow = TextOverflow.ellipsis,
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildItemView({
    required String text,
    String? hintText,
    TextStyle? textStyle,
    String? value,
    bool switchOn = false,
    bool isTopRadius = false,
    bool isBottomRadius = false,
    bool showRightArrow = false,
    bool showSwitchButton = false,
    ValueChanged<bool>? onChanged,
    Function()? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          height: hintText == null ? 46.h : 68.h,
          margin: EdgeInsets.symmetric(horizontal: 10.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(isTopRadius ? 6.r : 0),
              topLeft: Radius.circular(isTopRadius ? 6.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: null != hintText
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          text.toText
                            ..style = textStyle ?? Styles.ts_0C1C33_17sp
                            ..maxLines = 1
                            ..overflow = TextOverflow.ellipsis,
                          hintText.toText
                            ..style = Styles.ts_8E9AB0_14sp
                            ..maxLines = 2
                            ..overflow = TextOverflow.ellipsis,
                        ],
                      )
                    : (text.toText
                      ..style = textStyle ?? Styles.ts_0C1C33_17sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis),
              ),
              if (null != value) value.toText..style = Styles.ts_8E9AB0_14sp,
              if (showSwitchButton) ...[
                8.horizontalSpace,
                CupertinoSwitch(
                  value: switchOn,
                  activeColor: Styles.c_0089FF,
                  onChanged: onChanged,
                ),
              ],
              if (showRightArrow)
                ImageRes.rightArrow.toImage
                  ..width = 24.w
                  ..height = 24.h,
            ],
          ),
        ),
      );
}
