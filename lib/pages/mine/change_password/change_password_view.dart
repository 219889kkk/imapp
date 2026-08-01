import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'change_password_logic.dart';

class ChangePasswordPage extends StatelessWidget {
  final logic = Get.find<ChangePasswordLogic>();

  ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TouchCloseSoftKeyboard(
      child: Scaffold(
        appBar: TitleBar.back(title: StrRes.changePassword),
        backgroundColor: Styles.c_FFFFFF,
        body: Obx(
          () => Padding(
            padding: EdgeInsets.symmetric(horizontal: 22.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                28.verticalSpace,
                InputBox.password(
                  label: StrRes.oldPwd,
                  hintText: StrRes.plsEnterOldPwd,
                  controller: logic.oldPwdCtrl,
                  inputFormatters: [IMUtils.getPasswordFormatter()],
                ),
                17.verticalSpace,
                InputBox.password(
                  label: StrRes.newPwd,
                  hintText: StrRes.plsEnterNewPwd,
                  controller: logic.newPwdCtrl,
                  formatHintText: StrRes.loginPwdFormat,
                  inputFormatters: [IMUtils.getPasswordFormatter()],
                ),
                17.verticalSpace,
                InputBox.password(
                  label: StrRes.confirmNewPwd,
                  hintText: StrRes.plsConfirmNewPwd,
                  controller: logic.confirmPwdCtrl,
                  inputFormatters: [IMUtils.getPasswordFormatter()],
                ),
                40.verticalSpace,
                Button(
                  text: StrRes.confirmTheChanges,
                  enabled: logic.enabled.value,
                  onTap: logic.confirmTheChanges,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
