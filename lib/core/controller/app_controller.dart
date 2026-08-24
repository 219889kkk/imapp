import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as im;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:vibration/vibration.dart';

import '../../utils/upgrade_manager.dart';
import 'im_controller.dart';

class AppController extends GetxController
    with WidgetsBindingObserver, UpgradeManger {
  var isRunningBackground = false;
  final themeRevision = 0.obs;

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  DateTime? _lastImNudgeAt;
  Timer? _backgroundDebounce;
  Timer? _imKeepAlivePing;

  final initializationSettingsAndroid =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  static const String _callCategoryId = 'incoming_call';
  static const String _callActionAccept = 'call_accept';
  static const String _callActionReject = 'call_reject';

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    notificationCategories: [
      DarwinNotificationCategory(
        _callCategoryId,
        actions: [
          DarwinNotificationAction.plain(
            _callActionAccept,
            '接听',
            options: {
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            _callActionReject,
            '拒绝',
            options: {
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
        options: {
          DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
        },
      ),
    ],
  );

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get shouldMuted =>
      rtcBridge?.hasConnection == true ||
      Get.find<IMController>().imSdkStatusSubject.values.last.status !=
          IMSdkStatus.syncEnded;

  final _ring = 'assets/audio/notification_ring.wav';
  final _audioPlayer = AudioPlayer();
  final configuration = const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.ambient,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.sonification,
      usage: AndroidAudioUsage.notification,
    ),
  );
  late AudioSession session;

  late BaseDeviceInfo deviceInfo;

  final clientConfigMap = <String, dynamic>{}.obs;

  Future<void> runningBackground(bool run) async {
    _backgroundDebounce?.cancel();
    if (!run) {
      isRunningBackground = false;
      _imKeepAlivePing?.cancel();
      _imKeepAlivePing = null;
      if (Get.isRegistered<IMController>()) {
        Get.find<IMController>().backgroundSubject.add(false);
      }
      _nudgeImConnection();
      // Keep the IM FGS while logged in — stopping it on resume let Doze
      // freeze the socket after the next lock.
      return;
    }
    // Debounce: permission dialogs briefly fire onForegroundLost — ignore blips.
    _backgroundDebounce = Timer(const Duration(milliseconds: 450), () {
      isRunningBackground = true;
      if (Get.isRegistered<IMController>()) {
        Get.find<IMController>().backgroundSubject.add(true);
      }
      unawaited(CallAudioKeepAlive.startImBackgroundKeepAlive());
      _startImKeepAlivePing();
    });
  }

  /// Ping IM while locked so the websocket is not silently dropped.
  void _startImKeepAlivePing() {
    _imKeepAlivePing?.cancel();
    if (!Platform.isAndroid || !SessionGuard.shouldNotify) return;
    _imKeepAlivePing = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isRunningBackground) return;
      unawaited(_nudgeImConnection());
    });
  }

  static const _voipChannel = MethodChannel('top.hangxun.app/voip');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // FocusDetector alone misses some OEM background transitions; mirror lifecycle.
    if (state == AppLifecycleState.resumed) {
      runningBackground(false);
      // After "Allow Notifications", push SDKs may stamp a stale badge — wipe if logged out.
      if (!_hasLoginSession) {
        clearBadgeForLoggedOut();
      } else if (Platform.isAndroid) {
        unawaited(VoipCallkitController.toOrNull?.onReturnedFromSettings());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // inactive can also mean a permission dialog; only treat paused/hidden as bg.
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        runningBackground(true);
      }
    }
  }

  @override
  void onInit() async {
    WidgetsBinding.instance.addObserver(this);
    _voipChannel.setMethodCallHandler((call) async {
      if (call.method == 'keepAliveTick') {
        unawaited(_nudgeImConnection());
        return true;
      }
      if (call.method == 'nativeIncomingCall') {
        final raw = call.arguments;
        if (raw is Map) {
          unawaited(
            VoipCallkitController.toOrNull?.onNativeIncoming(
                  Map<String, dynamic>.from(raw),
                ) ??
                Future.value(),
          );
        }
        return true;
      }
      return null;
    });
    _syncStylesTheme();
    _initPlayer();

    // Overlay IPA keeps DataSp tokens + UserDefaults. iOS: disarm native
    // badge until IM login succeeds — otherwise 未登录桌面图标会显示未读数.
    // Android: do not stop the IM keep-alive FGS here. Engine restart after
    // a long lock still has tokens; killing FGS then re-init used to crash.
    final hasSession = (DataSp.userID?.trim().isNotEmpty ?? false) &&
        (DataSp.imToken?.trim().isNotEmpty ?? false);
    if (Platform.isIOS || !hasSession) {
      SessionGuard.markLoggedOut();
      unawaited(syncNativeLoginHint(false));
      clearBadgeForLoggedOut();
    } else {
      unawaited(syncNativeLoginHint(true));
    }

    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    await _ensureAndroidNotificationChannels();
    try {
      final launch = await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _onNotificationResponse(launch!.notificationResponse ??
            const NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
            ));
      }
    } catch (e, s) {
      Logger.print('notification launch details failed: $e $s');
    }
    _listenConnectivity();
    PackageBridge.clearCallNotification = cancelCallNotification;

    // Request permission AFTER badge wipe; Allow Notifications can restore a stale number.
    await _requestNotificationPermissions();
    if (!_imLoggedIn) {
      clearBadgeForLoggedOut();
    }

    autoCheckVersionUpgrade();
    super.onInit();
  }

  bool get _hasLoginSession {
    final id = DataSp.userID?.trim() ?? '';
    final token = DataSp.imToken?.trim() ?? '';
    return id.isNotEmpty &&
        token.isNotEmpty &&
        !SessionGuard.suppressNotifications;
  }

  /// Lets native know the user is logged in so Android can keep the IM socket
  /// (and iOS can decide whether a SpringBoard badge wipe is safe).
  Future<void> syncNativeLoginHint(bool active) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _voipChannel.invokeMethod('setLoginSessionHint', {
        'active': active,
        'userID': DataSp.userID ?? '',
      });
    } catch (e, s) {
      Logger.print('syncNativeLoginHint failed: $e $s');
    }
    if (Platform.isAndroid) {
      if (active) {
        unawaited(CallAudioKeepAlive.startImBackgroundKeepAlive());
      } else {
        unawaited(CallAudioKeepAlive.stopImBackgroundKeepAlive());
      }
    }
  }

  /// Create channels up-front so Android 8+ actually delivers banners/sound.
  Future<void> _ensureAndroidNotificationChannels() async {
    if (!Platform.isAndroid) return;
    try {
      final android = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'chat_v2',
          'Chat Messages',
          description: '航讯消息通知',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('notification_ring'),
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'chat_silent',
          'Chat Messages (Silent)',
          description: '航讯消息通知（静音）',
          importance: Importance.high,
          playSound: false,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'call_v2',
          'Incoming Calls',
          description: '航讯语音/视频来电',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('notification_ring'),
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'call_silent_v2',
          'Incoming Calls (Silent)',
          description: '航讯语音/视频来电（静音）',
          importance: Importance.max,
          playSound: false,
        ),
      );
    } catch (e, s) {
      Logger.print('create notification channels error: $e $s');
    }
  }

  void _listenConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _nudgeImConnection();
        // Callee was offline when caller hung up — reconcile CallKit/timer zombies.
        if (Get.isRegistered<IMController>()) {
          unawaited(Get.find<IMController>().recoverPendingRtcInvitations());
        }
      }
    });
  }

  /// When process is alive but socket dropped: ping or soft re-login.
  Future<void> _nudgeImConnection() async {
    final now = DateTime.now();
    if (_lastImNudgeAt != null &&
        now.difference(_lastImNudgeAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastImNudgeAt = now;

    if (!Get.isRegistered<IMController>()) return;
    if (!OpenIM.iMManager.isLogined) return;
    if (OpenIMLiveClient().isBusy) {
      Logger.print('IM nudge skipped: active call');
      return;
    }

    final imLogic = Get.find<IMController>();
    final status =
        imLogic.imSdkStatusSubject.values.lastOrNull?.status;

    try {
      if (status == IMSdkStatus.connectionFailed ||
          status == IMSdkStatus.syncFailed) {
        await ServerEndpointSelector.ensureBestEndpoint(force: true);
        HttpUtil.updateBaseUrl();
        final cert = DataSp.getLoginCertificate();
        if (cert == null || cert.userID.isEmpty || cert.imToken.isEmpty) {
          return;
        }
        Logger.print('IM nudge: soft re-login after disconnect');
        await imLogic.login(cert.userID, cert.imToken);
        return;
      }

      // Healthy or connecting: light ping to wake the socket path.
      await OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount();
    } catch (e, s) {
      Logger.print('IM nudge failed: $e $s');
      if (OpenIMLiveClient().isBusy) {
        Logger.print('IM nudge retry skipped: active call');
        return;
      }
      try {
        final cert = DataSp.getLoginCertificate();
        if (cert == null || cert.userID.isEmpty || cert.imToken.isEmpty) {
          return;
        }
        Logger.print('IM nudge: retry login after ping failure');
        await imLogic.login(cert.userID, cert.imToken);
      } catch (e2, s2) {
        Logger.print('IM nudge retry login failed: $e2 $s2');
      }
    }
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e, s) {
      Logger.print('request notification permissions error: $e $s');
    }
  }

  Future<void> showNotification(im.Message message,
      {bool showNotification = true}) async {
    if (!SessionGuard.shouldNotify) return;
    if (_isGlobalNotDisturb() ||
        message.attachedInfoElem?.notSenderNotificationPush == true ||
        message.contentType == im.MessageType.typing ||
        message.sendID == OpenIM.iMManager.userID ||
        message.isCallingSignalingType ||
        (message.contentType! >= 1000 && message.contentType != 1400)) return;

    var sourceID = message.sessionType == ConversationType.single
        ? message.sendID
        : message.groupID;
    if (sourceID != null && message.sessionType != null) {
      var i = await OpenIM.iMManager.conversationManager.getOneConversation(
        sourceID: sourceID,
        sessionType: message.sessionType!,
      );
      if (i.recvMsgOpt != 0) return;
    }

    if (showNotification) {
      promptSoundOrNotification(message);
    }
  }

  /// Conversation currently open in chat UI; skip banner for that session.
  String? viewingConversationID;

  Future<void> promptSoundOrNotification(im.Message message) async {
    if (!SessionGuard.shouldNotify) return;
    final status =
        Get.find<IMController>().imSdkStatusSubject.values.lastOrNull?.status;
    // Only suppress during active sync — previously required syncEnded and
    // silently dropped ALL foreground alerts after reconnect/connectionSucceeded.
    final syncing = status == IMSdkStatus.syncStart ||
        status == IMSdkStatus.syncProgress;
    if (!isRunningBackground && syncing) {
      return;
    }
    if (!isRunningBackground) {
      _playMessageSound();
    }
    // System banner when backgrounded, or when not viewing this chat.
    final inThisChat = viewingConversationID != null &&
        _messageMatchesViewingChat(message, viewingConversationID!);
    if (isRunningBackground || !inThisChat) {
      await _showMessageNotification(message);
    }
  }

  bool _messageMatchesViewingChat(im.Message message, String conversationID) {
    if (message.sessionType == ConversationType.single) {
      return conversationID.contains(message.sendID ?? '') ||
          conversationID.contains(message.recvID ?? '');
    }
    if (message.groupID != null && message.groupID!.isNotEmpty) {
      return conversationID.contains(message.groupID!);
    }
    return false;
  }

  Future<void> showFriendApplicationNotification({
    required String nickname,
  }) async {
    if (!SessionGuard.shouldNotify) return;
    if (_isGlobalNotDisturb()) return;
    if (!DataSp.getEnableMsgNotification()) return;

    final title = '航讯';
    final body = DataSp.getShowNotificationDetail() && nickname.isNotEmpty
        ? '$nickname ${StrRes.newFriend}'
        : StrRes.newFriend;

    if (!isRunningBackground) {
      _playMessageSound();
    }
    await _showLocalNotification(
      id: _fallbackNotificationID,
      title: title,
      body: body,
    );
  }

  bool get _isAllowBeep {
    if (Get.isRegistered<IMController>()) {
      return Get.find<IMController>().userInfo.value.allowBeep == 1;
    }
    return true;
  }

  Future<void> _showMessageNotification(im.Message message) async {
    if (!DataSp.getEnableMsgNotification()) return;

    String title = '航讯';
    String body = StrRes.newMessageHint;
    if (DataSp.getShowNotificationDetail()) {
      final senderNickname = message.senderNickname ?? '';
      final summary = IMUtils.parseMsg(message, isConversation: true);
      if (message.sessionType != ConversationType.single &&
          message.groupID != null) {
        final groupName = await _getGroupName(message.groupID!);
        title = groupName ?? senderNickname;
        body = senderNickname.isEmpty ? summary : '$senderNickname: $summary';
      } else {
        title = senderNickname.isEmpty ? title : senderNickname;
        body = summary;
      }
    }

    await _showLocalNotification(
      id: message.seq ?? _fallbackNotificationID,
      title: title,
      body: body,
      payload: _msgNotifyPayload(message),
    );
  }

  String? _msgNotifyPayload(im.Message message) {
    final sessionType = message.sessionType ?? ConversationType.single;
    final sourceID = sessionType == ConversationType.single
        ? (message.sendID ?? '')
        : (message.groupID ?? '');
    if (sourceID.isEmpty) return null;
    return 'msg|$sessionType|$sourceID';
  }

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload ?? '';
    final isCall = response.id == _callNotificationId ||
        payload == 'callingInvite' ||
        payload.startsWith('callingInvite');
    if (isCall) {
      if (actionId == _callActionAccept) {
        PackageBridge.handleCallNotificationAction?.call(true);
      } else if (actionId == _callActionReject) {
        PackageBridge.handleCallNotificationAction?.call(false);
      }
      return;
    }
    if (payload.startsWith('msg|')) {
      final parts = payload.split('|');
      if (parts.length >= 3) {
        final sessionType = int.tryParse(parts[1]) ?? ConversationType.single;
        final sourceID = parts.sublist(2).join('|');
        PackageBridge.dispatchChatNotify(sessionType, sourceID);
      }
    }
  }

  Future<void> showCallNotification(SignalingInfo info) async {
    if (!SessionGuard.shouldNotify) return;
    // iOS CallKit owns the system incoming-call UI; skip local banners.
    if (Platform.isIOS) return;
    if (PackageBridge.rtcBridge?.hasCallOverlay == true) return;
    if (PackageBridge.isCallRoomEnded?.call(info.invitation?.roomID) == true) {
      return;
    }
    if (!DataSp.getEnableCallNotification()) return;

    final invitation = info.invitation;
    final isVideo = invitation?.mediaType == 'video';
    final hint = isVideo
        ? StrRes.videoCallInviteHint
        : StrRes.voiceCallInviteHint;
    final callTitle = isVideo
        ? StrRes.videoCallNotificationTitle
        : StrRes.voiceCallNotificationTitle;

    String nickname = invitation?.inviterUserID ?? '';
    try {
      if (invitation?.inviterUserID != null) {
        final list = await OpenIM.iMManager.userManager.getUsersInfo(
          userIDList: [invitation!.inviterUserID!],
        );
        nickname = list.firstOrNull?.simpleUserInfo.nickname ?? nickname;
      }
    } catch (e, s) {
      Logger.print('query inviter info error: $e $s');
    }

    // Always distinguish from chat: title = call type, body = who + invite.
    final title = callTitle;
    final body = nickname.isEmpty
        ? StrRes.offlineCallMessage
        : (DataSp.getShowNotificationDetail()
            ? '$nickname$hint'
            : StrRes.offlineCallMessage);

    if (!isRunningBackground) {
      _playMessageSound();
    }

    final beepOn = _isAllowBeep;
    final androidDetails = AndroidNotificationDetails(
      beepOn ? 'call_v2' : 'call_silent_v2',
      beepOn ? 'Incoming Calls' : 'Incoming Calls (Silent)',
      channelDescription: '航讯语音/视频来电',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      playSound: beepOn,
      sound: beepOn
          ? const RawResourceAndroidNotificationSound('notification_ring')
          : null,
      ongoing: true,
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          _callActionAccept,
          StrRes.pickUp,
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _callActionReject,
          StrRes.reject,
          cancelNotification: true,
        ),
      ],
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: beepOn,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: _callCategoryId,
    );
    // Fixed id so we can cancel when call ends / is cancelled.
    await flutterLocalNotificationsPlugin.show(
      _callNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: isVideo ? 'callingInvite:video' : 'callingInvite:audio',
    );
  }

  /// Stable id for the active incoming-call banner.
  static const int _callNotificationId = 900001;

  Future<void> cancelCallNotification() async {
    try {
      await flutterLocalNotificationsPlugin.cancel(_callNotificationId);
    } catch (e, s) {
      Logger.print('cancelCallNotification error: $e $s');
    }
  }

  int get _fallbackNotificationID =>
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  Future<String?> _getGroupName(String groupID) async {
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupsInfo(
        groupIDList: [groupID],
      );
      final name = list.firstOrNull?.groupName;
      return (name == null || name.isEmpty) ? null : name;
    } catch (e, s) {
      Logger.print('query group info error: $e $s');
      return null;
    }
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final beepOn = _isAllowBeep;

    final androidDetails = AndroidNotificationDetails(
      beepOn ? 'chat_v2' : 'chat_silent',
      beepOn ? 'Chat Messages' : 'Chat Messages (Silent)',
      channelDescription: '航讯消息通知',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: body,
      playSound: beepOn,
      enableVibration: beepOn,
      autoCancel: true,
      channelShowBadge: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '航讯',
      ),
      sound: beepOn
          ? const RawResourceAndroidNotificationSound('notification_ring')
          : null,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: beepOn,
      sound: beepOn ? 'notification_ring.wav' : null,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload ?? '',
    );
  }

  Future<void> _cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  /// Stop sounds, banners, and badge as soon as logout begins.
  Future<void> onSessionLogout() async {
    await syncNativeLoginHint(false);
    await _stopMessageSound();
    await _cancelAllNotifications();
    clearBadgeForLoggedOut();
    unawaited(CallAudioKeepAlive.stopImBackgroundKeepAlive());
    _imKeepAlivePing?.cancel();
    _imKeepAlivePing = null;
  }

  bool get _imLoggedIn {
    try {
      return OpenIM.iMManager.isLogined;
    } catch (_) {
      return false;
    }
  }

  void showBadge(count) {
    // Never paint unread on the icon while logged out / on login page.
    if (!_hasLoginSession || !_imLoggedIn) {
      clearBadgeForLoggedOut();
      return;
    }
    final n = count is int ? count : int.tryParse('$count') ?? 0;
    if (n <= 0) {
      removeBadge();
      return;
    }
    unawaited(
      OpenIM.iMManager.messageManager.setAppBadge(n).catchError((_) {}),
    );
    AppBadgePlus.isSupported().then((value) {
      if (value) {
        AppBadgePlus.updateBadge(n);
      }
    }).catchError((_) {});
  }

  void removeBadge() {
    unawaited(_clearLocalIconBadge());
    // OpenIM SetAppBadge crashes / asserts when not logged in — never call then.
    if (_imLoggedIn) {
      unawaited(
        OpenIM.iMManager.messageManager.setAppBadge(0).catchError((_) {}),
      );
    }
  }

  Future<void> _clearLocalIconBadge() async {
    try {
      if (Platform.isIOS) {
        await _voipChannel.invokeMethod('clearIconBadge');
      }
    } catch (e, s) {
      Logger.print('clearIconBadge native failed: $e $s');
    }
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (e, s) {
      Logger.print('AppBadgePlus updateBadge(0) failed: $e $s');
    }
  }

  /// Force-clear desktop badge + local call/chat banners (logout / no session).
  void clearBadgeForLoggedOut() {
    // Prefer zeroing OpenIM server badge while still logged in when possible.
    try {
      if (OpenIM.iMManager.isLogined) {
        unawaited(
          OpenIM.iMManager.messageManager.setAppBadge(0).catchError((_) {}),
        );
      }
    } catch (_) {}
    unawaited(_clearLocalIconBadge());
    // Repeat — notification permission / Getui can restore SpringBoard badge.
    Future<void>.delayed(const Duration(milliseconds: 400), _clearLocalIconBadge);
    Future<void>.delayed(const Duration(seconds: 2), _clearLocalIconBadge);
    unawaited(_cancelAllNotifications());
  }

  @override
  void onClose() {
    if (identical(PackageBridge.clearCallNotification, cancelCallNotification)) {
      PackageBridge.clearCallNotification = null;
    }
    _connectivitySub?.cancel();
    _backgroundDebounce?.cancel();
    _imKeepAlivePing?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    closeSubject();
    _audioPlayer.dispose();
    super.onClose();
  }

  @override
  void didChangePlatformBrightness() {
    if (DataSp.getThemeMode() == 0) {
      _syncStylesTheme();
      Config.updateSystemUiOverlayStyle();
      themeRevision.value++;
      update();
    }
  }

  Locale? getLocale() {
    var local = Get.locale;
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        local = const Locale('zh', 'CN');
        break;
      case 2:
        local = const Locale('en', 'US');
        break;
    }
    return local;
  }

  ThemeMode getThemeMode() {
    final index = DataSp.getThemeMode();
    final mode = switch (index) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _syncStylesTheme(mode);
    return mode;
  }

  int getThemeModeIndex() => DataSp.getThemeMode();

  Future<void> switchThemeMode(int index) async {
    await DataSp.putThemeMode(index);
    _syncStylesTheme(getThemeMode());
    Config.updateSystemUiOverlayStyle();
    themeRevision.value++;
    update();
  }

  Color getThemeColor() => Color(DataSp.getThemeColor());

  Future<void> switchThemeColor(Color color) async {
    await DataSp.putThemeColor(color.toARGB32());
    Styles.updateAccentColor(color);
    Config.updateSystemUiOverlayStyle();
    themeRevision.value++;
    update();
  }

  void _syncStylesTheme([ThemeMode? mode]) {
    Styles.updateAccentColor(Color(DataSp.getThemeColor()));
    Styles.updateThemeMode(
      mode ?? getThemeMode(),
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    IMViews.syncEasyLoadingTheme();
  }

  @override
  void onReady() {
    queryClientConfig();
    _getDeviceInfo();
    _cancelAllNotifications();
    super.onReady();
  }

  bool _isGlobalNotDisturb() {
    bool isRegistered = Get.isRegistered<IMController>();
    if (isRegistered) {
      var logic = Get.find<IMController>();
      return logic.userInfo.value.globalRecvMsgOpt == 2;
    }
    return false;
  }

  void _initPlayer() async {
    session = await AudioSession.instance;
    await session.configure(configuration);

    _audioPlayer.setAsset(_ring, package: 'openim_common');
    _audioPlayer.playerStateStream.listen((state) {
      switch (state.processingState) {
        case ProcessingState.idle:
        case ProcessingState.loading:
        case ProcessingState.buffering:
        case ProcessingState.ready:
          break;
        case ProcessingState.completed:
          _stopMessageSound();

          break;
      }
    });
  }

  void _playMessageSound() async {
    if (shouldMuted) {
      return;
    }
    bool isRegistered = Get.isRegistered<IMController>();
    bool isAllowVibration = true;
    bool isAllowBeep = true;
    if (isRegistered) {
      var logic = Get.find<IMController>();
      isAllowVibration = logic.userInfo.value.allowVibration == 1;
      isAllowBeep = logic.userInfo.value.allowBeep == 1;
    }

    RingerModeStatus ringerStatus = await SoundMode.ringerModeStatus;

    Logger.print(
        'System ringer status: $ringerStatus, user is allow beep: $isAllowBeep',
        fileName: 'app_controller.dart');

    if (!_audioPlayer.playerState.playing &&
        isAllowBeep &&
        (ringerStatus == RingerModeStatus.normal ||
            ringerStatus == RingerModeStatus.unknown)) {
      await session.setActive(true);
      _audioPlayer.setAsset(_ring, package: 'openim_common');
      _audioPlayer.setLoopMode(LoopMode.off);
      _audioPlayer.setVolume(1.0);
      _audioPlayer.play();
    }

    if (isAllowVibration &&
        (ringerStatus == RingerModeStatus.normal ||
            ringerStatus == RingerModeStatus.vibrate ||
            ringerStatus == RingerModeStatus.unknown)) {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate();
      }
    }
  }

  Future<void> _stopMessageSound() async {
    if (_audioPlayer.playerState.playing) {
      await _audioPlayer.stop();
    }
    await session.setActive(false);
  }

  void _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    deviceInfo = await deviceInfoPlugin.deviceInfo;
  }

  Future queryClientConfig() async {
    final map = await Apis.getClientConfig();
    clientConfigMap.assignAll(map);

    return clientConfigMap;
  }
}
