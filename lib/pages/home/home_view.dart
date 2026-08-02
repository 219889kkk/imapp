import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

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

  List<Widget>? _pages;

  List<Widget> _ensurePages() {
    return _pages ??= [
      ConversationPage(),
      ContactsPage(),
      MomentsFeedPage(),
      MinePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final logic = Get.find<HomeLogic>();
    return Scaffold(
      backgroundColor: Styles.pageBackground,
      body: Obx(
        () => IndexedStack(
          index: logic.index.value,
          children: _ensurePages(),
        ),
      ),
      bottomNavigationBar: Obx(() => _buildBottomBar(logic)),
    );
  }

  Widget _buildBottomBar(HomeLogic logic) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Styles.c_FFFFFF,
      selectedItemColor: Styles.c_0089FF,
      unselectedItemColor: Styles.c_8E9AB0,
      selectedFontSize: 10,
      unselectedFontSize: 10,
      currentIndex: logic.index.value,
      onTap: logic.switchTab,
      items: [
        BottomNavigationBarItem(
          icon: _tabIcon(ImageRes.homeTab1Nor, logic.unreadMsgCount.value),
          activeIcon: _tabIcon(ImageRes.homeTab1Sel, logic.unreadMsgCount.value),
          label: StrRes.home,
        ),
        BottomNavigationBarItem(
          icon: _tabIcon(ImageRes.homeTab2Nor, logic.unhandledCount.value),
          activeIcon: _tabIcon(ImageRes.homeTab2Sel, logic.unhandledCount.value),
          label: StrRes.contacts,
        ),
        BottomNavigationBarItem(
          icon: _tabIcon(ImageRes.homeTab3Nor, 0),
          activeIcon: _tabIcon(ImageRes.homeTab3Sel, 0),
          label: StrRes.workingCircle,
        ),
        BottomNavigationBarItem(
          icon: _tabIcon(ImageRes.homeTab4Nor, 0),
          activeIcon: _tabIcon(ImageRes.homeTab4Sel, 0),
          label: StrRes.mine,
        ),
      ],
    );
  }

  static Widget _tabIcon(String res, int unReadCount, {double size = 24}) {
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
}
