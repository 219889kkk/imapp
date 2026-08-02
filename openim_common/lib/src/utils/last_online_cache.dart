import 'sp_util.dart';
import 'utils.dart';

/// Local cache of last-online timestamps (ms since epoch).
/// Updated when a subscribed user transitions to offline.
class LastOnlineCache {
  LastOnlineCache._();

  static const _prefix = 'last_online_';

  static String _key(String userID) => '$_prefix$userID';

  static Future<bool>? put(String userID, int ms) =>
      SpUtil().putInt(_key(userID), ms);

  static int? get(String userID) {
    final key = _key(userID);
    final prefs = SpUtil().prefs;
    if (prefs == null || !prefs.containsKey(key)) return null;
    final ms = prefs.getInt(key);
    if (ms == null || ms <= 0) return null;
    return ms;
  }

  static void markOfflineNow(String userID) {
    put(userID, DateTime.now().millisecondsSinceEpoch);
  }

  static String? format(String userID) {
    final ms = get(userID);
    if (ms == null) return null;
    return IMUtils.getChatTimeline(ms);
  }
}
