import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/conversation_category_controller.dart';
import 'package:openim_common/openim_common.dart';

class ConversationTagSheet extends StatefulWidget {
  const ConversationTagSheet({
    super.key,
    required this.conversationID,
  });

  final String conversationID;

  @override
  State<ConversationTagSheet> createState() => _ConversationTagSheetState();
}

class _ConversationTagSheetState extends State<ConversationTagSheet> {
  final logic = Get.find<ConversationCategoryController>();
  late final selectedIDs = <String>{
    ...(logic.config.value.conversationTags[widget.conversationID] ?? []),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: 520.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52.h,
              alignment: Alignment.center,
              child: StrRes.setConversationTags.toText
                ..style = Styles.ts_0C1C33_17sp_medium,
            ),
            Flexible(
              child: Obx(
                () => ListView(
                  shrinkWrap: true,
                  children: [
                    ...logic.config.value.customTags.map(_buildTagItem),
                    _buildCreateItem(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Button(
                text: StrRes.confirm,
                onTap: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagItem(ConversationTag tag) => StatefulBuilder(
        builder: (_, setItemState) {
          final checked = selectedIDs.contains(tag.id);
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setItemState(() {
                checked ? selectedIDs.remove(tag.id) : selectedIDs.add(tag.id);
              });
            },
            child: Container(
              height: 48.h,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  Expanded(
                    child: tag.name.toText
                      ..style = Styles.ts_0C1C33_17sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ),
                  ChatRadio(checked: checked),
                ],
              ),
            ),
          );
        },
      );

  Widget _buildCreateItem() => Container(
        height: 48.h,
        alignment: Alignment.center,
        child: StrRes.createTag.toText
          ..style = Styles.ts_0089FF_17sp
          ..onTap = logic.createTag,
      );

  Future<void> _submit() async {
    await logic.setTags(widget.conversationID, selectedIDs.toList());
    Get.back();
  }
}
