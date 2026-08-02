import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/home_debug.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_logic.dart';
import '../conversation/conversation_view.dart';
import '../mine/mine_view.dart';
import '../moments/feed/moments_feed_view.dart';
import 'home_logic.dart';

/// Temporary on-screen diagnostics for blank-home investigation.
const bool kHomeDebugBanner = true;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Map<int, Widget> _pageCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LoadingView.singleton.dismiss();
    });
  }

  Widget _pageFor(int index) {
    return _pageCache.putIfAbsent(index, () {
      try {
        switch (index) {
          case 0:
            return ConversationPage();
          case 1:
            return ContactsPage();
          case 2:
            return MomentsFeedPage();
          case 3:
            return MinePage();
          default:
            return const SizedBox.shrink();
        }
      } catch (e, s) {
        Logger.print('home tab $index create failed: $e $s');
        return _TabErrorView(tab: index, error: e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeLogic>()) {
      return const Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Text(
            'DEBUG: HomeLogic 未注册',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    final logic = Get.find<HomeLogic>();
    return Scaffold(
      backgroundColor: Styles.pageBackground,
      body: Column(
        children: [
          if (kHomeDebugBanner) _DebugBanner(logic: logic),
          Expanded(
            child: Obx(() {
              final index = logic.index.value;
              return KeyedSubtree(
                key: ValueKey('home_tab_$index'),
                child: _SafeTab(child: _pageFor(index)),
              );
            }),
          ),
        ],
      ),
      bottomNavigationBar: Obx(() {
        final index = logic.index.value;
        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0089FF),
          unselectedItemColor: const Color(0xFF8E9AB0),
          selectedFontSize: 10,
          unselectedFontSize: 10,
          currentIndex: index,
          onTap: logic.switchTab,
          items: [
            BottomNavigationBarItem(
              icon: _badgeIcon(
                  Icons.chat_bubble_outline, logic.unreadMsgCount.value),
              activeIcon:
                  _badgeIcon(Icons.chat_bubble, logic.unreadMsgCount.value),
              label: StrRes.home,
            ),
            BottomNavigationBarItem(
              icon: _badgeIcon(
                  Icons.contacts_outlined, logic.unhandledCount.value),
              activeIcon: _badgeIcon(Icons.contacts, logic.unhandledCount.value),
              label: StrRes.contacts,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.public_outlined),
              activeIcon: const Icon(Icons.public),
              label: StrRes.workingCircle,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline),
              activeIcon: const Icon(Icons.person),
              label: StrRes.mine,
            ),
          ],
        );
      }),
    );
  }

  static Widget _badgeIcon(IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}

class _SafeTab extends StatelessWidget {
  const _SafeTab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _TabErrorView extends StatelessWidget {
  const _TabErrorView({required this.tab, required this.error});

  final int tab;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Tab$tab 渲染失败:\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _DebugBanner extends StatelessWidget {
  const _DebugBanner({required this.logic});

  final HomeLogic logic;

  @override
  Widget build(BuildContext context) {
    final imOk = Get.isRegistered<IMController>();
    final convOk = Get.isRegistered<ConversationLogic>();
    final size = MediaQuery.sizeOf(context);
    return Material(
      color: const Color(0xFFFFEB3B),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: ValueListenableBuilder<String?>(
            valueListenable: homeDebugError,
            builder: (_, err, __) {
              return Obx(() {
                final nickname = imOk
                    ? (Get.find<IMController>().userInfo.value.nickname ?? '-')
                    : 'no-im';
                final convCount =
                    convOk ? Get.find<ConversationLogic>().list.length : -1;
                final errLine = (err == null || err.isEmpty)
                    ? ''
                    : '\nERR: ${err.split('\n').first}';
                return Text(
                  'DEBUG HOME ok | tab=${logic.index.value} | '
                  'size=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)} | '
                  'user=$nickname | conv=$convCount | '
                  'Home/IM/Conv=${Get.isRegistered<HomeLogic>()}/$imOk/$convOk'
                  '$errLine',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    height: 1.3,
                  ),
                );
              });
            },
          ),
        ),
      ),
    );
  }
}
