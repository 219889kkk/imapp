import 'package:get/get.dart';

import '../account_setup/account_setup_logic.dart';

class ChatNotificationSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AccountSetupLogic());
  }
}
