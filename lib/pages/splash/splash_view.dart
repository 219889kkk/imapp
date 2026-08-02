import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'splash_logic.dart';

class SplashPage extends StatelessWidget {
  final logic = Get.find<SplashLogic>();

  SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.c_0089FF,
      body: SizedBox.expand(
        child: Image.asset(
          ImageRes.splashFullscreen,
          package: 'openim_common',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ImageRes.splashLogo.toImage
                  ..width = 120
                  ..height = 120,
                16.verticalSpace,
                StrRes.welcome.toText..style = Styles.ts_FFFFFF_17sp,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
