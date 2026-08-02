import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:openim_live/openim_live.dart';

import '../im_callback.dart';
import 'app_controller.dart';

class IMController extends GetxController with IMCallback, OpenIMLive {
  late Rx<UserFullInfo> userInfo;
  late String atAllTag;

  @override
  void onClose() {
    super.close();
    onCloseLive();
    super.onClose();
  }

  @override
  void onInit() async {
    userInfo = UserFullInfo(userID: DataSp.userID ?? '').obs;
    super.onInit();
    onInitLive();
    WidgetsBinding.instance.addPostFrameCallback((_) => initOpenIM());
  }

  void initOpenIM() async {
    var initialized = false;
    try {
      initialized = await OpenIM.iMManager.initSDK(
        platformID: IMUtils.getPlatform(),
        apiAddr: Config.imApiUrl,
        wsAddr: Config.imWsUrl,
        dataDir: Config.cachePath,
        logLevel: Config.logLevel,
        logFilePath: Config.cachePath,
        listener: OnConnectListener(
          onConnecting: () {
            imSdkStatus(IMSdkStatus.connecting);
          },
          onConnectFailed: (code, error) {
            imSdkStatus(IMSdkStatus.connectionFailed);
          },
          onConnectSuccess: () {
            imSdkStatus(IMSdkStatus.connectionSucceeded);
          },
          onKickedOffline: kickedOffline,
          onUserTokenExpired: kickedOffline,
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

  /// Returns true when the message is a calling signaling payload.
  bool _dispatchCallingMessage(Message msg) {
    if (!msg.isCustomType) return false;
    final raw = msg.customElem?.data;
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return false;
      final customType = map['customType'];
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
          receiveNewInvitation(signaling);
          if (Get.isRegistered<AppController>()) {
            Get.find<AppController>().showCallNotification(signaling);
          }
          break;
        case CustomMessageType.callingAccept:
          inviteeAccepted(signaling);
          break;
        case CustomMessageType.callingReject:
          inviteeRejected(signaling);
          break;
        case CustomMessageType.callingCancel:
          invitationCancelled(signaling);
          break;
        case CustomMessageType.callingHungup:
          beHangup(signaling);
          break;
      }
      return true;
    } catch (e, s) {
      Logger.print('dispatch calling message error: $e $s');
      return false;
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
