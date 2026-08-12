import 'dart:convert';

class Utils {
  static List<T> toList<T>(String value, T f(Map<String, dynamic> map)) =>
      (formatJson(value) as List).map((e) => f(e)).toList();

  static T toObj<T>(String value, T f(Map<String, dynamic> map)) => f(formatJson(value));

  /// Offline callbacks may be a single object or a JSON array (Android SDK).
  static List<T> toObjOrList<T>(dynamic value, T f(Map<String, dynamic> map)) {
    final decoded = value is String ? formatJson(value) : value;
    if (decoded is List) {
      return decoded.map((e) {
        if (e is Map<String, dynamic>) return f(e);
        if (e is Map) return f(Map<String, dynamic>.from(e));
        throw ArgumentError('expected map in list, got ${e.runtimeType}');
      }).toList();
    }
    if (decoded is Map<String, dynamic>) return [f(decoded)];
    if (decoded is Map) return [f(Map<String, dynamic>.from(decoded))];
    throw ArgumentError('expected map or list, got ${decoded.runtimeType}');
  }

  static List<dynamic> toListMap(String value) => formatJson(value);

  static dynamic formatJson(String value) => jsonDecode(value);

  static String checkOperationID(String? obj) => obj ?? DateTime.now().millisecondsSinceEpoch.toString();

  static Map<String, dynamic> cleanMap(Map<String, dynamic> map) {
    map.removeWhere((key, value) {
      if (value is Map<String, dynamic>) {
        cleanMap(value);
      }
      return value == null;
    });
    return map;
  }
}
