import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:getuiflut/getuiflut.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:openim_common/openim_common.dart';

import 'firebase_options.dart';

enum PushType { getui, FCM, apns, none }

/// Getui credentials (Android package: io.openim.flutter.demo).
/// iOS lock-screen banners use direct APNs (see [PushType.apns]), not Getui.
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

/// Redis TTL for the iOS APNs device token stored via [OpenIM.iMManager.updateFcmToken].
const _apnsTokenExpireSeconds = 90 * 24 * 3600;

class PushController extends GetxService {
  PushType pushType = PushType.none;

  String? _boundAlias;
  String? _pendingAlias;
  bool _getuiInited = false;
  bool _handlersAttached = false;
  Completer<void>? _unbindCompleter;

  @override
  void onInit() {
    super.onInit();
    if (Platform.isIOS) {
      // Alert (text) push is direct APNs. Starting Getui on iOS would
      // double-notify and stamp login-screen badges via CID.
      pushType = PushType.apns;
    } else {
      // Android vendor push is not available. Incoming after lock depends
      // on the IM websocket + ImKeepAliveService.
      pushType = PushType.none;
      Logger.print('PushController: Android pushType=none (no vendor push)');
    }
  }

  /// Logs in the user with the specified alias to the push notification service.
  ///
  /// Getui (Android): binds [alias] (OpenIM userID) so the server can push by alias.
  /// APNs (iOS): registers for remote notifications and uploads the device token.
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
      case PushType.apns:
        ApnsPushController()._login(alias);
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
      case PushType.apns:
        await ApnsPushController()._logoutAsync();
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
          onReceiveClientId: (res) async {
            await _log('clientId', res);
            _bindPendingAlias();
          },
          onReceiveOnlineState: (res) => _log('online', res),
          onRegisterDeviceToken: (res) => _log('deviceToken', res),
          onReceivePayload: (msg) async {
            await _log('payload', msg);
            _dispatchGetuiCall(msg);
          },
          onReceiveNotificationResponse: (msg) async {
            await _log('notificationResponse', msg);
            _dispatchGetuiCall(msg);
          },
          onTransmitUserMessageReceive: (msg) async {
            await _log('userMessage', msg);
            _dispatchGetuiCall(msg);
          },
          onNotificationMessageArrived: (msg) async {
            await _log('notificationArrived', msg);
            if (!SessionGuard.shouldNotify) {
              Logger.print(
                  'Getui notification arrived while logged out — ignore (badge wipe is native)');
              return;
            }
            _dispatchGetuiCall(msg);
          },
          onNotificationMessageClicked: (msg) async {
            await _log('notificationClicked', msg);
            _dispatchGetuiCall(msg);
          },
          onAppLinkPayload: (res) => _log('appLink', res),
          onPushModeResult: (msg) => _log('pushMode', msg),
          onSetTagResult: (msg) => _log('setTag', msg),
          onAliasResult: (msg) async {
            await _log('alias', msg);
            _unbindCompleter?.complete();
          },
          onQueryTagResult: (msg) => _log('queryTag', msg),
          onWillPresentNotification: (msg) async {
            await _log('willPresent', msg);
            if (!SessionGuard.shouldNotify) {
              Logger.print('Getui willPresent ignored — not logged in');
            }
          },
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
        // iOS text push is direct APNs. Never start Getui here.
        Logger.print('Getui SDK skipped on iOS (APNs alert path)');
      }
    } catch (e, s) {
      Logger.print('Getui SDK start failed: $e $s');
      _getuiInited = false;
    }
  }

  void _dispatchGetuiCall(dynamic msg) {
    if (!Platform.isAndroid) return;
    if (!SessionGuard.shouldNotify) return;
    final parsed = _parseGetuiCall(msg);
    if (parsed == null) return;
    final info = parsed.$1;
    final action = parsed.$2;
    Logger.print(
        'Getui call dispatch action=$action room=${info.invitation?.roomID}');
    PackageBridge.dispatchPushCallEvent(info, action);
  }

  /// Returns (signaling, action) for invite/cancel/hungup Getui payloads.
  (SignalingInfo, String)? _parseGetuiCall(dynamic msg) {
    final map = _asStringKeyMap(msg);
    if (map == null) return null;
    var payload = Map<String, dynamic>.from(map);
    for (final key in [
      'payload',
      'transmission',
      'offlineMsg',
      'message',
      'payloadMsg',
    ]) {
      final nested = _asStringKeyMap(payload[key]) ?? _decodeJsonMap(payload[key]);
      if (nested != null) {
        payload = {...payload, ...nested};
      }
    }
    final inner = _asStringKeyMap(payload['data']) ??
        _asStringKeyMap(payload['ex']) ??
        _decodeJsonMap(payload['ex']);
    if (inner != null) {
      payload = {...payload, ...inner};
    }

    final customType = payload['customType'];
    final customTypeInt = customType is num
        ? customType.toInt()
        : int.tryParse('$customType');
    final type = '${payload['type'] ?? ''}';
    var action = '${payload['action'] ?? ''}'.trim().toLowerCase();
    final roomID = '${payload['roomID'] ?? payload['callUUID'] ?? ''}'.trim();
    if (roomID.isEmpty) return null;

    final isCallType = customTypeInt == 200 ||
        customTypeInt == 201 ||
        customTypeInt == 202 ||
        customTypeInt == 203 ||
        customTypeInt == 204 ||
        type == 'callingInvite';
    if (!isCallType && action.isEmpty) return null;

    if (action.isEmpty) {
      if (customTypeInt == 201) {
        action = 'accept';
      } else if (customTypeInt == 202) {
        action = 'reject';
      } else if (customTypeInt == 203) {
        action = 'cancel';
      } else if (customTypeInt == 204) {
        action = 'hungup';
      } else {
        action = 'invite';
      }
    }

    List<String>? invitees;
    final rawInvitees = payload['inviteeUserIDList'];
    if (rawInvitees is List) {
      invitees = rawInvitees.map((e) => e.toString()).toList();
    }

    final nickname =
        '${payload['inviterNickname'] ?? payload['nickname'] ?? payload['title'] ?? ''}'
            .trim();
    final info = SignalingInfo(
      userID: '${payload['inviterUserID'] ?? ''}',
      invitation: InvitationInfo(
        roomID: roomID,
        inviterUserID: '${payload['inviterUserID'] ?? ''}',
        inviteeUserIDList: invitees,
        mediaType: '${payload['mediaType'] ?? 'audio'}',
        sessionType: int.tryParse('${payload['sessionType'] ?? 1}') ?? 1,
        groupID: payload['groupID']?.toString(),
        timeout: int.tryParse('${payload['timeout'] ?? 60}') ?? 60,
      ),
      offlinePushInfo: nickname.isEmpty
          ? null
          : OfflinePushInfo(title: nickname),
    );
    return (info, action);
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return _decodeJsonMap(v);
  }

  Map<String, dynamic>? _decodeJsonMap(dynamic v) {
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty || !s.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        return decoded.map((k, val) => MapEntry(k.toString(), val));
      }
    } catch (_) {}
    return null;
  }

  void _bindPendingAlias() {
    // Alias bind is not a login-screen start. SDK is only running after IM login.
    final alias = _pendingAlias?.trim() ?? '';
    if (alias.isEmpty || !_getuiInited) return;
    try {
      final sn = 'alias_${DateTime.now().millisecondsSinceEpoch}';
      Getuiflut().bindAlias(alias, sn);
      _boundAlias = alias;
      Logger.print('Getui bindAlias: $alias sn=$sn');
    } catch (e, s) {
      Logger.print('Getui bindAlias failed: $e $s');
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
    push?._pendingAlias = alias;
    push?._bindPendingAlias();
  }

  void _logout() {
    unawaited(_logoutAsync());
  }

  Future<void> _logoutAsync() async {
    final push = Get.isRegistered<PushController>()
        ? Get.find<PushController>()
        : null;
    final alias = push?._boundAlias;
    push?._pendingAlias = null;
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

class ApnsPushController {
  static final ApnsPushController _instance = ApnsPushController._internal();
  factory ApnsPushController() => _instance;
  ApnsPushController._internal();

  static const _channel = MethodChannel('top.hangxun.app/apns');

  String? _boundUserID;
  String? _token;
  String? _lastUploaded;
  bool _uploading = false;
  bool _handlerAttached = false;
  Timer? _retryTimer;
  int _retryCount = 0;

  void _login(String userID) {
    _boundUserID = userID;
    _lastUploaded = null;
    _attachHandler();
    unawaited(_start());
  }

  Future<void> _logoutAsync() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _boundUserID = null;
    _lastUploaded = null;
    try {
      await OpenIM.iMManager.updateFcmToken(
        fcmToken: '',
        expireTime: 1,
      );
      Logger.print('APNs token cleared on logout');
    } catch (e, s) {
      Logger.print('APNs token clear failed: $e $s');
    }
  }

  void _attachHandler() {
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onApnsToken') {
        final token = '${call.arguments ?? ''}'.trim();
        if (token.isEmpty) return;
        _token = token;
        Logger.print('APNs token from native len=${token.length}');
        await _uploadIfNeeded();
      }
    });
  }

  Future<void> _start() async {
    try {
      await Permissions.notification();
    } catch (e, s) {
      Logger.print('APNs notification permission: $e $s');
    }
    try {
      await _channel.invokeMethod('registerForRemoteNotifications');
    } catch (e, s) {
      Logger.print('registerForRemoteNotifications failed: $e $s');
    }
    await _refreshCachedToken(upload: true);
    _scheduleRetries();
  }

  void _scheduleRetries() {
    _retryTimer?.cancel();
    _retryCount = 0;
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _retryCount++;
      await _refreshCachedToken(upload: true);
      if (_isPlausible(_token) && _lastUploaded == _token) {
        timer.cancel();
        return;
      }
      if (_retryCount >= 30) {
        Logger.print(
            'APNs token upload gave up after retries; last=$_token uploaded=$_lastUploaded');
        timer.cancel();
      }
    });
  }

  Future<void> _refreshCachedToken({required bool upload}) async {
    try {
      final cached =
          await _channel.invokeMethod<String>('getCachedApnsToken');
      final raw = (cached ?? '').trim();
      if (raw.isNotEmpty) {
        _token = raw;
        if (upload) await _uploadIfNeeded();
      }
    } catch (e, s) {
      Logger.print('getCachedApnsToken failed: $e $s');
    }
  }

  Future<void> _uploadIfNeeded() async {
    final userID = _boundUserID;
    final token = _token;
    if (userID == null || userID.isEmpty) return;
    if (!_isPlausible(token)) return;
    if (token == _lastUploaded) return;
    if (_uploading) return;
    _uploading = true;
    final prefix = token!.length <= 8 ? token : token.substring(0, 8);
    Logger.print(
        'APNs token upload start userID=$userID len=${token.length} prefix=$prefix');
    try {
      await OpenIM.iMManager.updateFcmToken(
        fcmToken: token,
        expireTime: _apnsTokenExpireSeconds,
      );
      _lastUploaded = token;
      Logger.print('APNs token upload success userID=$userID');
    } catch (e, s) {
      Logger.print('APNs token upload error (will retry): $e $s');
    } finally {
      _uploading = false;
    }
  }

  bool _isPlausible(String? token) {
    final t = token?.trim() ?? '';
    if (t.length < 32 || t.length > 200 || t.length.isOdd) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(t);
  }
}

