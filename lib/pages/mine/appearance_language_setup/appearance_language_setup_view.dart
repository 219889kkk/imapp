import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import '../account_setup/account_setup_logic.dart';
import '../widgets/mine_setting_item.dart';

class AppearanceLanguageSetupPage extends StatelessWidget {
  final logic = Get.find<AccountSetupLogic>();

  AppearanceLanguageSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(
          title: StrRes.appearanceLanguageSetup,
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => SingleChildScrollView(
            child: Column(
              children: [
                10.verticalSpace,
                MineSettingItem(
                  label: StrRes.themeSetup,
                  value:
                      '${logic.curThemeMode.value} · ${logic.curThemeColorName.value}',
                  onTap: logic.themeSetting,
                  showRightArrow: true,
                  isTopRadius: true,
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
          ),
        ),
      ),
    );
  }
}
