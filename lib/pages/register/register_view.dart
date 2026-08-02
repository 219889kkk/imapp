import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../widgets/register_page_bg.dart';
import 'register_logic.dart';

class RegisterPage extends StatelessWidget {
  final logic = Get.find<RegisterLogic>();

  RegisterPage({super.key});

  @override
  Widget build(BuildContext context) => RegisterBgView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StrRes.newUserRegister.toText
              ..style = Styles.ts_0089FF_22sp_semibold,
            24.verticalSpace,
            InputBox(
              label: StrRes.account,
              hintText: StrRes.plsEnterAccount,
              controller: logic.accountCtrl,
            ),
            16.verticalSpace,
            InputBox(
              label: StrRes.nickname,
              hintText: StrRes.plsEnterYourNickname,
              controller: logic.nicknameCtrl,
            ),
            16.verticalSpace,
            InputBox.password(
              label: StrRes.password,
              hintText: StrRes.plsEnterPassword,
              controller: logic.pwdCtrl,
            ),
            16.verticalSpace,
            InputBox.password(
              label: StrRes.confirmPassword,
              hintText: StrRes.plsConfirmPasswordAgain,
              controller: logic.pwdAgainCtrl,
            ),
            40.verticalSpace,
            Obx(() => Button(
                  text: StrRes.registerNow,
                  enabled: logic.enabled.value,
                  onTap: logic.register,
                )),
          ],
        ),
      );
}
