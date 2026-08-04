import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'login_logic.dart';

class LoginPage extends StatelessWidget {
  LoginPage({super.key});

  LoginLogic get logic => Get.find<LoginLogic>();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final minHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: TouchCloseSoftKeyboard(
          isGradientBg: true,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                children: [
                  88.verticalSpace,
                  // Same artwork as desktop AppIcon; rounded like iOS mask.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22.r),
                    child: ImageRes.loginLogo.toImage
                      ..width = 96.w
                      ..height = 96.h
                      ..fit = BoxFit.cover,
                  ),
                  StrRes.welcome.toText..style = Styles.ts_0089FF_17sp_semibold,
                  51.verticalSpace,
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.w),
                    child: Column(children: [
                      InputBox.account(
                        label: '',
                        hintText: StrRes.plsEnterAccount,
                        code: logic.areaCode.value,
                        onAreaCode: null,
                        controller: logic.phoneCtrl,
                        focusNode: logic.accountFocus,
                        keyBoardType: TextInputType.text,
                      ),
                      8.verticalSpace,
                      InputBox.password(
                        label: '',
                        hintText: StrRes.plsEnterPassword,
                        controller: logic.pwdCtrl,
                        focusNode: logic.pwdFocus,
                      ),
                      46.verticalSpace,
                      Obx(() => SizedBox(
                            width: double.infinity,
                            child: Button(
                              text: StrRes.login,
                              enabled: logic.enabled.value,
                              onTap: logic.login,
                            ),
                          )),
                    ]),
                  ),
                  100.verticalSpace,
                  RichText(
                    text: TextSpan(
                      text: StrRes.noAccountYet,
                      style: Styles.ts_8E9AB0_12sp,
                      children: [
                        TextSpan(
                          text: StrRes.registerNow,
                          style: Styles.ts_0089FF_12sp,
                          recognizer: TapGestureRecognizer()
                            ..onTap = logic.registerNow,
                        )
                      ],
                    ),
                  ),
                  32.verticalSpace,
                  Obx(() =>
                      logic.versionInfo.value.toText..style = Styles.ts_0C1C33_14sp),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
