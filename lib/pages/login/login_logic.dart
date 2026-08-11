import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import '../conversation/conversation_logic.dart';

enum LoginType {
  phone(0),
  email(1),
  account(2);

  final int rawValue;

  const LoginType(this.rawValue);

  static LoginType fromRawValue(int rawValue) {
    return values.firstWhere(
      (e) => e.rawValue == rawValue,
      orElse: () => LoginType.account,
    );
  }
}

extension LoginTypeExt on LoginType {
  String get name {
    switch (this) {
      case LoginType.phone:
        return StrRes.phoneNumber;
      case LoginType.email:
        return StrRes.email;
      case LoginType.account:
        return StrRes.account;
    }
  }

  String get hintText {
    switch (this) {
      case LoginType.phone:
        return StrRes.plsEnterPhoneNumber;
      case LoginType.email:
        return StrRes.plsEnterEmail;
      case LoginType.account:
        return StrRes.plsEnterAccount;
    }
  }

  String get exclusiveName {
    switch (this) {
      case LoginType.phone:
        return StrRes.email;
      case LoginType.email:
        return StrRes.phoneNumber;
      case LoginType.account:
        return StrRes.account;
    }
  }
}

class LoginLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final phoneCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final obscureText = true.obs;
  final enabled = false.obs;
  final areaCode = "+86".obs;
  final versionInfo = ''.obs;
  final loginType = LoginType.account.obs;
  String? get account => phoneCtrl.text.trim();
  LoginType operateType = LoginType.account;

  FocusNode? accountFocus = FocusNode();
  FocusNode? pwdFocus = FocusNode();

  void _initData() {
    final map = DataSp.getLoginAccount();
    if (map is Map) {
      final savedAccount = map['account']?.toString();
      final phoneNumber = map['phoneNumber']?.toString();
      if (savedAccount != null && savedAccount.isNotEmpty) {
        phoneCtrl.text = savedAccount;
      } else if (phoneNumber != null && phoneNumber.isNotEmpty) {
        phoneCtrl.text = phoneNumber;
      }
      final area = map['areaCode']?.toString();
      if (area != null && area.isNotEmpty) {
        areaCode.value = area;
      }
    }
    loginType.value = LoginType.account;
    operateType = LoginType.account;
    DataSp.putLoginType(LoginType.account.rawValue);
  }

  @override
  void onClose() {
    phoneCtrl.removeListener(_onChanged);
    pwdCtrl.removeListener(_onChanged);
    phoneCtrl.dispose();
    pwdCtrl.dispose();
    accountFocus?.dispose();
    pwdFocus?.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    _initData();
    phoneCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    super.onInit();
  }

  @override
  void onReady() {
    super.onReady();
    getPackageInfo();
  }

  void _onChanged() {
    enabled.value =
        phoneCtrl.text.trim().isNotEmpty && pwdCtrl.text.trim().isNotEmpty;
  }

  void login() {
    DataSp.putLoginType(LoginType.account.rawValue);
    // Prefer EasyLoading over Overlay LoadingView to avoid stuck blank masks.
    EasyLoading.show(status: '登录中...', dismissOnTap: false);
    () async {
      try {
        final suc = await _login();
        if (!suc) return;
        final result = await ConversationLogic.getConversationFirstPage();
        Get.find<CacheController>().resetCache();
        await EasyLoading.dismiss();
        LoadingView.singleton.dismiss();
        AppNavigator.startMain(conversations: result);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          EasyLoading.dismiss();
          LoadingView.singleton.dismiss();
        });
      } catch (e, s) {
        Logger.print('login flow e: $e $s');
        IMViews.showToast('$e');
      } finally {
        await EasyLoading.dismiss();
        LoadingView.singleton.dismiss();
      }
    }();
  }

  Future<bool> _login() async {
    try {
      if (account?.isNotEmpty != true) {
        IMViews.showToast(StrRes.plsEnterRightAccount);
        return false;
      }
      final hostBefore = Config.serverIp;
      await ServerEndpointSelector.ensureBestEndpoint();
      HttpUtil.updateBaseUrl();
      if (Config.serverIp != hostBefore) {
        await imLogic.reinitOpenIM();
      }
      final password = IMUtils.emptyStrToNull(pwdCtrl.text);
      final data = await Apis.login(
        account: account,
        password: password,
      );
      await DataSp.putLoginCertificate(data);
      await DataSp.putLoginAccount({
        'account': account,
        'loginType': LoginType.account.rawValue,
      });
      await imLogic.login(data.userID, data.imToken);
      SessionGuard.markLoggedIn();
      if (Get.isRegistered<AppController>()) {
        await Get.find<AppController>().syncNativeLoginHint(true);
      }
      PushController.login(
        data.userID,
        onTokenRefresh: (token) {
          OpenIM.iMManager.updateFcmToken(
            fcmToken: token,
            expireTime: DateTime.now()
                .add(const Duration(days: 90))
                .millisecondsSinceEpoch,
          );
        },
      );
      VoipCallkitController.login(data.userID);
      return true;
    } catch (e, s) {
      Logger.print('login e: $e $s');
    }
    return false;
  }

  void registerNow() => AppNavigator.startRegister();

  void forgetPassword() => AppNavigator.startForgetPassword();

  void getPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    versionInfo.value =
        '${packageInfo.appName} ${packageInfo.version}+${packageInfo.buildNumber} SDK: ${OpenIM.version}';
  }
}
