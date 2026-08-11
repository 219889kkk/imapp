import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';

class SplashLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final pushLogic = Get.find<PushController>();
  final appLogic = Get.find<AppController>();

  String? get userID => DataSp.userID;

  String? get token => DataSp.imToken;

  late StreamSubscription initializedSub;
  Timer? _startupTimeout;
  final Completer<bool> _sdkReady = Completer<bool>();

  static const _sdkWaitSeconds = 12;

  @override
  void onInit() {
    initializedSub = imLogic.initializedSubject.listen((initialized) {
      _startupTimeout?.cancel();
      if (!_sdkReady.isCompleted) {
        _sdkReady.complete(initialized == true);
      }
    });
    _startupTimeout = Timer(Duration(seconds: _sdkWaitSeconds), () {
      Logger.print('splash startup timeout, continue to login/main');
      if (!_sdkReady.isCompleted) {
        _sdkReady.complete(false);
      }
    });
    _boot();
    super.onInit();
  }

  Future<void> _boot() async {
    // No session → wipe stale icon badge immediately (reinstall / logged-out).
    final hasSession = (userID?.trim().isNotEmpty ?? false) &&
        (token?.trim().isNotEmpty ?? false);
    if (!hasSession) {
      SessionGuard.markLoggedOut();
      await appLogic.syncNativeLoginHint(false);
      appLogic.clearBadgeForLoggedOut();
    } else {
      await appLogic.syncNativeLoginHint(true);
    }

    // No artificial countdown — leave as soon as SDK init finishes (or times out).
    final sdkOk = await _sdkReady.future;
    if (isClosed) return;

    if (sdkOk && null != userID && null != token) {
      final hostBefore = Config.serverIp;
      await ServerEndpointSelector.ensureBestEndpoint();
      HttpUtil.updateBaseUrl();
      if (Config.serverIp != hostBefore) {
        await imLogic.reinitOpenIM();
      }
      await _login();
    } else {
      SessionGuard.markLoggedOut();
      await appLogic.syncNativeLoginHint(false);
      appLogic.clearBadgeForLoggedOut();
      AppNavigator.startLogin();
    }
  }

  Future<void> _login() async {
    try {
      await imLogic.login(userID!, token!).timeout(const Duration(seconds: 15));
      SessionGuard.markLoggedIn();
      await appLogic.syncNativeLoginHint(true);
      PushController.login(
        userID!,
        onTokenRefresh: (token) {
          OpenIM.iMManager.updateFcmToken(
              fcmToken: token,
              expireTime: DateTime.now()
                  .add(const Duration(days: 90))
                  .millisecondsSinceEpoch);
        },
      );
      VoipCallkitController.login(userID!);
      final result = await ConversationLogic.getConversationFirstPage()
          .timeout(const Duration(seconds: 15));

      AppNavigator.startSplashToMain(isAutoLogin: true, conversations: result);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LoadingView.singleton.dismiss();
        EasyLoading.dismiss();
      });
    } catch (e, s) {
      Logger.print('splash auto login failed: $e $s');
      IMViews.showToast('$e');
      await DataSp.removeLoginCertificate();
      SessionGuard.markLoggedOut();
      await appLogic.syncNativeLoginHint(false);
      appLogic.clearBadgeForLoggedOut();
      AppNavigator.startLogin();
    }
  }

  @override
  void onClose() {
    _startupTimeout?.cancel();
    initializedSub.cancel();
    if (!_sdkReady.isCompleted) {
      _sdkReady.complete(false);
    }
    super.onClose();
  }
}
