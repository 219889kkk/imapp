import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import 'merge_message_detail_logic.dart';

class MergeMessageDetailPage extends StatelessWidget {
  final logic = Get.find<MergeMessageDetailLogic>();

  MergeMessageDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(title: logic.title),
        backgroundColor: Styles.pageBackground,
        body: logic.messages.isEmpty
            ? Center(
                child: StrRes.unsupportedMessage.toText
                  ..style = Styles.ts_8E9AB0_14sp,
              )
            : ListView.builder(
                itemCount: logic.messages.length,
                itemBuilder: (_, index) =>
                    _buildItemView(logic.messages[index]),
              ),
      ),
    );
  }

  Widget _buildItemView(Message message) => Ink(
        color: Styles.c_FFFFFF,
        child: InkWell(
          child: Container(
            constraints: BoxConstraints(minHeight: 64.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Styles.c_E8EAEF, width: .5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AvatarView(
                  url: message.senderFaceUrl,
                  text: message.senderNickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: (message.senderNickname ?? '').toText
                              ..style = Styles.ts_0C1C33_17sp
                              ..maxLines = 1
                              ..overflow = TextOverflow.ellipsis,
                          ),
                          if (message.sendTime != null)
                            IMUtils.getChatTimeline(message.sendTime!).toText
                              ..style = Styles.ts_8E9AB0_14sp,
                        ],
                      ),
                      6.verticalSpace,
                      IMUtils.parseMsg(message).toText
                        ..style = Styles.ts_8E9AB0_14sp,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
