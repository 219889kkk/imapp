import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:search_keyword_text/search_keyword_text.dart';

import 'expand_chat_history_logic.dart';

class ExpandChatHistoryPage extends StatelessWidget {
  final logic = Get.find<ExpandChatHistoryLogic>();

  ExpandChatHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.globalSearchChatHistory),
      backgroundColor: Styles.pageBackground,
      body: ListView.builder(
        itemCount: logic.messageList.length,
        itemBuilder: (_, index) => _buildItemView(logic.messageList[index]),
      ),
    );
  }

  Widget _buildItemView(Message message) => Ink(
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: () => logic.viewMessage(message),
          child: Container(
            constraints: BoxConstraints(minHeight: 64.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            child: Row(
              children: [
                AvatarView(
                  url: message.senderFaceUrl,
                  text: message.senderNickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      SearchKeywordText(
                        text: IMUtils.parseMsg(message),
                        keyText: logic.defaultSearchKey,
                        style: Styles.ts_8E9AB0_14sp,
                        keyStyle: Styles.ts_0089FF_14sp,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
