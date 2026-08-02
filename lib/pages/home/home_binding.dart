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
    // Recreate home-scoped controllers for a clean post-login state.
    _reput(() => HomeLogic());
    _reput(() => ConversationLogic());
    _reput(() => ConversationCategoryController());
    _reput(() => ContactsLogic());
    _reput(() => MomentsFeedLogic());
    _reput(() => MineLogic());
  }

  void _reput<T>(T Function() builder) {
    if (Get.isRegistered<T>()) {
      Get.delete<T>(force: true);
    }
    Get.put<T>(builder());
  }
}
