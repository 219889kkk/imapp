import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'splash_logic.dart';

class SplashPage extends StatelessWidget {
  final logic = Get.find<SplashLogic>();

  SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003A7A),
      body: Image.asset(
        'assets/splash_bg.png',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Image.asset(
          ImageRes.splashFullscreen,
          package: 'openim_common',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}
