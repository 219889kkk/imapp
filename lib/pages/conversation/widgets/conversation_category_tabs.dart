import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/conversation_category_controller.dart';
import 'package:openim_common/openim_common.dart';

class ConversationCategoryTabs extends StatelessWidget {
  ConversationCategoryTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Get.find<ConversationCategoryController>();
    return Obx(() {
      if (!logic.showTabs) return const SizedBox.shrink();
      return Container(
        height: 44.h,
        color: Styles.c_FFFFFF,
        child: ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          scrollDirection: Axis.horizontal,
          itemCount: logic.tabKeys.length,
          separatorBuilder: (_, __) => 8.horizontalSpace,
          itemBuilder: (_, index) {
            final key = logic.tabKeys[index];
            return KeyedSubtree(
              key: ValueKey('conversation_category_tab_$key'),
              child: Obx(
                () {
                  final selected = logic.selectedCategory.value == key;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => logic.selectCategory(key),
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: BoxDecoration(
                        color:
                            selected ? Styles.c_0089FF : Styles.insetBackground,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: logic.labelOf(key).toText
                        ..style = selected
                            ? Styles.ts_FFFFFF_14sp
                            : Styles.ts_0C1C33_14sp,
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }
}
