import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'mine_logic.dart';
import 'widgets/mine_menu_icon.dart';

class _MineMenuItem {
  final MineMenuIconType iconType;
  final String label;
  final VoidCallback? onTap;

  const _MineMenuItem({
    required this.iconType,
    required this.label,
    this.onTap,
  });
}

class MinePage extends StatelessWidget {
  final logic = Get.find<MineLogic>();

  MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (context) => Scaffold(
        backgroundColor: Styles.pageBackground,
        body: SmartRefresher(
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
                Stack(
                  children: [
                    Container(
                      height: 138.h,
                      width: 1.sw,
                      color: Styles.c_0089FF,
                      child: ImageRes.mineHeaderBg.toImage,
                    ),
                    Obx(() => _buildMyInfoView()),
                  ],
                ),
                10.verticalSpace,
                _buildMenuGroup([
                  _MineMenuItem(
                    iconType: MineMenuIconType.myInfo,
                    label: StrRes.myInfo,
                    onTap: logic.viewMyInfo,
                  ),
                  _MineMenuItem(
                    iconType: MineMenuIconType.chatNotification,
                    label: StrRes.chatNotificationSetup,
                    onTap: logic.chatNotificationSetup,
                  ),
                  _MineMenuItem(
                    iconType: MineMenuIconType.privacySecurity,
                    label: StrRes.privacySecuritySetup,
                    onTap: logic.privacySecuritySetup,
                  ),
                  _MineMenuItem(
                    iconType: MineMenuIconType.appearanceLanguage,
                    label: StrRes.appearanceLanguageSetup,
                    onTap: logic.appearanceLanguageSetup,
                  ),
                  _MineMenuItem(
                    iconType: MineMenuIconType.discover,
                    label: StrRes.workbench,
                    onTap: logic.workbench,
                  ),
                  _MineMenuItem(
                    iconType: MineMenuIconType.aboutUs,
                    label: StrRes.aboutUs,
                    onTap: logic.aboutUs,
                  ),
                ]),
                10.verticalSpace,
                _buildMenuGroup([
                  _MineMenuItem(
                    iconType: MineMenuIconType.logout,
                    label: StrRes.logout,
                    onTap: logic.logout,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyInfoView() => Container(
        height: 98.h,
        margin: EdgeInsets.only(left: 16.w, right: 16.w, top: 90.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Row(
          children: [
            AvatarView(
              url: logic.imLogic.userInfo.value.faceURL,
              text: logic.imLogic.userInfo.value.nickname,
              width: 48.w,
              height: 48.h,
              textStyle: Styles.ts_FFFFFF_14sp,
            ),
            10.horizontalSpace,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  (logic.imLogic.userInfo.value.nickname ?? '').toText
                    ..style = Styles.ts_0C1C33_17sp_medium,
                  4.verticalSpace,
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: logic.copyID,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        (logic.imLogic.userInfo.value.userID ?? '').toText
                          ..style = Styles.ts_8E9AB0_14sp,
                        ImageRes.mineCopy.toImage
                          ..width = 16.w
                          ..height = 16.h,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildMenuGroup(List<_MineMenuItem> items) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.circular(6.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final item in items) _buildGroupItemView(item: item),
        ],
      ),
    );
  }

  Widget _buildGroupItemView({required _MineMenuItem item}) => InkWell(
        onTap: item.onTap,
        child: Container(
          height: 56.h,
          padding: EdgeInsets.only(left: 12.w, right: 16.w),
          child: Row(
            children: [
              MineMenuIcon(type: item.iconType),
              11.horizontalSpace,
              item.label.toText..style = Styles.ts_0C1C33_17sp,
              const Spacer(),
              ImageRes.rightArrow.toImage
                ..width = 24.w
                ..height = 24.h,
            ],
          ),
        ),
      );
}
