import 'package:get/get.dart';

import 'moments_feed_logic.dart';

class MomentsFeedBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MomentsFeedLogic());
  }
}
