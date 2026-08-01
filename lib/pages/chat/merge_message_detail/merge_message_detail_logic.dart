import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class MergeMessageDetailLogic extends GetxController {
  late String title;
  late List<Message> messages;

  @override
  void onInit() {
    title = Get.arguments['title'] ?? StrRes.chatRecord;
    messages = (Get.arguments['messages'] as List<Message>?) ?? const [];
    super.onInit();
  }
}
