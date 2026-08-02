import 'dart:convert';

class OnlineStatus {
  String? userID;
  /// Normalized: "online" / "offline"
  String? status;
  List<DetailPlatformStatus>? detailPlatformStatus;

  OnlineStatus({this.userID, this.status, this.detailPlatformStatus});

  bool get isOnline => status?.toLowerCase() == 'online';

  OnlineStatus.fromJson(Map<String, dynamic> json) {
    userID = json['userID']?.toString();
    status = _normalizeStatus(json['status']);
    if (json['detailPlatformStatus'] != null) {
      detailPlatformStatus = <DetailPlatformStatus>[];
      json['detailPlatformStatus'].forEach((v) {
        detailPlatformStatus!.add(DetailPlatformStatus.fromJson(
          Map<String, dynamic>.from(v),
        ));
      });
    }
  }

  static String? _normalizeStatus(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      return raw.toInt() == 1 ? 'online' : 'offline';
    }
    final s = raw.toString().toLowerCase();
    if (s == '1' || s == 'online') return 'online';
    if (s == '0' || s == 'offline') return 'offline';
    return s;
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['userID'] = userID;
    data['status'] = status;
    if (detailPlatformStatus != null) {
      data['detailPlatformStatus'] =
          detailPlatformStatus!.map((e) => e.toJson()).toList();
    }
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class DetailPlatformStatus {
  String? platform;
  String? status;
  int? platformID;

  DetailPlatformStatus({this.platform, this.status, this.platformID});

  DetailPlatformStatus.fromJson(Map<String, dynamic> json) {
    platform = json['platform']?.toString();
    platformID = json['platformID'] is num
        ? (json['platformID'] as num).toInt()
        : int.tryParse('${json['platformID'] ?? ''}');
    status = OnlineStatus._normalizeStatus(json['status']);
    platform ??= _platformName(platformID);
  }

  static String? _platformName(int? id) {
    switch (id) {
      case 1:
        return 'iOS';
      case 2:
        return 'Android';
      case 3:
        return 'Windows';
      case 4:
        return 'OSX';
      case 5:
        return 'Web';
      case 6:
        return 'MiniProgram';
      case 7:
        return 'Linux';
      case 8:
        return 'AndroidPad';
      case 9:
        return 'iPad';
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['platform'] = platform;
    data['platformID'] = platformID;
    data['status'] = status;
    return data;
  }
}
