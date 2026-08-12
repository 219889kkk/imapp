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
    // Zero server+icon badge BEFORE marking logged out / killing IM session.
    if (Get.isRegistered<AppController>()) {
      try {
        if (OpenIM.iMManager.isLogined) {
          await OpenIM.iMManager.messageManager.setAppBadge(0);
        }
      } catch (e, s) {
        Logger.print('SessionLogout setAppBadge(0): $e $s');
      }
      await Get.find<AppController>().onSessionLogout();
    }

    SessionGuard.markLoggedOut();

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
    if (Get.isRegistered<AppController>()) {
      Get.find<AppController>().clearBadgeForLoggedOut();
    }
    onConversationsCleared?.call();
  }

  static Future<void> runFromKickoff({
    IMController? im,
    void Function()? onConversationsCleared,
  }) async {
    if (Get.isRegistered<AppController>()) {
      try {
        if (OpenIM.iMManager.isLogined) {
          await OpenIM.iMManager.messageManager.setAppBadge(0);
        }
      } catch (e, s) {
        Logger.print('SessionLogout kickoff setAppBadge(0): $e $s');
      }
      await Get.find<AppController>().onSessionLogout();
    }

    SessionGuard.markLoggedOut();

    final imCtrl = im ??
        (Get.isRegistered<IMController>() ? Get.find<IMController>() : null);
    imCtrl?.terminateAllCallsOnLogout();

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
    if (Get.isRegistered<AppController>()) {
      Get.find<AppController>().clearBadgeForLoggedOut();
    }
    onConversationsCleared?.call();
  }
}
