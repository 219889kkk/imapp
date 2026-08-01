import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/core/controller/conversation_category_controller.dart';
import 'package:openim/pages/conversation/widgets/conversation_category_manage_sheet.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';

class AccountSetupLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final categoryLogic = Get.isRegistered<ConversationCategoryController>()
      ? Get.find<ConversationCategoryController>()
      : Get.put(ConversationCategoryController());
  final curLanguage = "".obs;
  final curThemeMode = "".obs;
  final curThemeColorName = "".obs;
  final enableMsgNotification = DataSp.getEnableMsgNotification().obs;
  final enableCallNotification = DataSp.getEnableCallNotification().obs;
  final showNotificationDetail = DataSp.getShowNotificationDetail().obs;

  bool get isGlobalNotDisturb => imLogic.userInfo.value.globalRecvMsgOpt != 0;

  bool get isAllowBeep => imLogic.userInfo.value.allowBeep == 1;

  @override
  void onReady() {
    _updateLanguage();
    _updateThemeAppearance();
    super.onReady();
  }

  @override
  void onInit() {
    _queryMyFullInfo();
    super.onInit();
  }

  void _queryMyFullInfo() async {
    final data = await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.queryMyFullInfo(),
    );
    if (data is UserFullInfo) {
      final userInfo = UserFullInfo.fromJson(data.toJson());
      imLogic.userInfo.update((val) {
        val?.allowAddFriend = userInfo.allowAddFriend;
        val?.allowBeep = userInfo.allowBeep;
        val?.allowVibration = userInfo.allowVibration;
        val?.globalRecvMsgOpt = userInfo.globalRecvMsgOpt;
      });
    }
  }

  Future<void> toggleGlobalNotDisturb(bool value) async {
    final recvMsgOpt = value ? 2 : 0;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.userManager.setSelfInfo(
        globalRecvMsgOpt: recvMsgOpt,
      ),
    );
    imLogic.userInfo.update((val) {
      val?.globalRecvMsgOpt = recvMsgOpt;
    });
  }

  Future<void> toggleMsgNotification(bool value) async {
    enableMsgNotification.value = value;
    await DataSp.putEnableMsgNotification(value);
  }

  Future<void> toggleCallNotification(bool value) async {
    enableCallNotification.value = value;
    await DataSp.putEnableCallNotification(value);
  }

  Future<void> toggleShowNotificationDetail(bool value) async {
    showNotificationDetail.value = value;
    await DataSp.putShowNotificationDetail(value);
  }

  Future<void> toggleBeep(bool value) async {
    final allowBeep = value ? 1 : 2;
    await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.updateUserInfo(
        userID: OpenIM.iMManager.userID,
        allowBeep: allowBeep,
      ),
    );
    imLogic.userInfo.update((val) {
      val?.allowBeep = allowBeep;
    });
  }

  void blacklist() => AppNavigator.startBlacklist();

  void changePassword() => AppNavigator.startChangePassword();

  void myQrcode() => AppNavigator.startMyQrcode();

  void chatFolders() {
    categoryLogic.load();
    Get.bottomSheet(
      ConversationCategoryManageSheet(),
      isScrollControlled: true,
    );
  }

  void languageSetting() => AppNavigator.startLanguageSetup()?.then((_) => _updateLanguage());

  void themeSetting() => AppNavigator.startThemeSetup()?.then((_) => _updateThemeAppearance());

  void _updateLanguage() {
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        curLanguage.value = StrRes.chinese;
        break;
      case 2:
        curLanguage.value = StrRes.english;
        break;
      default:
        curLanguage.value = StrRes.followSystem;
        break;
    }
  }

  void _updateThemeAppearance() {
    final index = DataSp.getThemeMode();
    switch (index) {
      case 1:
        curThemeMode.value = StrRes.lightMode;
        break;
      case 2:
        curThemeMode.value = StrRes.darkMode;
        break;
      default:
        curThemeMode.value = StrRes.followSystem;
        break;
    }
    curThemeColorName.value = ThemeColorPresets.labelFor(Color(DataSp.getThemeColor()));
  }
}
