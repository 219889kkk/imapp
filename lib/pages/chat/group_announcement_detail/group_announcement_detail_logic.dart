import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class GroupAnnouncementDetailLogic extends GetxController {
  late String content;
  late int updateTime;

  @override
  void onInit() {
    content = Get.arguments['content'] ?? '';
    updateTime = Get.arguments['updateTime'] ?? 0;
    super.onInit();
  }

  bool get hasUpdateTime => updateTime > 0;

  String get updateTimeText => IMUtils.getChatTimeline(updateTime);
}
