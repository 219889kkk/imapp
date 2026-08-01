import 'package:get/get.dart';

import 'theme_setup_logic.dart';

class ThemeSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ThemeSetupLogic());
  }
}
