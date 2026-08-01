import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import 'earn_logic.dart';

class EarnPage extends StatelessWidget {
  final logic = Get.find<EarnLogic>();

  EarnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (context) => Scaffold(
        backgroundColor: Styles.pageBackground,
        appBar: AppBar(
          backgroundColor: Styles.c_FFFFFF,
          elevation: 0,
          centerTitle: true,
          title: StrRes.earnMoney.toText..style = Styles.ts_0C1C33_17sp_medium,
        ),
        body: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Center(
            child: StrRes.earnComingSoon.toText..style = Styles.ts_8E9AB0_17sp,
          ),
        ),
      ),
    );
  }
}
