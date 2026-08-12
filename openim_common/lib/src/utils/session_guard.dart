import 'data_sp.dart';

/// Blocks message/call notifications after logout until next login.
class SessionGuard {
  SessionGuard._();

  static bool suppressNotifications = false;

  static bool get _hasCredentials {
    final id = DataSp.userID?.trim() ?? '';
    final token = DataSp.imToken?.trim() ?? '';
    return id.isNotEmpty && token.isNotEmpty;
  }

  /// Heal stuck [suppressNotifications] when login cert is still present
  /// (kick/logout races used to leave suppress=true and kill all call rings).
  static void _healIfLoggedIn() {
    if (suppressNotifications && _hasCredentials) {
      suppressNotifications = false;
    }
  }

  static bool get shouldNotify {
    _healIfLoggedIn();
    return !suppressNotifications && _hasCredentials;
  }

  static void markLoggedIn() {
    suppressNotifications = false;
  }

  static void markLoggedOut() {
    suppressNotifications = true;
  }
}
