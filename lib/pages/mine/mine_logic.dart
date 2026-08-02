import 'dart:async';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';

class MineLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final refreshController = RefreshController();

  late StreamSubscription kickedOfflineSub;

  void viewMyInfo() => AppNavigator.startMyInfo();

  void copyID() {
    final account = imLogic.userInfo.value.account?.trim();
    IMUtils.copy(
      text: (account != null && account.isNotEmpty)
          ? account
          : imLogic.userInfo.value.userID!,
    );
  }

  String get idLineText {
    final account = imLogic.userInfo.value.account?.trim();
    final userID = imLogic.userInfo.value.userID ?? '';
    if (account != null && account.isNotEmpty) {
      return '${StrRes.account}:$account';
    }
    return '${StrRes.userID}:$userID';
  }

  void chatNotificationSetup() => AppNavigator.startChatNotificationSetup();

  void privacySecuritySetup() => AppNavigator.startPrivacySecuritySetup();

  void appearanceLanguageSetup() => AppNavigator.startAppearanceLanguageSetup();

  void workbench() => AppNavigator.startWorkbench();

  void aboutUs() => AppNavigator.startAboutUs();

  void myQrcode() => AppNavigator.startMyQrcode();

  void logout() async {
    var confirm = await Get.dialog(CustomDialog(title: StrRes.logoutHint));
    if (confirm == true) {
      try {
        await LoadingView.singleton.wrap(asyncFunction: () async {
          await imLogic.logout();
          await DataSp.removeLoginCertificate();
          PushController.logout();
          Get.find<HomeLogic>().conversationsAtFirstPage.clear();
        });
        AppNavigator.startLogin();
      } catch (e) {
        IMViews.showToast('e:$e');
      }
    }
  }

  void kickedOffline({String? tips}) async {
    if (EasyLoading.isShow) {
      EasyLoading.dismiss();
    }
    Get.snackbar(StrRes.accountWarn, tips ?? StrRes.accountException);
    await DataSp.removeLoginCertificate();
    PushController.logout();
    AppNavigator.startLogin();
  }

  @override
  void onInit() {
    kickedOfflineSub = imLogic.onKickedOfflineSubject.listen((value) {
      if (value == KickoffType.userTokenInvalid) {
        kickedOffline(tips: StrRes.tokenInvalid);
      } else {
        kickedOffline();
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    refreshController.dispose();
    kickedOfflineSub.cancel();
    super.onClose();
  }

  Future<void> onRefresh() async {
    try {
      final data = await Apis.queryMyFullInfo();
      if (data is UserFullInfo) {
        imLogic.userInfo.update((val) {
          val?.allowAddFriend = data.allowAddFriend;
          val?.allowBeep = data.allowBeep;
          val?.allowVibration = data.allowVibration;
          val?.nickname = data.nickname;
          val?.faceURL = data.faceURL;
          val?.phoneNumber = data.phoneNumber;
          val?.email = data.email;
          val?.birth = data.birth;
          val?.gender = data.gender;
          val?.signature = data.signature;
          val?.account = data.account;
        });
      }
      refreshController.refreshCompleted();
    } catch (_) {
      refreshController.refreshFailed();
    }
  }
}
