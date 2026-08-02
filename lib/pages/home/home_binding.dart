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
    _deleteIfRegistered<HomeLogic>();
    _deleteIfRegistered<ConversationLogic>();
    _deleteIfRegistered<ConversationCategoryController>();
    _deleteIfRegistered<ContactsLogic>();
    _deleteIfRegistered<MomentsFeedLogic>();
    _deleteIfRegistered<MineLogic>();

    Get.put(HomeLogic());
    Get.put(ConversationLogic());
    Get.put(ConversationCategoryController());
    Get.put(ContactsLogic());
    Get.put(MomentsFeedLogic());
    Get.put(MineLogic());
  }

  void _deleteIfRegistered<T>() {
    if (Get.isRegistered<T>()) {
      Get.delete<T>(force: true);
    }
  }
}
