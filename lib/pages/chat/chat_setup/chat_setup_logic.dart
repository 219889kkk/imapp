import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/app_controller.dart';
import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../chat_logic.dart';

class ChatSetupLogic extends GetxController {
  final chatLogic = Get.find<ChatLogic>(tag: GetTags.chat);
  final appLogic = Get.find<AppController>();
  final imLogic = Get.find<IMController>();
  late Rx<ConversationInfo> conversationInfo;
  late StreamSubscription ccSub;
  late StreamSubscription fcSub;

  String get conversationID => conversationInfo.value.conversationID;

  bool get isPinned => conversationInfo.value.isPinned == true;

  bool get isNotDisturb => conversationInfo.value.recvMsgOpt != 0;

  bool get isPrivateChat => conversationInfo.value.isPrivateChat == true;

  int get burnDuration => conversationInfo.value.burnDuration ?? 30;

  static const burnDurationOptions = [30, 60, 300, 3600];

  String get burnDurationText {
    switch (burnDuration) {
      case 30:
        return StrRes.burnDuration30Seconds;
      case 60:
        return StrRes.burnDuration1Minute;
      case 300:
        return StrRes.burnDuration5Minutes;
      case 3600:
        return StrRes.burnDuration1Hour;
      default:
        return '$burnDuration${StrRes.seconds}';
    }
  }

  @override
  void onClose() {
    ccSub.cancel();
    fcSub.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    conversationInfo = Rx(Get.arguments['conversationInfo']);
    final sourceID =
        conversationInfo.value.conversationType == ConversationType.single
            ? conversationInfo.value.userID
            : conversationInfo.value.groupID;
    OpenIM.iMManager.conversationManager
        .getOneConversation(
            sourceID: sourceID!,
            sessionType: conversationInfo.value.conversationType!)
        .then((value) {
      conversationInfo.value = value;
    });

    ccSub = imLogic.conversationChangedSubject.listen((newList) {
      for (var newValue in newList) {
        if (newValue.conversationID == conversationID) {
          conversationInfo.update((val) {
            val?.burnDuration = newValue.burnDuration ?? 30;
            val?.isPrivateChat = newValue.isPrivateChat;
            val?.isPinned = newValue.isPinned;

            val?.recvMsgOpt = newValue.recvMsgOpt;
            val?.isMsgDestruct = newValue.isMsgDestruct;
            val?.msgDestructTime = newValue.msgDestructTime;
            val?.showName = newValue.showName;
          });
          break;
        }
      }
    });

    fcSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (conversationInfo.value.userID == value.userID) {
        conversationInfo.update((val) {
          val?.showName = value.getShowName();
          val?.faceURL = value.faceURL;
        });
      }
    });
    super.onInit();
  }

  void createGroup() => AppNavigator.startCreateGroup(defaultCheckedList: [
        UserInfo(
          userID: conversationInfo.value.userID,
          faceURL: conversationInfo.value.faceURL,
          nickname: conversationInfo.value.showName,
        ),
        OpenIM.iMManager.userInfo,
      ]);

  void viewUserInfo() => AppNavigator.startUserProfilePane(
        userID: conversationInfo.value.userID!,
        nickname: conversationInfo.value.showName,
        faceURL: conversationInfo.value.faceURL,
      );

  Future<void> togglePinned(bool value) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        conversationID,
        ConversationReq(isPinned: value),
      ),
    );
    conversationInfo.update((val) {
      val?.isPinned = value;
    });
  }

  Future<void> toggleNotDisturb(bool value) async {
    final recvMsgOpt = value ? 2 : 0;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        conversationID,
        ConversationReq(recvMsgOpt: recvMsgOpt),
      ),
    );
    conversationInfo.update((val) {
      val?.recvMsgOpt = recvMsgOpt;
    });
  }

  Future<void> togglePrivateChat(bool value) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        conversationID,
        ConversationReq(
          isPrivateChat: value,
          burnDuration: burnDuration,
        ),
      ),
    );
    conversationInfo.update((val) {
      val?.isPrivateChat = value;
      val?.burnDuration ??= 30;
    });
  }

  void showBurnDurationSheet() {
    Get.bottomSheet(
      BottomSheetView(
        items: burnDurationOptions
            .map(
              (seconds) => SheetItem(
                label: _burnDurationLabel(seconds),
                onTap: () => updateBurnDuration(seconds),
              ),
            )
            .toList(),
      ),
    );
  }

  String _burnDurationLabel(int seconds) {
    switch (seconds) {
      case 30:
        return StrRes.burnDuration30Seconds;
      case 60:
        return StrRes.burnDuration1Minute;
      case 300:
        return StrRes.burnDuration5Minutes;
      case 3600:
        return StrRes.burnDuration1Hour;
      default:
        return '$seconds${StrRes.seconds}';
    }
  }

  Future<void> updateBurnDuration(int seconds) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        conversationID,
        ConversationReq(burnDuration: seconds),
      ),
    );
    conversationInfo.update((val) {
      val?.burnDuration = seconds;
    });
  }

  void searchChatHistory() => AppNavigator.startGlobalSearch();

  Future<void> clearChatHistory() async {
    final confirm = await Get.dialog(CustomDialog(
      title: StrRes.confirmClearChatHistory,
    ));
    if (confirm != true) return;
    await LoadingView.singleton.wrap(
      asyncFunction: () =>
          OpenIM.iMManager.conversationManager.clearConversationAndDeleteAllMsg(
        conversationID: conversationID,
      ),
    );
    chatLogic.clearAllMessage();
  }
}
