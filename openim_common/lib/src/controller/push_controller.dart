import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:getuiflut/getuiflut.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:openim_common/openim_common.dart';

import 'firebase_options.dart';

enum PushType { getui, FCM, none }

/// Getui credentials (iOS Bundle ID: top.hangxun.app; Android package: io.openim.flutter.demo).
/// Replace placeholders with values from the Getui console; when filled,
/// [PushController] enables [PushType.getui] on both iOS and Android.
const appID = 'gy41yoFqNV8bdYKPBDYwc7';
const appKey = 'UveVgAb1Id8vAfz7RdCkA6';
const appSecret = 'yIcrJFzeUd6MynyvYNZ251';

bool get _hasGetuiCredentials =>
    appID.isNotEmpty &&
    appKey.isNotEmpty &&
    appSecret.isNotEmpty &&
    appID != 'your-app-id' &&
    appKey != 'your-app-key' &&
    appSecret != 'your-app-secret';

class PushController extends GetxService {
  PushType pushType = PushType.none;

  String? _boundAlias;
  bool _getuiInited = false;
  bool _handlersAttached = false;
  Completer<void>? _unbindCompleter;

  @override
  void onInit() {
    super.onInit();
    if (_hasGetuiCredentials) {
      pushType = PushType.getui;
      _ensureGetuiStarted();
    } else {
      pushType = PushType.none;
      Logger.print(
        'PushController: Getui credentials not set, pushType=none '
        '(offline push disabled until AppID/AppKey/AppSecret are filled)',
      );
    }
  }

  /// Logs in the user with the specified alias to the push notification service.
  ///
  /// Getui: binds [alias] (OpenIM userID) so the server can push by alias.
  /// FCM: refreshes token via [onTokenRefresh].
  static void login(
    String alias, {
    void Function(String token)? onTokenRefresh,
  }) {
    SessionGuard.markLoggedIn();
    final ctrl = Get.isRegistered<PushController>()
        ? Get.find<PushController>()
        : PushController();
    switch (ctrl.pushType) {
      case PushType.getui:
        GetuiPushController()._login(alias);
        break;
      case PushType.FCM:
        assert(onTokenRefresh != null);
        FCMPushController()._initialize().then((_) {
          FCMPushController()._getToken().then((token) => onTokenRefresh!(token));
          FCMPushController()._listenToTokenRefresh(onTokenRefresh!);
        });
        break;
      case PushType.none:
        break;
    }
  }

  static void logout() {
    unawaited(logoutAsync());
  }

  static Future<void> logoutAsync() async {
    final ctrl = Get.isRegistered<PushController>()
        ? Get.find<PushController>()
        : PushController();
    switch (ctrl.pushType) {
      case PushType.getui:
        await GetuiPushController()._logoutAsync();
        break;
      case PushType.FCM:
        await FCMPushController()._deleteToken();
        break;
      case PushType.none:
        break;
    }
  }

  void _ensureGetuiStarted() {
    if (_getuiInited || !_hasGetuiCredentials) return;
    try {
      final gt = Getuiflut();
      if (!_handlersAttached) {
        _handlersAttached = true;
        Future<dynamic> _log(String tag, dynamic data) async {
          Logger.print('Getui $tag: $data');
        }

        gt.addEventHandler(
          onReceiveClientId: (res) => _log('clientId', res),
          onReceiveOnlineState: (res) => _log('online', res),
          onRegisterDeviceToken: (res) => _log('deviceToken', res),
          onReceivePayload: (msg) => _log('payload', msg),
          onReceiveNotificationResponse: (msg) =>
              _log('notificationResponse', msg),
          onTransmitUserMessageReceive: (msg) => _log('userMessage', msg),
          onNotificationMessageArrived: (msg) =>
              _log('notificationArrived', msg),
          onNotificationMessageClicked: (msg) =>
              _log('notificationClicked', msg),
          onAppLinkPayload: (res) => _log('appLink', res),
          onPushModeResult: (msg) => _log('pushMode', msg),
          onSetTagResult: (msg) => _log('setTag', msg),
          onAliasResult: (msg) {
            _log('alias', msg);
            _unbindCompleter?.complete();
          },
          onQueryTagResult: (msg) => _log('queryTag', msg),
          onWillPresentNotification: (msg) => _log('willPresent', msg),
          onOpenSettingsForNotification: (msg) =>
              _log('openSettings', msg),
          onGrantAuthorization: (res) => _log('grantAuth', res),
          onLiveActivityResult: (msg) => _log('liveActivity', msg),
          onRegisterPushToStartTokenResult: (msg) =>
              _log('pushToStartToken', msg),
        );
      }

      if (Platform.isAndroid) {
        // Android reads GETUI_APPID from manifestPlaceholders.
        gt.initGetuiSdk;
        gt.turnOnPush();
        // Android 13+ notification permission (Xiaomi/Redmi etc.).
        // ignore: unawaited_futures
        Permissions.notification();
        _getuiInited = true;
        Logger.print('Getui SDK init requested (Android)');
      } else if (Platform.isIOS) {
        gt.startSdk(appId: appID, appKey: appKey, appSecret: appSecret);
        _getuiInited = true;
        Logger.print('Getui SDK start requested (iOS)');
      }
    } catch (e, s) {
      Logger.print('Getui SDK start failed: $e $s');
      _getuiInited = false;
    }
  }
}

class GetuiPushController {
  static final GetuiPushController _instance = GetuiPushController._internal();
  factory GetuiPushController() => _instance;
  GetuiPushController._internal();

  void _login(String alias) {
    final push = Get.isRegistered<PushController>()
        ? Get.find<PushController>()
        : null;
    push?._ensureGetuiStarted();
    try {
      final sn = 'alias_${DateTime.now().millisecondsSinceEpoch}';
      Getuiflut().bindAlias(alias, sn);
      push?._boundAlias = alias;
      Logger.print('Getui bindAlias: $alias sn=$sn');
    } catch (e, s) {
      Logger.print('Getui bindAlias failed: $e $s');
    }
  }

  void _logout() {
    unawaited(_logoutAsync());
  }

  Future<void> _logoutAsync() async {
    final push = Get.isRegistered<PushController>()
        ? Get.find<PushController>()
        : null;
    final alias = push?._boundAlias;
    if (alias == null || alias.isEmpty) return;
    try {
      final sn = 'unalias_${DateTime.now().millisecondsSinceEpoch}';
      push?._unbindCompleter = Completer<void>();
      Getuiflut().unbindAlias(alias, sn, true);
      push?._boundAlias = null;
      Logger.print('Getui unbindAlias: $alias');
      try {
        await push!._unbindCompleter!.future
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        Logger.print('Getui unbindAlias timeout for $alias');
      } finally {
        push?._unbindCompleter = null;
      }
    } catch (e, s) {
      push?._unbindCompleter = null;
      Logger.print('Getui unbindAlias failed: $e $s');
    }
  }
}

class FCMPushController {
  static final FCMPushController _instance = FCMPushController._internal();
  factory FCMPushController() => _instance;

  FCMPushController._internal();

  Future<void> _initialize() async {
    GooglePlayServicesAvailability? availability =
        GooglePlayServicesAvailability.success;
    if (Platform.isAndroid) {
      availability = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability();
    }
    if (availability != GooglePlayServicesAvailability.serviceInvalid) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } else {
      Logger.print('Google Play Services are not available');
      return;
    }

    await _requestPermission();
    _configureForegroundNotification();
    _configureBackgroundNotification();
  }

  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    Logger.print('FCM permission: ${settings.authorizationStatus}');
  }

  void _configureForegroundNotification() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      Logger.print(
          'Foreground notification: ${message.notification?.title}');
    });
  }

  void _configureBackgroundNotification() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      Logger.print(
          'App opened from background: ${message.notification?.title}');
    });

    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        Logger.print(
            'App opened from terminated: ${message.notification?.title}');
      }
    });
  }

  Future<String> _getToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    Logger.print('FCM Token: $token');
    if (token == null) {
      throw Exception('FCM Token is null');
    }
    return token;
  }

  Future<void> _deleteToken() {
    return FirebaseMessaging.instance.deleteToken();
  }

  void _listenToTokenRefresh(void Function(String token) onTokenRefresh) {
    FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) {
      Logger.print('FCM Token refreshed: $newToken');
      onTokenRefresh(newToken);
    });
  }
}
