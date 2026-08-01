import 'package:get/get.dart';

import '../account_setup/account_setup_logic.dart';

class AppearanceLanguageSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AccountSetupLogic());
  }
}
