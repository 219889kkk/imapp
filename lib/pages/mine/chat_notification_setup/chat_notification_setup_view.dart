import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import '../account_setup/account_setup_logic.dart';
import '../widgets/mine_setting_item.dart';

class ChatNotificationSetupPage extends StatelessWidget {
  final logic = Get.find<AccountSetupLogic>();

  ChatNotificationSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(
          title: StrRes.chatNotificationSetup,
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => SingleChildScrollView(
            child: Column(
              children: [
                10.verticalSpace,
                MineSettingItem(
                  label: StrRes.msgNotification,
                  switchOn: logic.enableMsgNotification.value,
                  showSwitchButton: true,
                  onChanged: logic.toggleMsgNotification,
                  isTopRadius: true,
                ),
                MineSettingItem(
                  label: StrRes.callNotification,
                  switchOn: logic.enableCallNotification.value,
                  showSwitchButton: true,
                  onChanged: logic.toggleCallNotification,
                ),
                MineSettingItem(
                  label: StrRes.notificationShowDetail,
                  switchOn: logic.showNotificationDetail.value,
                  showSwitchButton: true,
                  onChanged: logic.toggleShowNotificationDetail,
                  isBottomRadius: true,
                ),
                10.verticalSpace,
                MineSettingItem(
                  label: StrRes.messageSound,
                  switchOn: logic.isAllowBeep,
                  showSwitchButton: true,
                  onChanged: logic.toggleBeep,
                  isTopRadius: true,
                ),
                MineSettingItem(
                  label: StrRes.messageNotDisturb,
                  switchOn: logic.isGlobalNotDisturb,
                  showSwitchButton: true,
                  onChanged: logic.toggleGlobalNotDisturb,
                ),
                MineSettingItem(
                  label: StrRes.chatFolders,
                  onTap: logic.chatFolders,
                  showRightArrow: true,
                  isBottomRadius: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
