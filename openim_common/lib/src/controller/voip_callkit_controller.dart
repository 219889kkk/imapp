import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sprintf/sprintf.dart';
import 'package:uuid/uuid.dart';

import '../apis.dart';
import '../bridge/package_bridge.dart';
import '../models/signaling_info.dart';
import '../res/strings.dart';
import '../utils/data_sp.dart';
import '../utils/logger.dart';
import '../utils/session_guard.dart';

/// iOS PushKit + CallKit / Android full-screen incoming-call bridge.
///
/// - iOS: native PushKit registers early; CallKit reports before VoIP completion.
/// - Android: [showIncoming] uses flutter_callkit_incoming full-screen /
///   high-priority call notification when the app is backgrounded (process alive).
class VoipCallkitController extends GetxService {
  static VoipCallkitController get to => Get.find();

  static VoipCallkitController? get toOrNull =>
      Get.isRegistered<VoipCallkitController>()
          ? Get.find<VoipCallkitController>()
          : null;

  static const _nativeChannel = MethodChannel('top.hangxun.app/voip');

  StreamSubscription? _eventSub;
  String? _voipToken;
  String? _boundUserID;
  String? _lastUploadedToken;
  Timer? _tokenRetryTimer;
  int _tokenRetryCount = 0;
  bool _uploading = false;

  /// True while a CallKit / Android incoming UI is active (avoid double banners).
  final RxBool callKitActive = false.obs;

  String? get voipToken => _voipToken;

  bool get ownsIncomingUi =>
      (Platform.isIOS || Platform.isAndroid) && callKitActive.value;

  @override
  void onInit() {
    super.onInit();
    if (!Platform.isIOS && !Platform.isAndroid) return;
    _listenEvents();
    if (Platform.isIOS) {
      _listenNativeVoipChannel();
      _refreshVoipToken();
    }
  }

  @override
  void onClose() {
    _eventSub?.cancel();
    _tokenRetryTimer?.cancel();
    _nativeChannel.setMethodCallHandler(null);
    super.onClose();
  }

  /// After Getui [PushController.login] / bindAlias.
  static void login(String userID) {
    SessionGuard.markLoggedIn();
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final ctrl = Get.isRegistered<VoipCallkitController>()
        ? Get.find<VoipCallkitController>()
        : Get.put(VoipCallkitController(), permanent: true);
    ctrl._boundUserID = userID;
    if (Platform.isIOS) {
      // Force re-upload even if same device token was uploaded for another account.
      ctrl._lastUploadedToken = null;
      unawaited(ctrl._refreshVoipToken(upload: true));
      ctrl._scheduleTokenRetries();
      Logger.print('VoipCallkit login userID=$userID token=${ctrl._voipToken}');
    } else {
      // Delay until main UI is up so the Settings dialog can show.
      Future.delayed(const Duration(seconds: 2), () {
        unawaited(ctrl.promptAndroidCallPermissionsIfNeeded());
      });
      Logger.print('VoipCallkit Android login userID=$userID');
    }
  }

  static void logout() {
    unawaited(logoutAsync());
  }

  static Future<void> logoutAsync() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (!Get.isRegistered<VoipCallkitController>()) return;
    final ctrl = Get.find<VoipCallkitController>();
    final userID = ctrl._boundUserID ?? DataSp.userID;
    ctrl._boundUserID = null;
    ctrl._lastUploadedToken = null;
    ctrl._tokenRetryTimer?.cancel();
    ctrl._voipToken = null;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e, s) {
      Logger.print('VoipCallkit endAllCalls: $e $s');
    }
    ctrl.callKitActive.value = false;
    if (Platform.isIOS &&
        userID != null &&
        userID.isNotEmpty &&
        (DataSp.chatToken?.trim().isNotEmpty ?? false)) {
      await Apis.deleteVoipToken(userID: userID);
    }
  }

  /// Android: notification + full-screen intent (+ overlay if needed).
  Future<void> ensureAndroidCallPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        await Permission.notification.request();
      }
    } catch (e, s) {
      Logger.print('request notification permission failed: $e $s');
    }
    try {
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (can != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e, s) {
      Logger.print('request full-screen intent failed: $e $s');
    }
    try {
      final overlay = await Permission.systemAlertWindow.status;
      if (!overlay.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    } catch (e, s) {
      Logger.print('request system alert window failed: $e $s');
    }
    try {
      final battery = await Permission.ignoreBatteryOptimizations.status;
      if (!battery.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e, s) {
      Logger.print('request ignore battery optimization failed: $e $s');
    }
  }

  /// After login: request runtime perms, then guide user to Settings if still missing.
  /// Dialog at most once every 3 days to avoid nagging.
  Future<void> promptAndroidCallPermissionsIfNeeded() async {
    if (!Platform.isAndroid) return;
    await ensureAndroidCallPermissions();

    final missing = <String>[];
    try {
      if (!(await Permission.notification.isGranted)) {
        missing.add(StrRes.androidCallPermNotification);
      }
    } catch (_) {}
    try {
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (can != true) {
        missing.add(StrRes.androidCallPermFullScreen);
      }
    } catch (_) {}
    try {
      if (!(await Permission.systemAlertWindow.isGranted)) {
        missing.add(StrRes.androidCallPermOverlay);
      }
    } catch (_) {}
    try {
      if (!(await Permission.ignoreBatteryOptimizations.isGranted)) {
        missing.add(StrRes.androidCallPermBattery);
      }
    } catch (_) {}

    if (missing.isEmpty) return;

    final last = DataSp.getAndroidCallPermPromptAt();
    final now = DateTime.now().millisecondsSinceEpoch;
    const cooldownMs = 3 * 24 * 60 * 60 * 1000;
    if (last > 0 && now - last < cooldownMs) {
      Logger.print('android call perm guide skipped (cooldown), missing=$missing');
      return;
    }

    final ctx = Get.context ?? Get.overlayContext;
    if (ctx == null) {
      Logger.print('android call perm guide skipped (no context)');
      return;
    }

    await DataSp.putAndroidCallPermPromptAt(now);
    final body = sprintf(StrRes.androidCallPermBody, [missing.join('\n')]);

    await showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(StrRes.androidCallPermTitle),
          content: Text(body),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(StrRes.androidCallPermLater),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                openAppSettings();
              },
              child: Text(StrRes.androidCallPermGoSettings),
            ),
          ],
        );
      },
    );
  }

  /// Reject placeholders like server test token `bbbbbb...`.
  static bool isPlausibleVoipToken(String? token) {
    final t = token?.trim() ?? '';
    if (t.length < 32) return false;
    if (RegExp(r'^(b|0|f)+$', caseSensitive: false).hasMatch(t)) return false;
    return true;
  }

  void _listenNativeVoipChannel() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVoipToken') {
        final token = '${call.arguments ?? ''}'.trim();
        if (token.isEmpty) return;
        _voipToken = token;
        Logger.print('VoIP token from native channel: $token');
        await _uploadVoipTokenIfNeeded();
        return;
      }
      if (call.method == 'onVoipRemoteEnd') {
        final args = call.arguments;
        String? roomID;
        String action = 'cancel';
        if (args is Map) {
          roomID = args['roomID']?.toString();
          action = args['action']?.toString() ?? 'cancel';
        }
        PackageBridge.onVoipRemoteEnd?.call(roomID, action);
        return;
      }
      if (call.method == 'onCallKitAudioActivated') {
        Logger.print('CallKit audio session activated (native)');
        PackageBridge.onCallKitAudioActivated?.call();
      }
    });
  }

  Future<void> _refreshVoipToken({bool upload = false}) async {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      final raw = '$token'.trim();
      if (raw.isNotEmpty) {
        _voipToken = raw;
        Logger.print('VoIP PushKit token: $_voipToken');
        if (upload) await _uploadVoipTokenIfNeeded();
      } else {
        Logger.print('VoIP PushKit token empty (waiting for PushKit)');
      }
    } catch (e, s) {
      Logger.print('getDevicePushTokenVoIP failed: $e $s');
    }
  }

  void _scheduleTokenRetries() {
    _tokenRetryTimer?.cancel();
    _tokenRetryCount = 0;
    // PushKit token often arrives after Flutter login; retry ~2 minutes.
    _tokenRetryTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _tokenRetryCount++;
      await _refreshVoipToken(upload: true);
      if (isPlausibleVoipToken(_voipToken) &&
          _lastUploadedToken == _voipToken) {
        timer.cancel();
        return;
      }
      if (_tokenRetryCount >= 60) {
        Logger.print(
            'VoIP token upload gave up after retries; last=$_voipToken uploaded=$_lastUploadedToken');
        timer.cancel();
      }
    });
  }

  Future<void> _uploadVoipTokenIfNeeded() async {
    final userID = _boundUserID;
    final token = _voipToken;
    if (userID == null || userID.isEmpty) {
      Logger.print('voip_token upload skip: no bound userID');
      return;
    }
    if (token == null || token.trim().isEmpty) {
      Logger.print('voip_token upload skip: PushKit hex empty');
      return;
    }
    if (!isPlausibleVoipToken(token)) {
      Logger.print('voip_token upload skip (implausible): $token');
      return;
    }
    if (token == _lastUploadedToken) return;
    if (_uploading) return;
    _uploading = true;
    final prefix = token.length <= 8 ? token : token.substring(0, 8);
    Logger.print(
        'voip_token upload start userID=$userID len=${token.length} prefix=$prefix');
    try {
      await Apis.updateVoipToken(userID: userID, voipToken: token);
      _lastUploadedToken = token;
      Logger.print('voip_token upload success userID=$userID');
    } catch (e, s) {
      Logger.print('voip_token upload error (will retry): $e $s');
    } finally {
      _uploading = false;
    }
  }

  void _listenEvents() {
    _eventSub?.cancel();
    _eventSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      Logger.print('CallKit event: ${event.event} body=${event.body}');
      switch (event.event) {
        case Event.actionCallIncoming:
          callKitActive.value = true;
          // WS invite may have already opened in-app UI — drop duplicate banner.
          if (PackageBridge.rtcBridge?.hasCallOverlay == true) {
            final signaling = signalingFromCallKitBody(event.body);
            final roomID = signaling?.invitation?.roomID;
            PackageBridge.suppressCallKitEnded?.call(roomID);
            unawaited(endCall(roomID));
            callKitActive.value = false;
          }
          break;
        case Event.actionCallAccept:
          // Stay "active" until LiveKit connects / real hangup.
          callKitActive.value = true;
          _onAccept(event.body);
          break;
        case Event.actionCallDecline:
          callKitActive.value = false;
          _onDecline(event.body);
          break;
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          callKitActive.value = false;
          _onEnded(event.body);
          break;
        case Event.actionCallToggleAudioSession:
          Logger.print('CallKit audio session toggled');
          PackageBridge.onCallKitAudioActivated?.call();
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          final token = event.body is Map
              ? (event.body['deviceTokenVoIP'] ?? event.body['token'])
                  ?.toString()
              : event.body?.toString();
          if (token != null && token.isNotEmpty) {
            _voipToken = token;
            Logger.print('VoIP token updated: $token');
            unawaited(_uploadVoipTokenIfNeeded());
          }
          break;
        default:
          break;
      }
    });
  }

  Map<String, dynamic> _extraOf(dynamic body) {
    if (body is! Map) return {};
    final map = Map<String, dynamic>.from(body);
    final extra = map['extra'];
    if (extra is Map) return Map<String, dynamic>.from(extra);
    if (extra is String && extra.isNotEmpty) {
      try {
        final decoded = jsonDecode(extra);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return map;
  }

  SignalingInfo? signalingFromCallKitBody(dynamic body) {
    final extra = _extraOf(body);
    if (extra.isEmpty && body is! Map) return null;

    String? roomID = extra['roomID']?.toString();
    String? inviter = extra['inviterUserID']?.toString();
    String? mediaType = extra['mediaType']?.toString();
    final inviteesRaw = extra['inviteeUserIDList'];
    List<String>? invitees;
    if (inviteesRaw is List) {
      invitees = inviteesRaw.map((e) => e.toString()).toList();
    }

    if (body is Map) {
      roomID ??= body['id']?.toString();
      inviter ??= body['handle']?.toString();
      final type = body['type'];
      mediaType ??= (type == 1 || type == '1') ? 'video' : 'audio';
    }

    if (roomID == null || roomID.isEmpty) return null;
    invitees ??= [
      if (_boundUserID != null && _boundUserID!.isNotEmpty) _boundUserID!,
    ];

    return SignalingInfo(
      userID: inviter,
      invitation: InvitationInfo(
        roomID: roomID,
        inviterUserID: inviter,
        inviteeUserIDList: invitees,
        mediaType: mediaType ?? 'audio',
        sessionType: int.tryParse('${extra['sessionType'] ?? 1}') ?? 1,
        groupID: extra['groupID']?.toString(),
        timeout: int.tryParse('${extra['timeout'] ?? 30}') ?? 30,
      ),
    );
  }

  void _onAccept(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    if (signaling != null) {
      // Prefer CallKit path only — avoid double receiveNewInvitation via
      // handleCallNotificationAction + onCallKitAccept.
      PackageBridge.onCallKitAccept?.call(signaling);
    } else {
      PackageBridge.handleCallNotificationAction?.call(true);
    }
  }

  void _onDecline(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    if (signaling != null) {
      PackageBridge.onCallKitDecline?.call(signaling);
    } else {
      PackageBridge.handleCallNotificationAction?.call(false);
    }
  }

  void _onEnded(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    PackageBridge.onCallKitEnded?.call(signaling);
  }

  /// Show system-style incoming call (iOS CallKit / Android full-screen).
  Future<void> showIncoming(SignalingInfo info, {String? nameCaller}) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (PackageBridge.rtcBridge?.hasCallOverlay == true) {
      Logger.print('showIncoming skipped: in-app overlay already visible');
      return;
    }
    if (PackageBridge.isCallRoomEnded?.call(info.invitation?.roomID) == true) {
      Logger.print('showIncoming skipped: room ended ${info.invitation?.roomID}');
      return;
    }
    final invitation = info.invitation;
    if (invitation?.roomID == null) return;

    if (Platform.isAndroid) {
      await ensureAndroidCallPermissions();
    }

    final isVideo = invitation!.mediaType == 'video';
    final uuid = invitation.roomID!;
    final caller = nameCaller?.trim().isNotEmpty == true
        ? nameCaller!.trim()
        : (invitation.inviterUserID ?? '来电');

    final extra = <String, dynamic>{
      'type': 'callingInvite',
      'roomID': invitation.roomID,
      'inviterUserID': invitation.inviterUserID,
      'inviteeUserIDList': invitation.inviteeUserIDList,
      'mediaType': invitation.mediaType ?? (isVideo ? 'video' : 'audio'),
      'sessionType': invitation.sessionType,
      'groupID': invitation.groupID,
      'timeout': invitation.timeout ?? 30,
      'nickname': caller,
    };

    final params = CallKitParams(
      id: uuid,
      nameCaller: caller,
      appName: '航讯',
      handle: invitation.inviterUserID ?? '',
      type: isVideo ? 1 : 0,
      duration: (invitation.timeout ?? 30) * 1000,
      textAccept: StrRes.pickUp,
      textDecline: StrRes.reject,
      extra: extra,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isCustomSmallExNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        ringtonePath: 'notification_ring',
        backgroundColor: '#095C37',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowFullLockedScreen: true,
        isImportant: true,
        isBot: false,
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    callKitActive.value = true;
    Logger.print(
        'showIncoming platform=${Platform.operatingSystem} roomID=$uuid caller=$caller video=$isVideo');
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Mark an answered CallKit call as connected (keeps system call audio session).
  Future<void> setConnected([String? roomID]) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
      callKitActive.value = true;
      Logger.print('CallKit setConnected roomID=$id');
    } catch (e, s) {
      Logger.print('setConnected failed: $e $s');
    }
  }

  Future<void> endCall([String? roomID]) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      if (roomID != null && roomID.isNotEmpty) {
        PackageBridge.suppressCallKitEnded?.call(roomID);
        await FlutterCallkitIncoming.endCall(roomID);
      } else {
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e, s) {
      Logger.print('endCall failed: $e $s');
    }
    callKitActive.value = false;
  }

  Future<void> endAllCalls() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e, s) {
      Logger.print('endAllCalls failed: $e $s');
    }
    callKitActive.value = false;
  }

  static String newCallId() => const Uuid().v4();
}
