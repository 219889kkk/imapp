import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as im;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
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

  final initializationSettingsAndroid =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      const DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
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
    isRunningBackground = run;
    if (Get.isRegistered<IMController>()) {
      Get.find<IMController>().backgroundSubject.add(run);
    }
    if (!run) {
      _cancelAllNotifications();
      // Back to foreground: poke IM if the socket dropped while backgrounded.
      _nudgeImConnection();
    }
  }

  @override
  void onInit() async {
    WidgetsBinding.instance.addObserver(this);
    _syncStylesTheme();
    _initPlayer();
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (notificationResponse) {},
    );
    _requestNotificationPermissions();
    _listenConnectivity();
    PackageBridge.clearCallNotification = cancelCallNotification;

    autoCheckVersionUpgrade();
    super.onInit();
  }

  void _listenConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _nudgeImConnection();
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

    final imLogic = Get.find<IMController>();
    final status =
        imLogic.imSdkStatusSubject.values.lastOrNull?.status;

    try {
      if (status == IMSdkStatus.connectionFailed ||
          status == IMSdkStatus.syncFailed) {
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
    final status =
        Get.find<IMController>().imSdkStatusSubject.values.lastOrNull?.status;
    // Skip beep storms during sync while app is in foreground.
    if (!isRunningBackground && status != IMSdkStatus.syncEnded) {
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
    );
  }

  Future<void> showCallNotification(SignalingInfo info) async {
    if (!DataSp.getEnableCallNotification()) return;

    final invitation = info.invitation;
    final hint = invitation?.mediaType == 'video'
        ? StrRes.videoCallInviteHint
        : StrRes.voiceCallInviteHint;

    String title = '航讯';
    String body = StrRes.offlineCallMessage;
    if (DataSp.getShowNotificationDetail()) {
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
      title = nickname.isEmpty ? title : nickname;
      body = '$nickname$hint';
    }

    if (!isRunningBackground) {
      _playMessageSound();
    }

    final beepOn = _isAllowBeep;
    final androidDetails = AndroidNotificationDetails(
      beepOn ? 'call_v1' : 'call_silent',
      beepOn ? 'Incoming Calls' : 'Incoming Calls (Silent)',
      channelDescription: '航讯来电通知',
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
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: beepOn,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    // Fixed id so we can cancel when call ends / is cancelled.
    await flutterLocalNotificationsPlugin.show(
      _callNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
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
  }) async {
    final beepOn = _isAllowBeep;

    final androidDetails = AndroidNotificationDetails(
      beepOn ? 'chat_v2' : 'chat_silent',
      beepOn ? 'Chat Messages' : 'Chat Messages (Silent)',
      channelDescription: '航讯消息通知',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: beepOn,
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
      payload: '',
    );
  }

  Future<void> _cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  void showBadge(count) {
    OpenIM.iMManager.messageManager.setAppBadge(count);

    if (count == 0) {
      removeBadge();
    } else {
      AppBadgePlus.isSupported().then((value) {
        if (value) {
          AppBadgePlus.updateBadge(count);
        }
      });
    }
  }

  void removeBadge() {
    AppBadgePlus.isSupported().then((value) {
      if (value) {
        AppBadgePlus.updateBadge(0);
      }
    });
  }

  @override
  void onClose() {
    if (identical(PackageBridge.clearCallNotification, cancelCallNotification)) {
      PackageBridge.clearCallNotification = null;
    }
    _connectivitySub?.cancel();
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

  void _stopMessageSound() async {
    if (_audioPlayer.playerState.playing) {
      _audioPlayer.stop();
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
