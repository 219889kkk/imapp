import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/conversation_category_controller.dart';
import 'package:openim_common/openim_common.dart';

class ConversationCategoryManageSheet extends StatelessWidget {
  final logic = Get.find<ConversationCategoryController>();

  ConversationCategoryManageSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: 620.h),
      decoration: BoxDecoration(
        color: Styles.pageBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
      ),
      child: Obx(
        () => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildSwitchItem(
                StrRes.enableChatFolders,
                logic.config.value.folderTabsEnabled,
                logic.toggleFolderTabs,
              ),
              _buildSectionTitle(StrRes.autoCategories),
              _buildSwitchItem(
                StrRes.unreadConversations,
                logic.autoEnabled(ConversationAutoCategory.unread),
                (value) => logic.toggleAutoCategory(
                  ConversationAutoCategory.unread,
                  value,
                ),
              ),
              _buildSwitchItem(
                StrRes.singleChats,
                logic.autoEnabled(ConversationAutoCategory.single),
                (value) => logic.toggleAutoCategory(
                  ConversationAutoCategory.single,
                  value,
                ),
              ),
              _buildSwitchItem(
                StrRes.groupChats,
                logic.autoEnabled(ConversationAutoCategory.group),
                (value) => logic.toggleAutoCategory(
                  ConversationAutoCategory.group,
                  value,
                ),
              ),
              _buildSectionTitle(StrRes.setConversationTags),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...logic.config.value.customTags.map(_buildTagItem),
                    _buildActionItem(StrRes.createTag, logic.createTag),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        height: 52.h,
        color: Styles.c_FFFFFF,
        alignment: Alignment.center,
        child: StrRes.chatFolders.toText..style = Styles.ts_0C1C33_17sp_medium,
      );

  Widget _buildSectionTitle(String title) => Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 6.h),
        child: title.toText..style = Styles.ts_8E9AB0_14sp,
      );

  Widget _buildSwitchItem(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      Container(
        height: 48.h,
        color: Styles.c_FFFFFF,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            title.toText..style = Styles.ts_0C1C33_17sp,
            const Spacer(),
            CupertinoSwitch(
              value: value,
              activeColor: Styles.c_0089FF,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _buildTagItem(ConversationTag tag) => Container(
        height: 48.h,
        color: Styles.c_FFFFFF,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            Expanded(
              child: tag.name.toText
                ..style = Styles.ts_0C1C33_17sp
                ..maxLines = 1
                ..overflow = TextOverflow.ellipsis,
            ),
            StrRes.renameTag.toText
              ..style = Styles.ts_0089FF_14sp
              ..onTap = () => logic.renameTag(tag),
            16.horizontalSpace,
            StrRes.delete.toText
              ..style = Styles.ts_FF381F_17sp
              ..onTap = () => logic.deleteTag(tag),
          ],
        ),
      );

  Widget _buildActionItem(String title, VoidCallback onTap) => Container(
        height: 48.h,
        color: Styles.c_FFFFFF,
        alignment: Alignment.center,
        child: title.toText
          ..style = Styles.ts_0089FF_17sp
          ..onTap = onTap,
      );
}
