import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';

import 'conversation_logic.dart';
import 'widgets/conversation_category_tabs.dart';

class ConversationPage extends StatelessWidget {
  ConversationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Get.find<ConversationLogic>();
    return ThemeAware(
      builder: (context) => Scaffold(
        backgroundColor: Styles.pageBackground,
        appBar: TitleBar.conversation(
            statusStr: logic.imSdkStatus,
            isFailed: logic.isFailedSdkStatus,
            popCtrl: logic.popCtrl,
            onScan: logic.scan,
            onAddFriend: logic.addFriend,
            onAddGroup: logic.addGroup,
            onCreateGroup: logic.createGroup,
            onClearUnread: logic.clearAllUnread,
            onGlobalSearch: logic.globalSearch,
            left: Obx(
              () => Expanded(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Flexible(
                      child: StrRes.home.toText
                        ..style = Styles.ts_0C1C33_17sp_semibold
                        ..maxLines = 1
                        ..overflow = TextOverflow.ellipsis,
                    ),
                    10.horizontalSpace,
                    if (logic.imSdkStatus != null &&
                        (!logic.reInstall || logic.isFailedSdkStatus))
                      Flexible(
                        child: SyncStatusView(
                          isFailed: logic.isFailedSdkStatus,
                          statusStr: logic.imSdkStatus!,
                        ),
                      ),
                  ],
                ),
              ),
            )),
        body: Column(
          children: [
            ConversationCategoryTabs(),
            Expanded(
              child: Obx(
                () {
                  final category = logic.categoryLogic.selectedCategory.value;
                  final items = logic.categoryLogic.filter(logic.list);
                  return SmartRefresher(
                    controller: logic.refreshController,
                    onRefresh: logic.onRefresh,
                    header: IMViews.buildHeader(),
                    enablePullUp: false,
                    child: ListView.builder(
                      key: ValueKey('conv_list_$category'),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom,
                      ),
                      itemBuilder: (_, index) => _buildItemView(logic, items[index]),
                      itemCount: items.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemView(ConversationLogic logic, ConversationInfo info) => Ink(
        color: info.isPinned == true ? Styles.c_F0F2F6 : Styles.c_FFFFFF,
        child: InkWell(
          onTap: () => logic.toChat(conversationInfo: info),
          onLongPress: () => logic.showConversationActionSheet(info),
          child: Stack(
            children: [
              Container(
                height: 68.h,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        AvatarView(
                          width: 48.w,
                          height: 48.h,
                          text: logic.getShowName(info),
                          url: info.faceURL,
                          isGroup: logic.isGroupChat(info),
                          textStyle: Styles.ts_FFFFFF_14sp_medium,
                        ),
                      ],
                    ),
                    12.horizontalSpace,
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: logic.getShowName(info).toText
                                        ..style = Styles.ts_0C1C33_17sp
                                        ..maxLines = 1
                                        ..overflow = TextOverflow.ellipsis,
                                    ),
                                    ...logic.categoryLogic
                                        .tagsOf(info.conversationID)
                                        .map(
                                          (tag) => Container(
                                            margin: EdgeInsets.only(left: 6.w),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6.w,
                                              vertical: 2.h,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Styles.insetBackground,
                                              borderRadius:
                                                  BorderRadius.circular(8.r),
                                            ),
                                            child: tag.name.toText
                                              ..style = Styles.ts_8E9AB0_10sp
                                              ..maxLines = 1
                                              ..overflow =
                                                  TextOverflow.ellipsis,
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                              logic.getTime(info).toText
                                ..style = Styles.ts_8E9AB0_12sp,
                            ],
                          ),
                          3.verticalSpace,
                          Row(
                            children: [
                              MatchTextView(
                                text: logic.getContent(info),
                                textStyle: Styles.ts_8E9AB0_14sp,
                                prefixSpan: TextSpan(
                                  text: '',
                                  children: [
                                    if (logic.getUnreadCount(info) > 0)
                                      TextSpan(
                                        text: '[${sprintf(StrRes.nPieces, [
                                              logic.getUnreadCount(info)
                                            ])}] ',
                                        style: Styles.ts_8E9AB0_14sp,
                                      ),
                                    TextSpan(
                                      text: logic.getPrefixTag(info),
                                      style: Styles.ts_0089FF_14sp,
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Spacer(),
                              if (logic.isNotDisturb(info))
                                ImageRes.notDisturb.toImage
                                  ..width = 16.w
                                  ..height = 16.h,
                              if (logic.isNotDisturb(info)) 6.horizontalSpace,
                              UnreadCountView(
                                  count: logic.getUnreadCount(info)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
