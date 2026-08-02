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
    // Order matters: ConversationLogic finds ConversationCategoryController
    // in its field initializers. Wrong order caused release blank screen
    // (obfuscated as "npb" not found).
    _reput<HomeLogic>(() => HomeLogic());
    _reput<ConversationCategoryController>(
        () => ConversationCategoryController());
    _reput<ConversationLogic>(() => ConversationLogic());
    _reput<ContactsLogic>(() => ContactsLogic());
    _reput<MomentsFeedLogic>(() => MomentsFeedLogic());
    _reput<MineLogic>(() => MineLogic());
  }

  void _reput<T extends GetxController>(T Function() builder) {
    if (Get.isRegistered<T>()) {
      Get.delete<T>(force: true);
    }
    Get.put<T>(builder(), permanent: false);
  }
}
