import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:openim_live/openim_live.dart';

import '../im_callback.dart';
import 'app_controller.dart';
import 'session_logout.dart';
import '../../routes/app_navigator.dart';
import '../../pages/home/home_logic.dart';

class IMController extends GetxController with IMCallback, OpenIMLive {
  late Rx<UserFullInfo> userInfo;
  late String atAllTag;

  bool _failoverInFlight = false;
  DateTime? _lastFailoverAt;
  bool _reconnectInFlight = false;
  DateTime? _lastReconnectAt;
  StreamSubscription<KickoffType>? _kickedOfflineSub;
  StreamSubscription? _httpKickoffSub;
  bool _kickoffInFlight = false;
  bool _rtcRecoveryInFlight = false;
  DateTime? _lastRtcRecoveryAt;

  static bool _isActiveCallInProgress() => OpenIMLiveClient().isBusy;

  @override
  void onClose() {
    if (identical(PackageBridge.onEndpointSwitched, _onHttpEndpointSwitched)) {
      PackageBridge.onEndpointSwitched = null;
    }
    _kickedOfflineSub?.cancel();
    _httpKickoffSub?.cancel();
    close();
    onCloseLive();
    super.onClose();
  }

  @override
  void onInit() async {
    userInfo = UserFullInfo(userID: DataSp.userID ?? '').obs;
    super.onInit();
    onInitLive();
    PackageBridge.onEndpointSwitched = _onHttpEndpointSwitched;
    _bindKickoffListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => initOpenIM());
  }

  void _bindKickoffListener() {
    _kickedOfflineSub?.cancel();
    _kickedOfflineSub = onKickedOfflineSubject.listen(_handleKickoff);
    _httpKickoffSub?.cancel();
    _httpKickoffSub = Apis.kickoffController.stream.listen((event) {
      final code = event is int ? event : int.tryParse('$event') ?? 0;
      unawaited(_handleHttpKickoff(code));
    });
  }

  Future<void> _handleHttpKickoff(int errCode) async {
    final type = switch (errCode) {
      1501 => KickoffType.userTokenExpired,
      1502 || 1503 || 1504 || 1505 => KickoffType.userTokenInvalid,
      _ => KickoffType.userTokenInvalid,
    };
    await _handleKickoff(type);
  }

  Future<void> _handleKickoff(KickoffType type) async {
    if (_kickoffInFlight || SessionGuard.suppressNotifications) return;
    _kickoffInFlight = true;
    try {
      final tips = switch (type) {
        KickoffType.userTokenInvalid => StrRes.tokenInvalid,
        KickoffType.userTokenExpired => StrRes.tokenExpired,
        KickoffType.kickedOffline => StrRes.accountException,
      };
      IMViews.showToast('${StrRes.accountWarn}: $tips');
      await SessionLogout.runFromKickoff(
        im: this,
        onConversationsCleared: () {
          if (Get.isRegistered<HomeLogic>()) {
            Get.find<HomeLogic>().conversationsAtFirstPage.clear();
          }
        },
      );
      AppNavigator.startLogin();
    } catch (e, s) {
      Logger.print('handleKickoff failed: $e $s');
    } finally {
      _kickoffInFlight = false;
    }
  }

  Future<void> initOpenIM() async {
    var initialized = false;
    try {
      initialized = await OpenIM.iMManager.initSDK(
        platformID: IMUtils.getPlatform(),
        apiAddr: Config.imApiUrl,
        wsAddr: Config.imWsUrl,
        dataDir: Config.cachePath,
        logLevel: Config.logLevel,
        logFilePath: Config.cachePath,
        isLogStandardOutput: kDebugMode,
        listener: OnConnectListener(
          onConnecting: () {
            imSdkStatus(IMSdkStatus.connecting);
          },
          onConnectFailed: (code, error) {
            imSdkStatus(IMSdkStatus.connectionFailed);
            unawaited(_tryFailoverOnConnectFailed());
            unawaited(_softReconnectAfterDisconnect());
          },
          onConnectSuccess: () {
            imSdkStatus(IMSdkStatus.connectionSucceeded);
            var loggedIn = false;
            try {
              loggedIn = OpenIM.iMManager.isLogined;
            } catch (_) {}
            if (!loggedIn) return;
            // Re-arm call alerts after reconnect (suppress/login-hint races).
            SessionGuard.markLoggedIn();
            if (Get.isRegistered<AppController>()) {
              unawaited(
                  Get.find<AppController>().syncNativeLoginHint(true));
            }
            // Lock-screen CallKit needs a fresh APNs VoIP token after reconnect.
            unawaited(VoipCallkitController.ensureVoipTokenUploaded());
          },
          onKickedOffline: kickedOffline,
          onUserTokenExpired: userTokenExpired,
          onUserTokenInvalid: userTokenInvalid,
        ),
      );
    } catch (e, s) {
      Logger.print('initOpenIM failed: $e $s');
      initialized = false;
    }

    try {
      OpenIM.iMManager
      ..setUploadLogsListener(
          OnUploadLogsListener(onUploadProgress: uploadLogsProgress))
      ..userManager.setUserListener(OnUserListener(
          onSelfInfoUpdated: (u) {
            selfInfoUpdated(u);

            userInfo.update((val) {
              val?.nickname = u.nickname;
              val?.faceURL = u.faceURL;

              val?.remark = u.remark;
              val?.ex = u.ex;
              val?.globalRecvMsgOpt = u.globalRecvMsgOpt;
            });
          },
          onUserStatusChanged: userStausChanged))
      ..messageManager.setAdvancedMsgListener(OnAdvancedMsgListener(
        onRecvC2CReadReceipt: recvC2CMessageReadReceipt,
        onRecvNewMessage: (msg) {
          if (_dispatchCallingMessage(msg)) return;
          recvNewMessage(msg);
        },
        onNewRecvMessageRevoked: recvMessageRevoked,
        onRecvOfflineNewMessage: (msg) {
          if (_dispatchCallingMessage(msg)) return;
          recvOfflineMessage(msg);
        },
        onRecvOnlineOnlyMessage: (msg) {
          _dispatchCallingMessage(msg);
        },
      ))
      ..messageManager.setMsgSendProgressListener(OnMsgSendProgressListener(
        onProgress: progressCallback,
      ))
      ..messageManager.setCustomBusinessListener(OnCustomBusinessListener(
        onRecvCustomBusinessMessage: recvCustomBusinessMessage,
      ))
      ..friendshipManager.setFriendshipListener(OnFriendshipListener(
        onBlackAdded: blacklistAdded,
        onBlackDeleted: blacklistDeleted,
        onFriendApplicationAccepted: friendApplicationAccepted,
        onFriendApplicationAdded: friendApplicationAdded,
        onFriendApplicationDeleted: friendApplicationDeleted,
        onFriendApplicationRejected: friendApplicationRejected,
        onFriendInfoChanged: friendInfoChanged,
        onFriendAdded: friendAdded,
        onFriendDeleted: friendDeleted,
      ))
      ..conversationManager.setConversationListener(OnConversationListener(
          onConversationChanged: conversationChanged,
          onNewConversation: newConversation,
          onTotalUnreadMessageCountChanged: totalUnreadMsgCountChanged,
          onInputStatusChanged: inputStateChanged,
          onSyncServerFailed: (reInstall) {
            imSdkStatus(IMSdkStatus.syncFailed, reInstall: reInstall ?? false);
          },
          onSyncServerFinish: (reInstall) {
            imSdkStatus(IMSdkStatus.syncEnded, reInstall: reInstall ?? false);
            if (Platform.isAndroid) {
              Permissions.request([Permission.systemAlertWindow]);
            }
          },
          onSyncServerStart: (reInstall) {
            imSdkStatus(IMSdkStatus.syncStart, reInstall: reInstall ?? false);
          },
          onSyncServerProgress: (progress) {
            imSdkStatus(IMSdkStatus.syncProgress, progress: progress);
          }))
      ..groupManager.setGroupListener(OnGroupListener(
        onGroupApplicationAccepted: groupApplicationAccepted,
        onGroupApplicationAdded: groupApplicationAdded,
        onGroupApplicationDeleted: groupApplicationDeleted,
        onGroupApplicationRejected: groupApplicationRejected,
        onGroupInfoChanged: groupInfoChanged,
        onGroupMemberAdded: groupMemberAdded,
        onGroupMemberDeleted: groupMemberDeleted,
        onGroupMemberInfoChanged: groupMemberInfoChanged,
        onJoinedGroupAdded: joinedGroupAdded,
        onJoinedGroupDeleted: joinedGroupDeleted,
      ));
    } catch (e, s) {
      Logger.print('initOpenIM listener setup failed: $e $s');
    }

    Logger().sdkIsInited = initialized;
    initializedSubject.sink.add(initialized);
  }

  /// Re-init SDK after switching to backup/primary entry.
  Future<void> reinitOpenIM() async {
    try {
      OpenIM.iMManager.unInitSDK();
    } catch (e, s) {
      Logger.print('unInitSDK: $e $s');
    }
    await initOpenIM();
  }

  /// HTTP layer already switched host — rebind IM SDK/WS to the new line.
  Future<void> _onHttpEndpointSwitched() async {
    if (_isActiveCallInProgress()) {
      Logger.print('defer IM rebind after HTTP failover: active call');
      return;
    }
    final now = DateTime.now();
    if (_lastFailoverAt != null &&
        now.difference(_lastFailoverAt!) < const Duration(seconds: 8)) {
      return;
    }
    if (_failoverInFlight) return;
    _failoverInFlight = true;
    try {
      _lastFailoverAt = now;
      HttpUtil.updateBaseUrl();
      await reinitOpenIM();
      final cert = DataSp.getLoginCertificate();
      if (cert != null &&
          cert.userID.isNotEmpty &&
          cert.imToken.isNotEmpty) {
        await login(cert.userID, cert.imToken);
      }
      Logger.print('IM rebound after HTTP endpoint switch → ${Config.serverIp}');
    } catch (e, s) {
      Logger.print('HTTP endpoint switch rebind failed: $e $s');
    } finally {
      _failoverInFlight = false;
    }
  }

  Future<void> _tryFailoverOnConnectFailed() async {
    if (_failoverInFlight || _isActiveCallInProgress()) {
      if (_isActiveCallInProgress()) {
        Logger.print('defer endpoint failover: active call');
      }
      return;
    }
    final now = DateTime.now();
    if (_lastFailoverAt != null &&
        now.difference(_lastFailoverAt!) < const Duration(seconds: 45)) {
      return;
    }
    _failoverInFlight = true;
    try {
      final current = Config.serverIp;
      final switched = await ServerEndpointSelector.failoverFrom(current);
      if (!switched) return;
      _lastFailoverAt = now;
      await reinitOpenIM();
      HttpUtil.updateBaseUrl();
      final cert = DataSp.getLoginCertificate();
      if (cert != null &&
          cert.userID.isNotEmpty &&
          cert.imToken.isNotEmpty) {
        await login(cert.userID, cert.imToken);
      }
    } catch (e, s) {
      Logger.print('endpoint failover failed: $e $s');
    } finally {
      _failoverInFlight = false;
    }
  }

  /// Best-effort relogin when the WS drops without a clean SDK callback.
  Future<void> _softReconnectAfterDisconnect() async {
    if (_reconnectInFlight || _failoverInFlight || _isActiveCallInProgress()) {
      if (_isActiveCallInProgress()) {
        Logger.print('defer soft reconnect: active call');
      }
      return;
    }
    final now = DateTime.now();
    if (_lastReconnectAt != null &&
        now.difference(_lastReconnectAt!) < const Duration(seconds: 15)) {
      return;
    }
    _reconnectInFlight = true;
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!OpenIM.iMManager.isLogined || _isActiveCallInProgress()) return;
      final status = imSdkStatusSubject.values.lastOrNull?.status;
      if (status == IMSdkStatus.connectionSucceeded) return;
      final cert = DataSp.getLoginCertificate();
      if (cert == null || cert.userID.isEmpty || cert.imToken.isEmpty) {
        return;
      }
      Logger.print('IM soft reconnect after disconnect');
      await login(cert.userID, cert.imToken);
      _lastReconnectAt = now;
    } catch (e, s) {
      Logger.print('IM soft reconnect failed: $e $s');
    } finally {
      _reconnectInFlight = false;
    }
  }

  Future login(String userID, String token) async {
    try {
      var user = await OpenIM.iMManager.login(
        userID: userID,
        token: token,
        defaultValue: () async => UserInfo(userID: userID),
      );
      userInfo = UserFullInfo.fromJson(user.toJson()).obs;
      _queryMyFullInfo();
      _queryAtAllTag();
    } catch (e, s) {
      Logger.print('e: $e  s:$s');
      await _handleLoginRepeatError(e);

      return Future.error(e, s);
    }
  }

  /// After IM sync / network restore / cold start:
  /// 1) clear CallKit/UI for rooms already cancel/hungup (callee was offline)
  /// 2) only then replay a still-pending invite
  Future<void> recoverPendingRtcInvitations() async {
    if (!SessionGuard.shouldNotify) return;
    if (_rtcRecoveryInFlight || !OpenIM.iMManager.isLogined) return;

    final now = DateTime.now();
    if (_lastRtcRecoveryAt != null &&
        now.difference(_lastRtcRecoveryAt!) < const Duration(seconds: 2)) {
      return;
    }
    _rtcRecoveryInFlight = true;
    _lastRtcRecoveryAt = now;
    try {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
        messageTypeList: [MessageType.custom],
        searchTimePeriod: 180,
        count: 300,
      );
      final messages = <Message>[];
      for (final item in result.searchResultItems ?? const []) {
        messages.addAll(item.messageList ?? const []);
      }
      messages.sort((a, b) => (a.sendTime ?? 0).compareTo(b.sendTime ?? 0));

      final nowMs = now.millisecondsSinceEpoch;
      final selfID = OpenIM.iMManager.userID;
      final pending = <String, ({SignalingInfo signaling, int sendTime})>{};
      final endedRooms = <String>{};
      final terminalAt = <String, int>{};

      for (final msg in messages) {
        final parsed = _parseCallingCustomMessage(msg);
        if (parsed == null) continue;
        final roomID = parsed.signaling.invitation?.roomID?.trim() ?? '';
        if (roomID.isEmpty) continue;
        final sendTime = msg.sendTime ?? 0;

        switch (parsed.customType) {
          case CustomMessageType.callingInvite:
            if (msg.sendID == selfID) break;
            if (endedRooms.contains(roomID)) break;
            if (sendTime > 0 && nowMs - sendTime > 60 * 1000) {
              endedRooms.add(roomID);
              pending.remove(roomID);
              break;
            }
            if (PackageBridge.isCallRoomEnded?.call(roomID) == true) {
              endedRooms.add(roomID);
              pending.remove(roomID);
              break;
            }
            pending[roomID] =
                (signaling: parsed.signaling, sendTime: sendTime);
            break;
          case CustomMessageType.callingReject:
          case CustomMessageType.callingCancel:
          case CustomMessageType.callingHungup:
            endedRooms.add(roomID);
            pending.remove(roomID);
            if (sendTime >= (terminalAt[roomID] ?? 0)) {
              terminalAt[roomID] = sendTime;
            }
            break;
          case CustomMessageType.callingAccept:
            // Accept alone does not keep a stale invite after later hungup.
            break;
        }
      }

      // Offline miss: caller hung up while we were dead — tear down zombies.
      await _reconcileStaleRtcCalls(
        endedRooms: endedRooms,
        pendingRoomIDs: pending.keys.toSet(),
      );

      if (_isActiveCallInProgress()) return;
      if (pending.isEmpty) return;

      SignalingInfo? latest;
      var latestTime = 0;
      for (final entry in pending.entries) {
        if (entry.value.sendTime >= latestTime) {
          latestTime = entry.value.sendTime;
          latest = entry.value.signaling;
        }
      }
      if (latest == null) return;

      Logger.print(
          'RTC recovery: replay pending invite room=${latest.invitation?.roomID}');
      receiveNewInvitation(latest);
    } catch (e, s) {
      Logger.print('recoverPendingRtcInvitations failed: $e $s');
    } finally {
      _rtcRecoveryInFlight = false;
    }
  }

  /// End CallKit / in-app call UI for rooms already terminated while offline.
  Future<void> _reconcileStaleRtcCalls({
    required Set<String> endedRooms,
    required Set<String> pendingRoomIDs,
  }) async {
    final voip = VoipCallkitController.toOrNull;
    final client = OpenIMLiveClient();
    final activeRoom = client.currentRoomID?.trim() ?? '';

    Future<void> endStale(String roomID, {required String reason}) async {
      Logger.print('RTC reconcile: end stale room=$roomID reason=$reason');
      PackageBridge.suppressCallKitEnded?.call(roomID);
      unawaited(voip?.markRoomEndedNative(roomID) ?? Future.value());
      await (voip?.endCall(roomID) ?? Future.value());
      final touchesLocal = activeRoom == roomID ||
          (client.isBusy && (activeRoom.isEmpty || activeRoom == roomID));
      if (touchesLocal) {
        beHangup(SignalingInfo(
          userID: OpenIM.iMManager.userID,
          invitation: InvitationInfo(roomID: roomID),
        ));
      }
    }

    for (final roomID in endedRooms) {
      await endStale(roomID, reason: 'terminal-signal');
    }

    // Lock-screen CallKit still up after reconnect, but invite is no longer pending.
    final callKitRooms = await voip?.activeCallRoomIDs() ?? const <String>[];
    for (final id in callKitRooms) {
      if (pendingRoomIDs.contains(id) && !endedRooms.contains(id)) continue;
      if (endedRooms.contains(id)) {
        // Already handled above.
        continue;
      }
      if (client.isBusy && client.currentRoomID?.trim() == id) {
        // Still in live media for this room and no terminal signal — keep.
        continue;
      }
      await endStale(id, reason: 'callkit-not-pending');
    }
  }

  ({int customType, SignalingInfo signaling})? _parseCallingCustomMessage(
      Message msg) {
    if (!msg.isCustomType) return null;
    final raw = msg.customElem?.data;
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final customType = map['customType'];
      if (customType is! int) return null;
      if (customType != CustomMessageType.callingInvite &&
          customType != CustomMessageType.callingAccept &&
          customType != CustomMessageType.callingReject &&
          customType != CustomMessageType.callingCancel &&
          customType != CustomMessageType.callingHungup) {
        return null;
      }
      final data = map['data'];
      if (data is! Map) return null;
      final signaling = SignalingInfo(
        invitation: InvitationInfo.fromJson(Map<String, dynamic>.from(data)),
      );
      signaling.userID = signaling.invitation?.inviterUserID;
      return (customType: customType, signaling: signaling);
    } catch (_) {
      return null;
    }
  }

  /// Returns true when the message is a calling signaling payload.
  bool _dispatchCallingMessage(Message msg) {
    // Never swallow invites when credentials exist — stuck suppress used to
    // return true here and kill all ring UI with no side effects.
    if (!SessionGuard.shouldNotify) {
      if (msg.isCallingSignalingType) {
        SessionGuard.markLoggedIn();
        if (!SessionGuard.shouldNotify) {
          return true;
        }
      } else {
        return false;
      }
    }
    if (!msg.isCustomType) return false;
    final raw = msg.customElem?.data;
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return false;
      final customType = _parseCallingCustomType(map['customType']);
      if (customType == null) return false;
      if (customType != CustomMessageType.callingInvite &&
          customType != CustomMessageType.callingAccept &&
          customType != CustomMessageType.callingReject &&
          customType != CustomMessageType.callingCancel &&
          customType != CustomMessageType.callingHungup) {
        return false;
      }

      final data = map['data'];
      if (data is! Map) return false;
      final signaling = SignalingInfo(
        invitation: InvitationInfo.fromJson(Map<String, dynamic>.from(data)),
      );
      signaling.userID = signaling.invitation?.inviterUserID;

      switch (customType) {
        case CustomMessageType.callingInvite:
          final sendTime = msg.sendTime ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          // Ignore stale invites after sync (already timed out).
          if (sendTime > 0 && now - sendTime > 60 * 1000) {
            return true;
          }
          // Own outbound invite echoed/synced must not open incoming UI.
          final selfID = OpenIM.iMManager.userID;
          final inviter = signaling.invitation?.inviterUserID;
          if (msg.sendID == selfID ||
              (inviter != null && inviter == selfID)) {
            return true;
          }
          final inviteRoomID = signaling.invitation?.roomID;
          if (PackageBridge.isCallRoomEnded?.call(inviteRoomID) == true) {
            Logger.print('ignore invite: room ended $inviteRoomID');
            return true;
          }
          // Busy / same-room: receiveNewInvitation no-ops; skip extra banners.
          final busy = OpenIMLiveClient().isBusy;
          receiveNewInvitation(signaling);
          if (busy) break;
          final voip = VoipCallkitController.toOrNull;
          if (voip != null && voip.ownsIncomingUi) {
            break;
          }
          if (Platform.isIOS) {
            // Foreground: in-app page; background: CallKit in live_controller.
          } else if (Get.isRegistered<AppController>()) {
            final app = Get.find<AppController>();
            // Android: CallKit full-screen owns Accept when registered.
            // Never stack a second notification Accept on top.
            if (voip == null &&
                app.isRunningBackground &&
                PackageBridge.rtcBridge?.hasCallOverlay != true) {
              app.showCallNotification(signaling);
            }
          }
          break;
        case CustomMessageType.callingAccept:
          inviteeAccepted(signaling);
          _clearCallNotification();
          // Callee only — caller outbound dial has no CallKit session.
          final inviter = signaling.invitation?.inviterUserID;
          if (inviter != OpenIM.iMManager.userID) {
            VoipCallkitController.toOrNull
                ?.setConnected(signaling.invitation?.roomID);
          }
          // Connected call: keep record, clear invite unread.
          unawaited(_markPeerConversationRead(signaling));
          break;
        case CustomMessageType.callingReject:
          PackageBridge.suppressCallKitEnded
              ?.call(signaling.invitation?.roomID);
          inviteeRejected(signaling);
          _clearCallNotification();
          unawaited(
              VoipCallkitController.toOrNull?.markRoomEndedNative(
                      signaling.invitation?.roomID) ??
                  Future.value());
          unawaited(
              VoipCallkitController.toOrNull?.endCall(
                      signaling.invitation?.roomID) ??
                  Future.value());
          break;
        case CustomMessageType.callingCancel:
          PackageBridge.suppressCallKitEnded
              ?.call(signaling.invitation?.roomID);
          // Block late VoIP invite re-show before ending CallKit.
          unawaited(
              VoipCallkitController.toOrNull?.markRoomEndedNative(
                      signaling.invitation?.roomID) ??
                  Future.value());
          invitationCancelled(signaling);
          _clearCallNotification();
          unawaited(
              VoipCallkitController.toOrNull?.endCall(
                      signaling.invitation?.roomID) ??
                  Future.value());
          break;
        case CustomMessageType.callingHungup:
          // Own hangup echo must not insert a second "通话时长 00:00" bubble.
          if (msg.sendID == OpenIM.iMManager.userID) {
            _clearCallNotification();
            unawaited(
                VoipCallkitController.toOrNull?.endCall(
                        signaling.invitation?.roomID) ??
                    Future.value());
            break;
          }
          PackageBridge.suppressCallKitEnded
              ?.call(signaling.invitation?.roomID);
          unawaited(
              VoipCallkitController.toOrNull?.markRoomEndedNative(
                      signaling.invitation?.roomID) ??
                  Future.value());
          // Prefer duration from peer hungup payload (wall clock on sender).
          final rawDur = data['duration'];
          final peerSec = rawDur is int
              ? rawDur
              : int.tryParse('$rawDur') ?? 0;
          beHangup(signaling, durationSec: peerSec);
          _clearCallNotification();
          unawaited(
              VoipCallkitController.toOrNull?.endCall(
                      signaling.invitation?.roomID) ??
                  Future.value());
          // Connected then hung up — record stays, unread must not.
          unawaited(_markPeerConversationRead(signaling));
          break;
      }
      return true;
    } catch (e, s) {
      Logger.print('dispatch calling message error: $e $s');
      return false;
    }
  }

  Future<void> _markPeerConversationRead(SignalingInfo signaling) async {
    try {
      final self = OpenIM.iMManager.userID;
      final inviter = signaling.invitation?.inviterUserID;
      final invitees = signaling.invitation?.inviteeUserIDList ?? const <String>[];
      String? peer;
      if (inviter != null && inviter != self) {
        peer = inviter;
      } else {
        for (final id in invitees) {
          if (id != self && id.isNotEmpty) {
            peer = id;
            break;
          }
        }
      }
      if (peer == null || peer.isEmpty) return;
      final conv = await OpenIM.iMManager.conversationManager.getOneConversation(
        sourceID: peer,
        sessionType: ConversationType.single,
      );
      final id = conv.conversationID;
      if (id.isEmpty) return;
      await OpenIM.iMManager.conversationManager
          .markConversationMessageAsRead(conversationID: id);
    } catch (e, s) {
      Logger.print('markPeerConversationRead failed: $e $s');
    }
  }

  int? _parseCallingCustomType(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw.trim());
    if (raw is double) return raw.toInt();
    return null;
  }

  void _clearCallNotification() {
    if (Get.isRegistered<AppController>()) {
      Get.find<AppController>().cancelCallNotification();
    }
  }

  Future logout() {
    return OpenIM.iMManager.logout();
  }

  void _queryAtAllTag() async {
    atAllTag = OpenIM.iMManager.conversationManager.atAllTag;
  }

  void _queryMyFullInfo() async {
    final data = await Apis.queryMyFullInfo();
    if (data is UserFullInfo) {
      userInfo.update((val) {
        val?.allowAddFriend = data.allowAddFriend;
        val?.allowBeep = data.allowBeep;
        val?.allowVibration = data.allowVibration;
        val?.nickname = data.nickname;
        val?.faceURL = data.faceURL;
        val?.phoneNumber = data.phoneNumber;
        val?.email = data.email;
        val?.birth = data.birth;
        val?.gender = data.gender;
        val?.signature = data.signature;
        val?.account = data.account;
      });
    }
  }

  _handleLoginRepeatError(e) async {
    if (e is PlatformException && (e.code == "13002" || e.code == '1507')) {
      await logout();
      await DataSp.removeLoginCertificate();
    }
  }
}
