import 'package:get/get.dart';

import 'merge_message_detail_logic.dart';

class MergeMessageDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MergeMessageDetailLogic());
  }
}
