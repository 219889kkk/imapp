import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'contacts_logic.dart';

class ContactsPage extends StatelessWidget {
  final logic = Get.find<ContactsLogic>();

  ContactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (context) => Scaffold(
        appBar: TitleBar.contacts(
          onClickAddContacts: logic.addContacts,
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => SmartRefresher(
            controller: logic.refreshController,
            onRefresh: logic.onRefresh,
            header: IMViews.buildHeader(),
            enablePullUp: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: [
                  _buildItemView(
                    assetsName: ImageRes.newFriend,
                    label: StrRes.newFriend,
                    count: logic.friendApplicationCount,
                    onTap: logic.newFriend,
                  ),
                  _buildItemView(
                    assetsName: ImageRes.newGroup,
                    label: StrRes.newGroupRequest,
                    count: logic.groupApplicationCount,
                    onTap: logic.newGroup,
                  ),
                  10.verticalSpace,
                  _buildItemView(
                    assetsName: ImageRes.myFriend,
                    label: StrRes.myFriend,
                    onTap: logic.myFriend,
                  ),
                  _buildItemView(
                    assetsName: ImageRes.myGroup,
                    label: StrRes.myGroup,
                    onTap: logic.myGroup,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemView({
    String? assetsName,
    required String label,
    Widget? icon,
    int count = 0,
    bool showRightArrow = true,
    double? height,
    Function()? onTap,
  }) =>
      Ink(
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height ?? 60.h,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                if (null != assetsName)
                  assetsName.toImage
                    ..width = 42.w
                    ..height = 42.h,
                if (null != icon) icon,
                12.horizontalSpace,
                label.toText..style = Styles.ts_0C1C33_17sp,
                const Spacer(),
                if (count > 0) UnreadCountView(count: count),
                4.horizontalSpace,
                if (showRightArrow)
                  ImageRes.rightArrow.toImage
                    ..width = 24.w
                    ..height = 24.h,
              ],
            ),
          ),
        ),
      );
}
