import 'package:get/get.dart';

import 'chat_read_detail_logic.dart';

class ChatReadDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ChatReadDetailLogic());
  }
}
