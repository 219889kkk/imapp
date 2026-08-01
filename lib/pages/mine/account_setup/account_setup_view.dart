import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/mine_setting_item.dart';
import 'account_setup_logic.dart';

class AccountSetupPage extends StatelessWidget {
  final logic = Get.find<AccountSetupLogic>();

  AccountSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(
          title: StrRes.accountSetup,
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(() => SingleChildScrollView(
              child: Column(
                children: [
                  10.verticalSpace,
                  MineSettingItem(
                    label: StrRes.changePassword,
                    onTap: logic.changePassword,
                    showRightArrow: true,
                    isTopRadius: true,
                  ),
                  MineSettingItem(
                    label: StrRes.qrcode,
                    onTap: logic.myQrcode,
                    showRightArrow: true,
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
                  ),
                  MineSettingItem(
                    label: StrRes.blacklist,
                    onTap: logic.blacklist,
                    showRightArrow: true,
                  ),
                  MineSettingItem(
                    label: StrRes.themeSetup,
                    value:
                        '${logic.curThemeMode.value} · ${logic.curThemeColorName.value}',
                    onTap: logic.themeSetting,
                    showRightArrow: true,
                  ),
                  MineSettingItem(
                    label: StrRes.languageSetup,
                    value: logic.curLanguage.value,
                    onTap: logic.languageSetting,
                    showRightArrow: true,
                    isBottomRadius: true,
                  ),
                ],
              ),
            )),
      ),
    );
  }
}
