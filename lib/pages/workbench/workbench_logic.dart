import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

class WorkbenchLogic extends GetxController {
  final applets = <UniMPInfo>[].obs;
  final agents = <AgentInfo>[].obs;
  final loading = false.obs;

  @override
  void onReady() {
    refreshWorkbench();
    super.onReady();
  }

  Future<void> refreshWorkbench() async {
    loading.value = true;
    try {
      final result = await Future.wait([
        Apis.findApplets(),
        Apis.pageFindAgents(),
      ]);
      applets.assignAll(result[0] as List<UniMPInfo>);
      agents.assignAll((result[1] as AgentPageResp).agents);
    } finally {
      loading.value = false;
    }
  }

  void openApplet(UniMPInfo applet) {
    final url = applet.url;
    if (url == null || url.isEmpty) return;
    AppNavigator.startH5(url: url, title: applet.name);
  }

  Future<void> chatWithAgent(AgentInfo agent) async {
    final conversation =
        await OpenIM.iMManager.conversationManager.getOneConversation(
      sourceID: agent.userID,
      sessionType: ConversationType.single,
    );
    AppNavigator.startChat(conversationInfo: conversation);
  }
}
