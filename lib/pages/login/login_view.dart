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
              child: IntrinsicHeight(
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
                        // Closer to login + slightly larger tap target.
                        28.verticalSpace,
                        RichText(
                          text: TextSpan(
                            text: StrRes.noAccountYet,
                            style: Styles.ts_8E9AB0_14sp,
                            children: [
                              TextSpan(
                                text: StrRes.registerNow,
                                style: Styles.ts_0089FF_14sp,
                                recognizer: TapGestureRecognizer()
                                  ..onTap = logic.registerNow,
                              )
                            ],
                          ),
                        ),
                      ]),
                    ),
                    const Spacer(),
                    // Bottom version: smaller, light weight, sit near screen edge.
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: Obx(
                        () => Text(
                          logic.versionInfo.value,
                          style: TextStyle(
                            color: Styles.c_8E9AB0,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
