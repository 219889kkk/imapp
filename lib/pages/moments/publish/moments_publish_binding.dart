import 'package:get/get.dart';

import 'moments_publish_logic.dart';

class MomentsPublishBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MomentsPublishLogic());
  }
}
