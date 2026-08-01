import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../earn/earn_view.dart';
import '../mine/mine_view.dart';
import '../moments/feed/moments_feed_view.dart';
import 'home_logic.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

class HomePage extends StatelessWidget {
  static const _tabIconSlotSize = 36.0;

  final logic = Get.find<HomeLogic>();
  HomePage({super.key});

  List<PersistentTabConfig> _tabs() => [
        PersistentTabConfig(
          screen: ConversationPage(),
          item: ItemConfig(
            icon: ImageRes.homeTab1Sel.toImage,
            title: StrRes.home,
          ),
        ),
        PersistentTabConfig(
          screen: ContactsPage(),
          item: ItemConfig(
            icon: ImageRes.homeTab2Sel.toImage,
            title: StrRes.contacts,
          ),
        ),
        PersistentTabConfig(
          screen: EarnPage(),
          item: ItemConfig(
            icon: ImageRes.homeTabEarnSel.toImage,
            title: StrRes.earnMoney,
          ),
        ),
        PersistentTabConfig(
          screen: MomentsFeedPage(),
          item: ItemConfig(
            icon: ImageRes.homeTab3Sel.toImage,
            title: StrRes.workingCircle,
          ),
        ),
        PersistentTabConfig(
          screen: MinePage(),
          item: ItemConfig(
            icon: ImageRes.homeTab4Sel.toImage,
            title: StrRes.mine,
          ),
        ),
      ];

  List<GlassTab> _glassTabs() => [
        GlassTab(
          icon: _tabIcon(ImageRes.homeTab1Nor, logic.unreadMsgCount.value),
          activeIcon:
              _tabIcon(ImageRes.homeTab1Sel, logic.unreadMsgCount.value),
          label: StrRes.home,
        ),
        GlassTab(
          icon: _tabIcon(ImageRes.homeTab2Nor, logic.unhandledCount.value),
          activeIcon:
              _tabIcon(ImageRes.homeTab2Sel, logic.unhandledCount.value),
          label: StrRes.contacts,
        ),
        GlassTab(
          icon: _tabIcon(ImageRes.homeTabEarnNor, 0, size: 36),
          activeIcon: _tabIcon(ImageRes.homeTabEarnSel, 0, size: 36),
          label: StrRes.earnMoney,
        ),
        GlassTab(
          icon: _tabIcon(ImageRes.homeTab3Nor, 0),
          activeIcon: _tabIcon(ImageRes.homeTab3Sel, 0),
          label: StrRes.workingCircle,
        ),
        GlassTab(
          icon: _tabIcon(ImageRes.homeTab4Nor, 0),
          activeIcon: _tabIcon(ImageRes.homeTab4Sel, 0),
          label: StrRes.mine,
        ),
      ];

  Widget _tabIcon(String res, int unReadCount, {double size = 24}) {
    return SizedBox(
      width: _tabIconSlotSize,
      height: _tabIconSlotSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ImageView(name: res, width: size, height: size, fit: BoxFit.contain),
          Positioned(
            top: -4,
            right: -8,
            child: UnreadCountView(count: unReadCount),
          ),
        ],
      ),
    );
  }

  Widget _buildLiquidGlassDock(NavBarConfig navBarConfig) => SafeArea(
        top: false,
        child: GlassTabBar.bottom(
          tabs: _glassTabs(),
          selectedIndex: navBarConfig.selectedIndex,
          onTabSelected: navBarConfig.onItemSelected,
          barHeight: 62,
          horizontalPadding: 24.w,
          verticalPadding: 8,
          iconSize: 24,
          iconLabelSpacing: 0,
          labelFontSize: 10,
          selectedLabelColor: Styles.c_0089FF,
          unselectedLabelColor: Styles.c_8E9AB0,
          selectedIconColor: Styles.c_0089FF,
          unselectedIconColor: Styles.c_8E9AB0,
          // Premium 走 Impeller 完整 shader 管线:底栏更通透,
          // 指示器静止时为纯玻璃透镜(无实心灰底),切换时水滴流动
          quality: GlassQuality.premium,
          // 沿用包内 iOS 26 预设的折射参数,按主题微调玻璃着色
          settings: LiquidGlassSettings(
            thickness: 30,
            blur: 3,
            chromaticAberration: 0.3,
            lightIntensity: 0.6,
            refractiveIndex: 1.59,
            saturation: 0.7,
            ambientStrength: 1,
            lightAngle: 0.75 * math.pi,
            glassColor: Styles.isDark
                ? const Color(0x22000000)
                : const Color(0x14FFFFFF),
          ),
          // 兜底:降级路径(减弱透明度/低端设备)下也不出现灰色实心块
          indicatorColor: Colors.transparent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => PersistentTabView(
            tabs: _tabs(),
            navBarBuilder: _buildLiquidGlassDock,
            navBarOverlap: const NavBarOverlap.full(),
            screenTransitionAnimation: const ScreenTransitionAnimation.none(),
          ),
        ),
      ),
    );
  }
}
