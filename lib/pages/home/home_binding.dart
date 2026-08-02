import 'package:get/get.dart';

import '../../core/controller/conversation_category_controller.dart';
import '../contacts/contacts_logic.dart';
import '../conversation/conversation_logic.dart';
import '../mine/mine_logic.dart';
import '../moments/feed/moments_feed_logic.dart';
import 'home_logic.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<HomeLogic>()) {
      Get.put(HomeLogic());
    }
    if (!Get.isRegistered<ConversationLogic>()) {
      Get.put(ConversationLogic());
    }
    if (!Get.isRegistered<ConversationCategoryController>()) {
      Get.put(ConversationCategoryController());
    }
    if (!Get.isRegistered<ContactsLogic>()) {
      Get.put(ContactsLogic());
    }
    if (!Get.isRegistered<MomentsFeedLogic>()) {
      Get.put(MomentsFeedLogic());
    }
    if (!Get.isRegistered<MineLogic>()) {
      Get.put(MineLogic());
    }
  }
}
