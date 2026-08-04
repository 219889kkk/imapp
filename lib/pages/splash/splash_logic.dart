import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';

class SplashLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final pushLogic = Get.find<PushController>();

  /// Remaining seconds shown on the splash (3 → 1 → 0).
  final countdown = 3.obs;

  String? get userID => DataSp.userID;

  String? get token => DataSp.imToken;

  late StreamSubscription initializedSub;
  Timer? _startupTimeout;
  final Completer<bool> _sdkReady = Completer<bool>();

  static const _minSplashSeconds = 3;
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
      Logger.print('splash startup timeout, continue after countdown');
      if (!_sdkReady.isCompleted) {
        _sdkReady.complete(false);
      }
    });
    _boot();
    super.onInit();
  }

  Future<void> _boot() async {
    // Hold the full splash for 3 seconds with countdown.
    for (var i = _minSplashSeconds; i >= 1; i--) {
      countdown.value = i;
      await Future.delayed(const Duration(seconds: 1));
      if (isClosed) return;
    }
    countdown.value = 0;

    final sdkOk = await _sdkReady.future;
    if (isClosed) return;

    if (sdkOk && null != userID && null != token) {
      await _login();
    } else {
      AppNavigator.startLogin();
    }
  }

  Future<void> _login() async {
    try {
      await imLogic.login(userID!, token!).timeout(const Duration(seconds: 15));
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
