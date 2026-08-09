import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'utils/server_endpoint_selector.dart';

class Config {
  static Future init(Function() runApp) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final path = (await getApplicationDocumentsDirectory()).path;
      cachePath = '$path/';
      await DataSp.init();
      await ServerEndpointSelector.ensureBestEndpoint();
      await Hive.initFlutter(path);
      MediaKit.ensureInitialized();
      HttpUtil.init();
    } catch (_) {}

    runApp();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    updateSystemUiOverlayStyle();

    final packageInfo = await PackageInfo.fromPlatform();
    _appName = packageInfo.appName;
  }

  static late String _appName;

  static late String cachePath;

  static void updateSystemUiOverlayStyle() {
    final iconBrightness = Styles.isDark ? Brightness.light : Brightness.dark;
    final statusBarBrightness = Styles.isDark ? Brightness.dark : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Platform.isIOS ? statusBarBrightness : iconBrightness,
      statusBarIconBrightness: iconBrightness,
    ));
  }
  static const uiW = 375.0;
  static const uiH = 812.0;

  static const double textScaleFactor = 1.0;

  static const discoverPageURL = 'discover';
  static const allowSendMsgNotFriend = '1';
  // amap key
  static const webKey = 'webKey';
  static const webServerKey = 'webServerKey';
  static const locationHost = 'http://location.your-domain';

  static OfflinePushInfo get offlinePushInfo => OfflinePushInfo(
        title: _appName,
        desc: StrRes.offlineMessage,
        iOSBadgeCount: true,
        iOSPushSound: 'default',
      );

  /// Offline APNs/Getui payload for call invites — distinct from chat messages.
  /// [invitation] is encoded into `ex` JSON so the server can build VoIP payload.
  static OfflinePushInfo offlineCallPushInfo({
    required bool isVideo,
    InvitationInfo? invitation,
  }) {
    final title = isVideo
        ? StrRes.videoCallNotificationTitle
        : StrRes.voiceCallNotificationTitle;
    final hint = isVideo
        ? StrRes.videoCallInviteHint
        : StrRes.voiceCallInviteHint;
    String nickname = '';
    try {
      nickname = OpenIM.iMManager.userInfo.nickname?.trim() ?? '';
    } catch (_) {}
    final desc = nickname.isEmpty ? hint : '$nickname$hint';
    final mediaType = invitation?.mediaType ?? (isVideo ? 'video' : 'audio');
    final exMap = <String, dynamic>{
      'type': 'callingInvite',
      'mediaType': mediaType,
      'roomID': invitation?.roomID,
      'inviterUserID':
          invitation?.inviterUserID ?? OpenIM.iMManager.userID,
      'inviteeUserIDList': invitation?.inviteeUserIDList,
      'sessionType': invitation?.sessionType,
      'groupID': invitation?.groupID,
      'timeout': invitation?.timeout ?? 60,
      'nickname': nickname,
    };
    return OfflinePushInfo(
      title: title,
      desc: desc,
      iOSBadgeCount: true,
      iOSPushSound: 'default',
      ex: jsonEncode(exMap),
    );
  }

  static const friendScheme = "io.openim.app/addFriend/";
  static const groupScheme = "io.openim.app/joinGroup/";

  static const _defaultHost = ServerEndpointSelector.primaryHost;

  static const _ipRegex =
      '((2[0-4]\\d|25[0-5]|[01]?\\d\\d?)\\.){3}(2[0-4]\\d|25[0-5]|[01]?\\d\\d?)';

  static String get _activeHost {
    final fromSp = DataSp.getServerConfig()?['serverIP']?.toString().trim();
    if (fromSp != null && fromSp.isNotEmpty) return fromSp;
    return _defaultHost;
  }

  static bool _isIPHost(String host) => RegExp(_ipRegex).hasMatch(host);

  static bool get _isIP => _isIPHost(_activeHost);

  static String get serverIp => _activeHost;

  static String get chatTokenUrl {
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['chatTokenUrl'];
    }
    return url ?? (_isIP ? "http://$_activeHost:10009" : "https://$_activeHost/chat");
  }

  static String get appAuthUrl {
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['authUrl'];
    }
    return url ?? (_isIP ? "http://$_activeHost:10008" : "https://$_activeHost/chat");
  }

  static String get botApiUrl {
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['botApiUrl'];
    }
    return url ?? (_isIP ? "http://$_activeHost:10010" : "https://$_activeHost/bot");
  }

  static String get imApiUrl {
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['apiUrl'];
    }
    return url ?? (_isIP ? 'http://$_activeHost:10002' : "https://$_activeHost/api");
  }

  static String get imWsUrl {
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['wsUrl'];
    }
    return url ?? (_isIP ? "ws://$_activeHost:10001" : "wss://$_activeHost/msg_gateway");
  }

  /// Public WebSocket URL for LiveKit — phones cannot use 127.0.0.1 from API.
  static String get liveKitWsUrl {
    final server = DataSp.getServerConfig();
    final fromConfig = server?['liveKitUrl']?.toString().trim();
    if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
    if (!_isIP) return 'wss://livekit.$_defaultHost';
    return 'wss://livekit.$_defaultHost';
  }

  static int get logLevel {
    String? level;
    var server = DataSp.getServerConfig();
    if (null != server) {
      level = server['logLevel'];
    }
    if (level != null) return int.parse(level);
    // Release: quieter SDK logs (less UI-isolate / native I/O); debug stays verbose.
    return kDebugMode ? 5 : 3;
  }
}
