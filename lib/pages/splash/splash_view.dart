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
      backgroundColor: const Color(0xFF003A7A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/splash_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Image.asset(
              ImageRes.splashFullscreen,
              package: 'openim_common',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48.h,
            child: Obx(() {
              final n = logic.countdown.value;
              if (n <= 0) return const SizedBox.shrink();
              return Center(
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    shadows: const [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
