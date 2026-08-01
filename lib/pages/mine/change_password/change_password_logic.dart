import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ChangePasswordLogic extends GetxController {
  final oldPwdCtrl = TextEditingController();
  final newPwdCtrl = TextEditingController();
  final confirmPwdCtrl = TextEditingController();
  final enabled = false.obs;

  @override
  void onInit() {
    oldPwdCtrl.addListener(_onChanged);
    newPwdCtrl.addListener(_onChanged);
    confirmPwdCtrl.addListener(_onChanged);
    super.onInit();
  }

  @override
  void onClose() {
    oldPwdCtrl.dispose();
    newPwdCtrl.dispose();
    confirmPwdCtrl.dispose();
    super.onClose();
  }

  void _onChanged() {
    enabled.value = oldPwdCtrl.text.trim().isNotEmpty &&
        newPwdCtrl.text.trim().isNotEmpty &&
        confirmPwdCtrl.text.trim().isNotEmpty;
  }

  bool _checkingInput() {
    if (!IMUtils.isValidPassword(oldPwdCtrl.text)) {
      IMViews.showToast(StrRes.plsEnterOldPwd);
      return false;
    } else if (!IMUtils.isValidPassword(newPwdCtrl.text)) {
      IMViews.showToast(StrRes.wrongPasswordFormat);
      return false;
    } else if (newPwdCtrl.text != confirmPwdCtrl.text) {
      IMViews.showToast(StrRes.twicePwdNoSame);
      return false;
    }
    return true;
  }

  void confirmTheChanges() async {
    if (!_checkingInput()) return;
    final success = await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.changePassword(
        userID: OpenIM.iMManager.userID,
        currentPassword: oldPwdCtrl.text,
        newPassword: newPwdCtrl.text,
      ),
    );
    if (success == true) {
      IMViews.showToast(StrRes.changedSuccessfully);
      Get.back();
    }
  }
}
