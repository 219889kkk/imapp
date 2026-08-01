import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';

class ThemeAware extends StatelessWidget {
  const ThemeAware({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    return Obx(() {
      app.themeRevision.value;
      return builder(context);
    });
  }
}
