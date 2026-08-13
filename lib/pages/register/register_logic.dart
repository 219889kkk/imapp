import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';

class RegisterLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final accountCtrl = TextEditingController();
  final nicknameCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final pwdAgainCtrl = TextEditingController();
  final enabled = false.obs;

  @override
  void onClose() {
    accountCtrl.dispose();
    nicknameCtrl.dispose();
    pwdCtrl.dispose();
    pwdAgainCtrl.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    accountCtrl.addListener(_onChanged);
    nicknameCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    pwdAgainCtrl.addListener(_onChanged);
    super.onInit();
  }

  void _onChanged() {
    enabled.value = accountCtrl.text.trim().isNotEmpty &&
        nicknameCtrl.text.trim().isNotEmpty &&
        pwdCtrl.text.trim().isNotEmpty &&
        pwdAgainCtrl.text.trim().isNotEmpty;
  }

  bool _checkingInput() {
    if (accountCtrl.text.trim().isEmpty) {
      IMViews.showToast(StrRes.plsEnterAccount);
      return false;
    }
    if (nicknameCtrl.text.trim().isEmpty) {
      IMViews.showToast(StrRes.plsEnterYourNickname);
      return false;
    }
    if (!IMUtils.isValidPassword(pwdCtrl.text)) {
      IMViews.showToast(StrRes.wrongPasswordFormat);
      return false;
    }
    if (pwdCtrl.text != pwdAgainCtrl.text) {
      IMViews.showToast(StrRes.twicePwdNoSame);
      return false;
    }
    return true;
  }

  void register() async {
    if (!_checkingInput()) return;

    final account = accountCtrl.text.trim();
    final nickname = nicknameCtrl.text.trim();

    await LoadingView.singleton.wrap(asyncFunction: () async {
      final data = await Apis.register(
        nickname: nickname,
        account: account,
        password: pwdCtrl.text,
      );
      if (null == IMUtils.emptyStrToNull(data.imToken) ||
          null == IMUtils.emptyStrToNull(data.chatToken)) {
        AppNavigator.startLogin();
        return;
      }
      await DataSp.putLoginCertificate(data);
      await DataSp.putLoginAccount({
        'account': account,
        'loginType': 2,
      });
      DataSp.putLoginType(2);
      await imLogic.login(data.userID, data.imToken);
      SessionGuard.markLoggedIn();
      if (Get.isRegistered<AppController>()) {
        await Get.find<AppController>().syncNativeLoginHint(true);
      }
      PushController.login(data.userID);
      VoipCallkitController.login(data.userID);
    });
    AppNavigator.startMain();
  }
}
