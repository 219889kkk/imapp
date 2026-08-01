import 'package:get/get.dart';

import '../../core/controller/conversation_category_controller.dart';
import 'conversation_logic.dart';

class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ConversationCategoryController());
    Get.lazyPut(() => ConversationLogic());
  }
}
