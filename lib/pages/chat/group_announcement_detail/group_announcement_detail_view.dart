import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import 'group_announcement_detail_logic.dart';

class GroupAnnouncementDetailPage extends StatelessWidget {
  final logic = Get.find<GroupAnnouncementDetailLogic>();

  GroupAnnouncementDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(title: StrRes.groupAc),
        backgroundColor: Styles.pageBackground,
        body: logic.content.trim().isEmpty
            ? Center(
                child: StrRes.unsupportedMessage.toText
                  ..style = Styles.ts_8E9AB0_14sp,
              )
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: Styles.c_FFFFFF,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: logic.content.toText
                        ..style = Styles.ts_0C1C33_17sp,
                    ),
                    if (logic.hasUpdateTime) ...[
                      12.verticalSpace,
                      logic.updateTimeText.toText
                        ..style = Styles.ts_8E9AB0_14sp,
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
