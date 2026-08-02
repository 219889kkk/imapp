import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import '../account_setup/account_setup_logic.dart';
import '../widgets/mine_setting_item.dart';

class PrivacySecuritySetupPage extends StatelessWidget {
  final logic = Get.find<AccountSetupLogic>();

  PrivacySecuritySetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => Scaffold(
        appBar: TitleBar.back(
          title: StrRes.privacySecuritySetup,
        ),
        backgroundColor: Styles.pageBackground,
        body: SingleChildScrollView(
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
                label: StrRes.blacklist,
                onTap: logic.blacklist,
                showRightArrow: true,
                isBottomRadius: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
