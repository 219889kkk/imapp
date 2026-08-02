import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../mine/mine_view.dart';
import '../moments/feed/moments_feed_view.dart';
import 'home_logic.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _tabIconSlotSize = 36.0;

  final logic = Get.find<HomeLogic>();
  late final List<PersistentTabConfig> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
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
  }

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

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Obx(() {
        logic.unreadMsgCount.value;
        logic.unhandledCount.value;
        return PersistentTabView(
          tabs: _tabs,
          backgroundColor: Styles.pageBackground,
          navBarBuilder: (config) => Style1BottomNavBar(
            navBarConfig: NavBarConfig(
              selectedIndex: config.selectedIndex,
              items: [
                ItemConfig(
                  icon: _tabIcon(ImageRes.homeTab1Sel, logic.unreadMsgCount.value),
                  inactiveIcon:
                      _tabIcon(ImageRes.homeTab1Nor, logic.unreadMsgCount.value),
                  title: StrRes.home,
                ),
                ItemConfig(
                  icon: _tabIcon(ImageRes.homeTab2Sel, logic.unhandledCount.value),
                  inactiveIcon:
                      _tabIcon(ImageRes.homeTab2Nor, logic.unhandledCount.value),
                  title: StrRes.contacts,
                ),
                ItemConfig(
                  icon: _tabIcon(ImageRes.homeTab3Sel, 0),
                  inactiveIcon: _tabIcon(ImageRes.homeTab3Nor, 0),
                  title: StrRes.workingCircle,
                ),
                ItemConfig(
                  icon: _tabIcon(ImageRes.homeTab4Sel, 0),
                  inactiveIcon: _tabIcon(ImageRes.homeTab4Nor, 0),
                  title: StrRes.mine,
                ),
              ],
              navBarHeight: config.navBarHeight,
              onItemSelected: config.onItemSelected,
            ),
            navBarDecoration: NavBarDecoration(
              color: Styles.c_FFFFFF,
              boxShadow: [
                BoxShadow(
                  color: Styles.c_000000_opacity4,
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
          ),
          navBarOverlap: const NavBarOverlap.none(),
          screenTransitionAnimation: const ScreenTransitionAnimation.none(),
        );
      }),
    );
  }
}
