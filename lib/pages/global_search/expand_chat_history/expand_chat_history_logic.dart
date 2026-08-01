import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../conversation/conversation_logic.dart';

class ExpandChatHistoryLogic extends GetxController {
  final conversationLogic = Get.find<ConversationLogic>();
  late SearchResultItems searchResultItems;
  late String defaultSearchKey;

  List<Message> get messageList => searchResultItems.messageList ?? [];

  @override
  void onInit() {
    searchResultItems = Get.arguments['searchResultItems'];
    defaultSearchKey = Get.arguments['defaultSearchKey'] ?? '';
    super.onInit();
  }

  void viewMessage(Message message) async {
    final conversationID = searchResultItems.conversationID;
    if (conversationID == null) return;
    final list = await LoadingView.singleton.wrap(
      asyncFunction: () =>
          OpenIM.iMManager.conversationManager.getMultipleConversation(
        conversationIDList: [conversationID],
      ),
    );
    if (list.isEmpty) return;
    conversationLogic.toChat(
      offUntilHome: false,
      conversationInfo: list.first,
      searchMessage: message,
    );
  }
}
