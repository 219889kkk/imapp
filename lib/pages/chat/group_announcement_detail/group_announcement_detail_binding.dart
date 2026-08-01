import 'package:get/get.dart';

import 'group_announcement_detail_logic.dart';

class GroupAnnouncementDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => GroupAnnouncementDetailLogic());
  }
}
