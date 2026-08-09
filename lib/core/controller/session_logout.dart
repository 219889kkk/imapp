import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'app_controller.dart';
import 'im_controller.dart';

/// Central logout side-effects: stop alerts immediately, unbind push, then IM logout.
class SessionLogout {
  SessionLogout._();

  static Future<void> run({
    IMController? im,
    bool imLogout = true,
    void Function()? onConversationsCleared,
  }) async {
    SessionGuard.markLoggedOut();

    if (Get.isRegistered<AppController>()) {
      await Get.find<AppController>().onSessionLogout();
    }

    final imCtrl = im ??
        (Get.isRegistered<IMController>() ? Get.find<IMController>() : null);
    imCtrl?.terminateAllCallsOnLogout();

    await VoipCallkitController.logoutAsync();
    await PushController.logoutAsync();

    if (imLogout && imCtrl != null) {
      try {
        await imCtrl.logout();
      } catch (e, s) {
        Logger.print('SessionLogout im logout: $e $s');
      }
    }

    await DataSp.removeLoginCertificate();
    onConversationsCleared?.call();
  }

  static Future<void> runFromKickoff({
    IMController? im,
    void Function()? onConversationsCleared,
  }) async {
    SessionGuard.markLoggedOut();

    if (Get.isRegistered<AppController>()) {
      await Get.find<AppController>().onSessionLogout();
    }

    final imCtrl = im ??
        (Get.isRegistered<IMController>() ? Get.find<IMController>() : null);
    imCtrl?.terminateAllCallsOnLogout();

    if (imCtrl != null) {
      try {
        await imCtrl.logout();
      } catch (e, s) {
        Logger.print('SessionLogout kickoff im logout: $e $s');
      }
    }

    await VoipCallkitController.logoutAsync();
    await PushController.logoutAsync();
    await DataSp.removeLoginCertificate();
    onConversationsCleared?.call();
  }
}
