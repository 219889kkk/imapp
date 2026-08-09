import 'data_sp.dart';

/// Blocks message/call notifications after logout until next login.
class SessionGuard {
  SessionGuard._();

  static bool suppressNotifications = false;

  static bool get shouldNotify =>
      !suppressNotifications &&
      DataSp.userID != null &&
      DataSp.userID!.isNotEmpty;

  static void markLoggedIn() {
    suppressNotifications = false;
  }

  static void markLoggedOut() {
    suppressNotifications = true;
  }
}
