import 'package:get/get.dart';

import '../../core/controller/conversation_category_controller.dart';
import '../contacts/contacts_logic.dart';
import '../conversation/conversation_logic.dart';
import '../earn/earn_logic.dart';
import '../mine/mine_logic.dart';
import '../moments/feed/moments_feed_logic.dart';
import 'home_logic.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HomeLogic());
    Get.lazyPut(() => ConversationLogic());
    Get.lazyPut(() => ConversationCategoryController());
    Get.lazyPut(() => ContactsLogic());
    Get.lazyPut(() => EarnLogic());
    Get.lazyPut(() => MomentsFeedLogic());
    Get.lazyPut(() => MineLogic());
  }
}
