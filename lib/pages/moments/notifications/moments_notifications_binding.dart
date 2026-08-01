import 'package:get/get.dart';

import 'moments_notifications_logic.dart';

class MomentsNotificationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MomentsNotificationsLogic());
  }
}
