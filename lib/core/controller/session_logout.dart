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
    // Suppress local alerts immediately — before any await.
    SessionGuard.markLoggedOut();

    if (Get.isRegistered<AppController>()) {
      await Get.find<AppController>().onSessionLogout();
    }

    final imCtrl = im ??
        (Get.isRegistered<IMController>() ? Get.find<IMController>() : null);
    imCtrl?.terminateAllCallsOnLogout();

    // Unbind VoIP / push WHILE chatToken is still valid, then IM logout.
    // Old order (IM logout first) left this phone ringing after multi-login kick.
    await VoipCallkitController.logoutAsync();
    await PushController.logoutAsync();

    if (imCtrl != null) {
      try {
        await imCtrl.logout();
      } catch (e, s) {
        Logger.print('SessionLogout kickoff im logout: $e $s');
      }
    }

    await DataSp.removeLoginCertificate();
    onConversationsCleared?.call();
  }
}
