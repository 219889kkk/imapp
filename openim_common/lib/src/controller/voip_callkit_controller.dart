import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../apis.dart';
import '../bridge/package_bridge.dart';
import '../models/signaling_info.dart';
import '../res/strings.dart';
import '../utils/logger.dart';

/// iOS PushKit + CallKit bridge for voice/video invites.
///
/// Native [AppDelegate] registers PushKit, calls Getui
/// `registerVoipTokenCredentials`, and shows CallKit **before** VoIP
/// completion. This controller listens to CallKit events.
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

  /// True while a CallKit incoming UI is active (avoid double local banners).
  final RxBool callKitActive = false.obs;

  String? get voipToken => _voipToken;

  bool get ownsIncomingUi => Platform.isIOS && callKitActive.value;

  @override
  void onInit() {
    super.onInit();
    if (!Platform.isIOS) return;
    _listenNativeVoipChannel();
    _listenEvents();
    _refreshVoipToken();
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
    if (!Platform.isIOS) return;
    final ctrl = Get.isRegistered<VoipCallkitController>()
        ? Get.find<VoipCallkitController>()
        : Get.put(VoipCallkitController(), permanent: true);
    ctrl._boundUserID = userID;
    // Force re-upload even if same device token was uploaded for another account.
    ctrl._lastUploadedToken = null;
    unawaited(ctrl._refreshVoipToken(upload: true));
    ctrl._scheduleTokenRetries();
    Logger.print('VoipCallkit login userID=$userID token=${ctrl._voipToken}');
  }

  static void logout() {
    if (!Platform.isIOS) return;
    if (!Get.isRegistered<VoipCallkitController>()) return;
    final ctrl = Get.find<VoipCallkitController>();
    ctrl._boundUserID = null;
    ctrl._lastUploadedToken = null;
    ctrl._tokenRetryTimer?.cancel();
    unawaited(FlutterCallkitIncoming.endAllCalls());
    ctrl.callKitActive.value = false;
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
          break;
        case Event.actionCallAccept:
          callKitActive.value = false;
          _onAccept(event.body);
          break;
        case Event.actionCallDecline:
          callKitActive.value = false;
          _onDecline(event.body);
          break;
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          callKitActive.value = false;
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
        timeout: int.tryParse('${extra['timeout'] ?? 60}') ?? 60,
      ),
    );
  }

  void _onAccept(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    PackageBridge.handleCallNotificationAction?.call(true);
    final signaling = signalingFromCallKitBody(body);
    if (signaling != null) {
      PackageBridge.onCallKitAccept?.call(signaling);
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

  /// Show CallKit from Dart (online/background fallback). Prefer native PushKit when killed.
  Future<void> showIncoming(SignalingInfo info, {String? nameCaller}) async {
    if (!Platform.isIOS) return;
    final invitation = info.invitation;
    if (invitation?.roomID == null) return;

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
      'timeout': invitation.timeout ?? 60,
      'nickname': caller,
    };

    final params = CallKitParams(
      id: uuid,
      nameCaller: caller,
      appName: '航讯',
      handle: invitation.inviterUserID ?? '',
      type: isVideo ? 1 : 0,
      duration: (invitation.timeout ?? 60) * 1000,
      textAccept: StrRes.pickUp,
      textDecline: StrRes.reject,
      extra: extra,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    callKitActive.value = true;
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> endCall([String? roomID]) async {
    if (!Platform.isIOS) return;
    try {
      if (roomID != null && roomID.isNotEmpty) {
        await FlutterCallkitIncoming.endCall(roomID);
      } else {
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e, s) {
      Logger.print('endCall failed: $e $s');
    }
    callKitActive.value = false;
  }

  Future<void> endAllCalls() => endCall();

  static String newCallId() => const Uuid().v4();
}
