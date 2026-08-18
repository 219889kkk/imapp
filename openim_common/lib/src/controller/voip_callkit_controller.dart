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
import '../utils/call_audio_debug_log.dart';
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

  /// roomID → millis when CallKit/PushKit first presented (detect re-show races).
  final Map<String, int> _incomingPresentedAtMs = {};

  /// roomID already recovered once after a spurious Timeout/Ended.
  final Set<String> _spuriousRecoveredRooms = {};

  String? get voipToken => _voipToken;

  bool get ownsIncomingUi =>
      (Platform.isIOS || Platform.isAndroid) && callKitActive.value;

  String? get incomingRoomID => _incomingRoomID;

  /// PushKit/Flutter double-show often kills CallKit within a few seconds.
  /// If Dart never recorded present time (PushKit-only wake), treat short-lived
  /// ends as spurious too — otherwise WeChat/background wakes false-reject.
  bool isSpuriousEarlyCallKitEnd(String? roomID, {int withinMs = 12000}) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    final at = _incomingPresentedAtMs[id];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (at == null) {
      // No timestamp yet — still ringing / just presented via PushKit.
      return callKitActive.value || _incomingRoomID == id;
    }
    return now - at < withinMs;
  }

  void noteIncomingPresented(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    if (PackageBridge.isCallRoomEnded?.call(id) == true) {
      Logger.print('CallKit presented ignored — room ended $id');
      return;
    }
    _incomingRoomID = id;
    callKitActive.value = true;
    _incomingPresentedAtMs.putIfAbsent(
        id, () => DateTime.now().millisecondsSinceEpoch);
    Logger.print('CallKit noted presented roomID=$id');
    // Always notify — first invoke often arrives before OpenIMLive is wired.
    PackageBridge.onIncomingCallPresented?.call(id);
  }

  /// After a false Timeout/Ended, try one re-show if the invite is still live.
  Future<bool> recoverSpuriousIncoming(SignalingInfo info) async {
    final id = info.invitation?.roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    if (PackageBridge.isCallRoomEnded?.call(id) == true) return false;
    // In-app invite: never re-open CallKit after hangup dummy / UUID end.
    if (PackageBridge.rtcBridge?.hasCallOverlay == true) {
      Logger.print('CallKit recover skipped — in-app overlay roomID=$id');
      return false;
    }
    if (_spuriousRecoveredRooms.contains(id)) {
      Logger.print('CallKit recover skipped — already tried roomID=$id');
      return false;
    }
    _spuriousRecoveredRooms.add(id);
    callKitActive.value = false;
    _incomingRoomID = null;
    Logger.print('CallKit recover re-show roomID=$id');
    await showIncoming(info);
    return true;
  }

  @override
  void onInit() {
    super.onInit();
    if (!Platform.isIOS && !Platform.isAndroid) return;
    _listenEvents();
    if (Platform.isIOS) {
      _listenNativeVoipChannel();
      _refreshVoipToken();
      unawaited(_pullPendingIncomingRoom());
      unawaited(refreshEndedRoomsFromNative());
      unawaited(refreshInHangXunForeground());
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        unawaited(_pullPendingIncomingRoom());
      });
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        unawaited(_pullPendingIncomingRoom());
      });
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
      // Mic must be granted before lock-screen answer — prompt once after login.
      Future.delayed(const Duration(seconds: 2), () {
        unawaited(Permission.microphone.request());
      });
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

  static Future<void> logoutAsync({bool deleteServerToken = true}) async {
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
    // Kick must NOT wipe the per-user VoIP token — re-login on this phone
    // (or another) would miss lock-screen rings until upload succeeds again.
    if (deleteServerToken &&
        Platform.isIOS &&
        userID != null &&
        userID.isNotEmpty &&
        (DataSp.chatToken?.trim().isNotEmpty ?? false)) {
      await Apis.deleteVoipToken(userID: userID);
    }
  }

  /// Force re-upload after IM reconnect (token may have been wiped / never sent).
  static Future<void> ensureVoipTokenUploaded() async {
    if (!Platform.isIOS) return;
    if (!Get.isRegistered<VoipCallkitController>()) return;
    final ctrl = Get.find<VoipCallkitController>();
    ctrl._lastUploadedToken = null;
    await ctrl._refreshVoipToken(upload: true);
    if (!isPlausibleVoipToken(ctrl._voipToken)) {
      try {
        final cached =
            await _nativeChannel.invokeMethod<String>('getCachedVoipToken');
        final t = (cached ?? '').trim();
        if (isPlausibleVoipToken(t)) {
          ctrl._voipToken = t;
          await ctrl._uploadVoipTokenIfNeeded();
        }
      } catch (e, s) {
        Logger.print('getCachedVoipToken failed: $e $s');
      }
    }
    ctrl._scheduleTokenRetries();
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

  bool _awaitingCallPermSettings = false;
  bool _callPermPromptInFlight = false;
  bool _oemAutostartVisited = false;

  /// After login: request runtime perms, then guide user to Settings if still missing.
  /// Returning from Settings continues with whatever is still off.
  /// "Later" starts a 3-day cooldown only when nothing detectable is missing.
  Future<void> promptAndroidCallPermissionsIfNeeded({
    bool continueAfterSettings = false,
  }) async {
    if (!Platform.isAndroid) return;
    if (_callPermPromptInFlight) return;
    _callPermPromptInFlight = true;
    try {
      await _promptAndroidCallPermissionsIfNeeded(continueAfterSettings);
    } finally {
      _callPermPromptInFlight = false;
    }
  }

  /// User came back from system Settings — keep guiding remaining items.
  Future<void> onReturnedFromSettings() async {
    if (!Platform.isAndroid) return;
    if (!_awaitingCallPermSettings) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!_awaitingCallPermSettings) return;
    _awaitingCallPermSettings = false;
    await promptAndroidCallPermissionsIfNeeded(continueAfterSettings: true);
  }

  Future<Map<String, dynamic>> _callPermGuide() async {
    try {
      final raw = await _nativeChannel.invokeMethod('getCallPermGuide');
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      Logger.print('getCallPermGuide failed: $e');
    }
    return {};
  }

  String _autostartLabelFor(String family) {
    switch (family) {
      case 'xiaomi':
        return StrRes.androidCallPermAutostartXiaomi;
      case 'huawei':
        return StrRes.androidCallPermAutostartHuawei;
      case 'oppo':
        return StrRes.androidCallPermAutostartOppo;
      case 'vivo':
        return StrRes.androidCallPermAutostartVivo;
      case 'meizu':
        return StrRes.androidCallPermAutostartMeizu;
      default:
        return StrRes.androidCallPermAutostart;
    }
  }

  Future<void> _promptAndroidCallPermissionsIfNeeded(
    bool continueAfterSettings,
  ) async {
    await ensureAndroidCallPermissions();
    final guide = await _callPermGuide();
    final family = '${guide['family'] ?? 'stock'}';
    final hasAutostart = guide['hasAutostart'] == true;
    final hibernationOn = guide['hibernationOn'] == true;

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
    if (hibernationOn) {
      missing.add(StrRes.androidCallPermHibernation);
    }
    final hardMissing = List<String>.from(missing);
    if (hasAutostart && !_oemAutostartVisited) {
      missing.add(_autostartLabelFor(family));
    }

    if (missing.isEmpty) {
      Logger.print('android call perm guide skipped (nothing for $family)');
      return;
    }

    final last = DataSp.getAndroidCallPermPromptAt();
    final now = DateTime.now().millisecondsSinceEpoch;
    const cooldownMs = 3 * 24 * 60 * 60 * 1000;
    if (!continueAfterSettings &&
        hardMissing.isEmpty &&
        last > 0 &&
        now - last < cooldownMs) {
      Logger.print('android call perm guide skipped (cooldown) family=$family');
      return;
    }

    final ctx = Get.context ?? Get.overlayContext;
    if (ctx == null) {
      Logger.print('android call perm guide skipped (no context)');
      return;
    }

    final body = sprintf(StrRes.androidCallPermBody, [missing.join('\n')]);
    final showAutostart = hasAutostart && !_oemAutostartVisited;

    await showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(StrRes.androidCallPermTitle),
          content: SingleChildScrollView(child: Text(body)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          actions: [
            TextButton(
              onPressed: () {
                unawaited(DataSp.putAndroidCallPermPromptAt(
                    DateTime.now().millisecondsSinceEpoch));
                Navigator.of(dialogCtx).pop();
              },
              child: Text(StrRes.androidCallPermLater),
            ),
            if (showAutostart)
              TextButton(
                onPressed: () {
                  _awaitingCallPermSettings = true;
                  _oemAutostartVisited = true;
                  Navigator.of(dialogCtx).pop();
                  unawaited(openAutostartSettings());
                },
                child: Text(StrRes.androidCallPermOpenAutostart),
              ),
            TextButton(
              onPressed: () {
                _awaitingCallPermSettings = true;
                Navigator.of(dialogCtx).pop();
                if (hibernationOn) {
                  unawaited(openUnusedAppSettings());
                } else {
                  openAppSettings();
                }
              },
              child: Text(hibernationOn
                  ? StrRes.androidCallPermOpenHibernation
                  : StrRes.androidCallPermGoSettings),
            ),
          ],
        );
      },
    );
  }

  Future<bool> unusedAppRestrictionsEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _nativeChannel.invokeMethod('unusedAppRestrictionsEnabled');
      return v == true;
    } catch (e) {
      Logger.print('unusedAppRestrictionsEnabled failed: $e');
      return false;
    }
  }

  Future<bool> openUnusedAppSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _nativeChannel.invokeMethod('openUnusedAppSettings');
      return v == true;
    } catch (e) {
      Logger.print('openUnusedAppSettings failed: $e');
      openAppSettings();
      return false;
    }
  }

  Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _nativeChannel.invokeMethod('openAutostartSettings');
      if (v == true) return true;
    } catch (e) {
      Logger.print('openAutostartSettings failed: $e');
    }
    openAppSettings();
    return false;
  }

  /// Reject placeholders like server test token `bbbbbb...`.
  static bool isPlausibleVoipToken(String? token) {
    final t = token?.trim() ?? '';
    if (t.length < 32) return false;
    if (RegExp(r'^(b|0|f)+$', caseSensitive: false).hasMatch(t)) return false;
    return true;
  }

  Future<void> _pullPendingIncomingRoom() async {
    if (!Platform.isIOS) return;
    try {
      final raw =
          await _nativeChannel.invokeMethod<String>('getPendingIncomingRoom');
      final id = (raw ?? '').trim();
      if (id.isEmpty) return;
      Logger.print('CallKit pending incoming from native roomID=$id');
      noteIncomingPresented(id);
    } catch (e) {
      Logger.print('getPendingIncomingRoom failed: $e');
    }
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
      if (call.method == 'onVoipCallKitPresented') {
        final args = call.arguments;
        String? roomID;
        if (args is Map) {
          roomID = args['roomID']?.toString();
        } else if (args != null) {
          roomID = args.toString();
        }
        noteIncomingPresented(roomID);
        return;
      }
      if (call.method == 'onCallKitUserEnd') {
        final args = call.arguments;
        String? roomID;
        if (args is Map) {
          roomID = args['roomID']?.toString();
        } else if (args != null) {
          roomID = args.toString();
        }
        Logger.print('CallKit native user end roomID=$roomID');
        CallAudioDebugLog.add('native', 'onCallKitUserEnd roomID=$roomID');
        PackageBridge.onCallKitUserHangup?.call(roomID);
        return;
      }
      if (call.method == 'onCallKitAudioActivated') {
        Logger.print('CallKit audio session activated (native)');
        CallAudioDebugLog.add('native', 'onCallKitAudioActivated');
        PackageBridge.onCallKitAudioActivated?.call();
        return;
      }
      if (call.method == 'onCallKitAudioDeactivated') {
        Logger.print('CallKit audio session deactivated (native)');
        CallAudioDebugLog.add('native', 'onCallKitAudioDeactivated');
        PackageBridge.onCallKitAudioDeactivated?.call();
        return;
      }
      if (call.method == 'onAudioDebug') {
        final args = call.arguments;
        String tag = 'native';
        String message = '';
        if (args is Map) {
          tag = args['tag']?.toString() ?? 'native';
          message = args['message']?.toString() ?? '';
        } else if (args != null) {
          message = args.toString();
        }
        if (message.isNotEmpty) {
          CallAudioDebugLog.add(tag, message);
        }
      }
    });
  }

  Future<void> _refreshVoipToken({bool upload = false}) async {
    try {
      var token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      var raw = '$token'.trim();
      if (raw.isEmpty) {
        try {
          final cached =
              await _nativeChannel.invokeMethod<String>('getCachedVoipToken');
          raw = (cached ?? '').trim();
        } catch (_) {}
      }
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
    // PushKit token often arrives after Flutter login; retry ~5 minutes.
    _tokenRetryTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _tokenRetryCount++;
      await _refreshVoipToken(upload: true);
      if (isPlausibleVoipToken(_voipToken) &&
          _lastUploadedToken == _voipToken) {
        timer.cancel();
        return;
      }
      if (_tokenRetryCount >= 150) {
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
    String? env;
    try {
      env = await _nativeChannel.invokeMethod<String>('getApsEnvironment');
    } catch (_) {}
    Logger.print(
        'voip_token upload start userID=$userID len=${token.length} prefix=$prefix env=$env');
    try {
      await Apis.updateVoipToken(
        userID: userID,
        voipToken: token,
        environment: env,
      );
      _lastUploadedToken = token;
      Logger.print('voip_token upload success userID=$userID env=$env');
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
          if (_isNonInviteVoipFulfill(event.body)) {
            Logger.print('CallKit incoming ignored — non-invite VoIP fulfill');
            break;
          }
          final incoming = signalingFromCallKitBody(event.body);
          final incomingRoom = incoming?.invitation?.roomID?.trim() ?? '';
          noteIncomingPresented(
              incomingRoom.isNotEmpty ? incomingRoom : null);
          // WS invite may have already opened in-app UI.
          // Background (WeChat etc.): NEVER end CallKit for a stale overlay —
          // that fired Ended → false callingReject within ~2s.
          if (PackageBridge.rtcBridge?.hasCallOverlay == true) {
            final life = WidgetsBinding.instance.lifecycleState;
            final inForeground = life == AppLifecycleState.resumed;
            if (!inForeground) {
              Logger.print(
                  'CallKit incoming: keep system ring (overlay stale, bg)');
              CallAudioDebugLog.add(
                  'callkit', 'incoming keep CallKit bg overlay roomID=$incomingRoom');
            }
            // Foreground overlay is dismissed by live_controller beCalled.
            // Never endCall here — VoIP wake looks resumed and was killing
            // the lock/home CallKit banner.
          }
          break;
        case Event.actionCallAccept:
          // Stay "active" until LiveKit connects / real hangup.
          callKitActive.value = true;
          _onAccept(event.body);
          break;
        case Event.actionCallDecline:
          if (_isNonInviteVoipFulfill(event.body)) {
            break;
          }
          callKitActive.value = false;
          _incomingRoomID = null;
          _onDecline(event.body);
          break;
        case Event.actionCallTimeout:
          // Missed ring — never map to reject (that stuck caller on "请求中"
          // / showed 对方已拒绝 when callee was in WeChat/browser).
          callKitActive.value = false;
          _incomingRoomID = null;
          _onTimeout(event.body);
          break;
        case Event.actionCallEnded:
          if (_isNonInviteVoipFulfill(event.body)) {
            break;
          }
          callKitActive.value = false;
          _incomingRoomID = null;
          _onEnded(event.body);
          break;
        case Event.actionCallToggleAudioSession:
          // Native AppDelegate didActivateAudioSession → MethodChannel only.
          // Plugin event fires before RTCAudioSession bridge — do not join LiveKit here.
          Logger.print('CallKit audio session toggled (ignored — wait for native bridge)');
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

  bool _isNonInviteVoipFulfill(dynamic body) {
    final extra = _extraOf(body);
    if (extra['silentFulfill'] == true || extra['silentFulfill'] == 'true') {
      return true;
    }
    var action = extra['action']?.toString();
    if ((action == null || action.isEmpty) && body is Map) {
      action = body['action']?.toString();
    }
    switch (action?.toLowerCase().trim()) {
      case 'accept':
      case 'answered':
      case 'cancel':
      case 'end':
      case 'hungup':
      case 'reject':
        return true;
      default:
        break;
    }
    // Native silent mustReport dummy — handle hangxun-silent, blank caller.
    if (body is Map) {
      final handle = '${body['handle'] ?? extra['handle'] ?? ''}'.trim().toLowerCase();
      final name = '${body['nameCaller'] ?? extra['nameCaller'] ?? ''}'.trim();
      if (handle == 'hangxun-silent' ||
          (handle == 'hangxun' && name.isEmpty)) {
        return true;
      }
    }
    return false;
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

  String? _lastAcceptRoomID;
  int _lastAcceptAtMs = 0;

  void _onAccept(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    if (signaling != null) {
      final roomID = signaling.invitation?.roomID?.trim() ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;
      // Plugin can re-fire accept many times around setConnected / unlock.
      if (roomID.isNotEmpty &&
          roomID == _lastAcceptRoomID &&
          now - _lastAcceptAtMs < 5000) {
        CallAudioDebugLog.add('callkit', 'plugin accept debounced roomID=$roomID');
        return;
      }
      _lastAcceptRoomID = roomID;
      _lastAcceptAtMs = now;
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

  void _onTimeout(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    PackageBridge.onCallKitTimeout?.call(signaling);
  }

  void _onEnded(dynamic body) {
    PackageBridge.clearCallNotification?.call();
    final signaling = signalingFromCallKitBody(body);
    PackageBridge.onCallKitEnded?.call(signaling);
  }

  /// RoomID currently shown in CallKit / full-screen incoming UI.
  String? _incomingRoomID;

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

    final uuid = invitation!.roomID!;
    // PushKit already reported CallKit — re-show same UUID ends the first call
    // and fires Timeout/Ended → callee UI dies while caller keeps waiting.
    if (callKitActive.value && _incomingRoomID == uuid) {
      noteIncomingPresented(uuid);
      Logger.print('showIncoming skipped: already ringing roomID=$uuid');
      return;
    }
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List) {
        for (final item in active) {
          final id = item is Map ? item['id']?.toString() : null;
          if (id == uuid) {
            noteIncomingPresented(uuid);
            Logger.print('showIncoming skipped: native active roomID=$uuid');
            return;
          }
        }
      }
    } catch (e, s) {
      Logger.print('showIncoming activeCalls check failed: $e $s');
    }

    if (Platform.isAndroid) {
      await ensureAndroidCallPermissions();
    }

    final isVideo = invitation.mediaType == 'video';
    final caller = nameCaller?.trim().isNotEmpty == true
        ? nameCaller!.trim()
        : (invitation.inviterUserID ?? '来电');
    // Clamp: 0/tiny timeout makes CallKit fire Timeout immediately → false reject.
    final timeoutSec = (() {
      final t = invitation.timeout ?? 60;
      return t < 30 ? 60 : t;
    })();

    final extra = <String, dynamic>{
      'type': 'callingInvite',
      'roomID': invitation.roomID,
      'inviterUserID': invitation.inviterUserID,
      'inviteeUserIDList': invitation.inviteeUserIDList,
      'mediaType': invitation.mediaType ?? (isVideo ? 'video' : 'audio'),
      'sessionType': invitation.sessionType,
      'groupID': invitation.groupID,
      'timeout': timeoutSec,
      'nickname': caller,
    };

    final params = CallKitParams(
      id: uuid,
      nameCaller: caller,
      appName: '航讯',
      handle: invitation.inviterUserID ?? '',
      type: isVideo ? 1 : 0,
      duration: timeoutSec * 1000,
      textAccept: StrRes.pickUp,
      textDecline: StrRes.reject,
      extra: extra,
      missedCallNotification: NotificationParams(
        showNotification: !Platform.isIOS,
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
        // Must be false — plugin session config fights WebRTC/LiveKit (see flutter_callkit_incoming #402).
        configureAudioSession: false,
        audioSessionActive: false,
        // 20 ms IO — 5 ms was too aggressive and broke speaker AEC (howling).
        audioSessionPreferredSampleRate: 48000.0,
        audioSessionPreferredIOBufferDuration: 0.02,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    noteIncomingPresented(uuid);
    Logger.print(
        'showIncoming platform=${Platform.operatingSystem} roomID=$uuid caller=$caller video=$isVideo');
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// roomID → last setConnected millis (dedupe CallKit audio activate storms).
  final Map<String, int> _setConnectedAtMs = {};

  /// Mark an answered CallKit call as connected (keeps system call audio session).
  /// Once per room until hangup — repeated calls flap AVAudioSession → mic flicker.
  Future<void> setConnected([String? roomID]) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _setConnectedAtMs[id];
    if (last != null && now - last < 15000) {
      CallAudioDebugLog.add('callkit', 'setCallConnected debounced roomID=$id');
      return;
    }
    _setConnectedAtMs[id] = now;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
      callKitActive.value = true;
      Logger.print('CallKit setConnected roomID=$id');
      CallAudioDebugLog.add('callkit', 'setCallConnected roomID=$id');
    } catch (e, s) {
      Logger.print('setConnected failed: $e $s');
      CallAudioDebugLog.add('callkit', 'setCallConnected failed: $e');
    }
  }

  /// Native UserDefaults ended rooms — survives Flutter isolate death.
  final Set<String> _nativeEndedRooms = {};

  bool isNativelyEnded(String? roomID) {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return false;
    if (_nativeEndedRooms.contains(id)) return true;
    final compact = id.toLowerCase().replaceAll('-', '');
    return _nativeEndedRooms.any(
        (e) => e.toLowerCase().replaceAll('-', '') == compact);
  }

  bool inHangXunForeground = false;

  /// Android lock screen / screen-off (Keyguard). iOS unused.
  bool deviceLocked = false;

  Future<bool> refreshInHangXunForeground() async {
    if (!Platform.isIOS) return false;
    try {
      final v = await _nativeChannel.invokeMethod('isInHangXunForeground');
      inHangXunForeground = v == true;
    } catch (_) {
      inHangXunForeground = false;
    }
    return inHangXunForeground;
  }

  Future<bool> refreshDeviceLocked() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _nativeChannel.invokeMethod('isDeviceLocked');
      deviceLocked = v == true;
    } catch (_) {
      deviceLocked = false;
    }
    return deviceLocked;
  }

  Future<void> refreshEndedRoomsFromNative() async {
    if (!Platform.isIOS) return;
    try {
      final raw = await _nativeChannel.invokeMethod('getEndedRooms');
      if (raw is List) {
        _nativeEndedRooms
          ..clear()
          ..addAll(raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty));
      }
    } catch (e) {
      Logger.print('getEndedRooms native failed: $e');
    }
  }

  /// Tell native PushKit to ignore late invites for this room (zombie CallKit).
  Future<void> markRoomEndedNative(String? roomID) async {
    final id = roomID?.trim() ?? '';
    if (id.isEmpty) return;
    _nativeEndedRooms.add(id);
    _setConnectedAtMs.remove(id);
    _incomingPresentedAtMs.remove(id);
    _spuriousRecoveredRooms.remove(id);
    if (_incomingRoomID == id) _incomingRoomID = null;
    if (!Platform.isIOS) return;
    try {
      await _nativeChannel.invokeMethod('markRoomEnded', {'roomID': id});
    } catch (e) {
      CallAudioDebugLog.add('callkit', 'markRoomEnded native failed: $e');
    }
  }

  Future<void> endCall([String? roomID]) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      if (roomID != null && roomID.isNotEmpty) {
        PackageBridge.suppressCallKitEnded?.call(roomID);
        _incomingPresentedAtMs.remove(roomID);
        _spuriousRecoveredRooms.remove(roomID);
      } else {
        _incomingPresentedAtMs.clear();
        _spuriousRecoveredRooms.clear();
      }
      if (Platform.isIOS) {
        // Native reportCall(.remoteEnded) — plugin endCall is CXEndCallAction
        // ("即将结束") and can hang with no way to dismiss.
        await _nativeChannel.invokeMethod('endAllCallKit', {
          'roomID': roomID ?? '',
        });
      } else if (roomID != null && roomID.isNotEmpty) {
        await FlutterCallkitIncoming.endCall(roomID);
      } else {
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e, s) {
      Logger.print('endCall failed: $e $s');
    }
    final keepIncoming = _incomingRoomID?.trim() ?? '';
    final ending = roomID?.trim() ?? '';
    final keepOther = keepIncoming.isNotEmpty &&
        ending.isNotEmpty &&
        keepIncoming != ending;
    if (!keepOther) {
      callKitActive.value = false;
    }
    if (ending.isNotEmpty && _incomingRoomID == ending) {
      _incomingRoomID = null;
    }
  }

  Future<void> endAllCalls({String? roomID}) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final ended = (roomID ?? _incomingRoomID ?? '').trim();
    final keep = _incomingRoomID?.trim() ?? '';
    final keepNewer = keep.isNotEmpty && ended.isNotEmpty && keep != ended;
    try {
      if (!Platform.isIOS) {
        if (keepNewer) {
          await FlutterCallkitIncoming.endCall(ended);
        } else {
          await FlutterCallkitIncoming.endAllCalls();
        }
      }
    } catch (e, s) {
      Logger.print('endAllCalls failed: $e $s');
    }
    if (Platform.isIOS) {
      try {
        await _nativeChannel.invokeMethod('endAllCallKit', {
          'roomID': ended,
        });
      } catch (e, s) {
        Logger.print('native endAllCallKit failed: $e $s');
      }
    }
    if (!keepNewer) {
      callKitActive.value = false;
      _incomingRoomID = null;
      _incomingPresentedAtMs.clear();
      _spuriousRecoveredRooms.clear();
    } else {
      _incomingPresentedAtMs.remove(ended);
      _spuriousRecoveredRooms.remove(ended);
    }
  }

  /// Active CallKit room IDs (lock-screen ring / ongoing timer).
  Future<List<String>> activeCallRoomIDs() async {
    if (!Platform.isIOS && !Platform.isAndroid) return const [];
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is! List) return const [];
      final ids = <String>[];
      for (final raw in active) {
        String id = '';
        if (raw is CallKitParams) {
          id = raw.id?.trim() ?? '';
        } else if (raw is Map) {
          id = '${raw['id'] ?? ''}'.trim();
        }
        if (id.isNotEmpty) ids.add(id);
      }
      return ids;
    } catch (e, s) {
      Logger.print('activeCallRoomIDs failed: $e $s');
      return const [];
    }
  }

  static String newCallId() => const Uuid().v4();
}
