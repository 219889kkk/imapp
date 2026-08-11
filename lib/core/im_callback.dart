import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import 'controller/app_controller.dart';

class GroupReadReceiptMsg {
  final String clientMsgID;
  final int seq;
  final int hasReadCount;
  final int unreadCount;
  final int groupMemberCount;

  GroupReadReceiptMsg({
    required this.clientMsgID,
    required this.seq,
    required this.hasReadCount,
    required this.unreadCount,
    required this.groupMemberCount,
  });

  factory GroupReadReceiptMsg.fromJson(Map<String, dynamic> json) =>
      GroupReadReceiptMsg(
        clientMsgID: json['clientMsgID'] ?? '',
        seq: json['seq'] ?? 0,
        hasReadCount: json['hasReadCount'] ?? 0,
        unreadCount: json['unreadCount'] ?? 0,
        groupMemberCount: json['groupMemberCount'] ?? 0,
      );
}

class GroupReadReceiptEvent {
  final String conversationID;
  final String groupID;
  final String readUserID;
  final int readTime;
  final List<GroupReadReceiptMsg> msgs;

  GroupReadReceiptEvent({
    required this.conversationID,
    required this.groupID,
    required this.readUserID,
    required this.readTime,
    required this.msgs,
  });

  factory GroupReadReceiptEvent.fromJson(Map<String, dynamic> json) =>
      GroupReadReceiptEvent(
        conversationID: json['conversationID'] ?? '',
        groupID: json['groupID'] ?? '',
        readUserID: json['readUserID'] ?? '',
        readTime: json['readTime'] ?? 0,
        msgs: ((json['msgs'] ?? []) as List)
            .whereType<Map>()
            .map((e) => GroupReadReceiptMsg.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

enum IMSdkStatus {
  connectionFailed,
  connecting,
  connectionSucceeded,
  syncStart,
  synchronizing,
  syncEnded,
  syncFailed,
  syncProgress,
}

enum KickoffType {
  kickedOffline,
  userTokenInvalid,
  userTokenExpired,
}

mixin IMCallback {
  final initLogic = Get.find<AppController>();

  Function(RevokedInfo info)? onRecvMessageRevoked;

  Function(List<ReadReceiptInfo> list)? onRecvC2CReadReceipt;

  Function(Message msg)? onRecvNewMessage;

  Function(Message msg)? onRecvOfflineMessage;

  Function(String msgId, int progress)? onMsgSendProgress;

  Function(BlacklistInfo u)? onBlacklistAdd;

  Function(BlacklistInfo u)? onBlacklistDeleted;

  Function(int current, int size)? onUploadProgress;

  final conversationAddedSubject = BehaviorSubject<List<ConversationInfo>>();

  final conversationChangedSubject = BehaviorSubject<List<ConversationInfo>>();

  final unreadMsgCountEventSubject = PublishSubject<int>();

  final friendApplicationChangedSubject =
      BehaviorSubject<FriendApplicationInfo>();

  final friendAddSubject = BehaviorSubject<FriendInfo>();

  final friendDelSubject = BehaviorSubject<FriendInfo>();

  final friendInfoChangedSubject = PublishSubject<FriendInfo>();

  final selfInfoUpdatedSubject = BehaviorSubject<UserInfo>();

  final userStatusChangedSubject = BehaviorSubject<UserStatusInfo>();

  final groupInfoUpdatedSubject = BehaviorSubject<GroupInfo>();

  final groupApplicationChangedSubject =
      BehaviorSubject<GroupApplicationInfo>();

  final initializedSubject = PublishSubject<bool>();

  final memberAddedSubject = BehaviorSubject<GroupMembersInfo>();

  final memberDeletedSubject = BehaviorSubject<GroupMembersInfo>();

  final memberInfoChangedSubject = PublishSubject<GroupMembersInfo>();

  final joinedGroupDeletedSubject = BehaviorSubject<GroupInfo>();

  final joinedGroupAddedSubject = BehaviorSubject<GroupInfo>();

  final onKickedOfflineSubject = PublishSubject<KickoffType>();

  final imSdkStatusSubject =
      ReplaySubject<({IMSdkStatus status, bool reInstall, int? progress})>();

  final imSdkStatusPublishSubject =
      PublishSubject<({IMSdkStatus status, bool reInstall, int? progress})>();

  final inputStateChangedSubject = PublishSubject<InputStatusChangedData>();

  final groupReadReceiptSubject = PublishSubject<GroupReadReceiptEvent>();

  void imSdkStatus(IMSdkStatus status,
      {bool reInstall = false, int? progress}) {
    imSdkStatusSubject
        .add((status: status, reInstall: reInstall, progress: progress));
    imSdkStatusPublishSubject
        .add((status: status, reInstall: reInstall, progress: progress));
  }

  void kickedOffline() {
    onKickedOfflineSubject.add(KickoffType.kickedOffline);
  }

  void userTokenExpired() {
    onKickedOfflineSubject.add(KickoffType.userTokenExpired);
  }

  void userTokenInvalid() {
    onKickedOfflineSubject.add(KickoffType.userTokenInvalid);
  }

  void selfInfoUpdated(UserInfo u) {
    selfInfoUpdatedSubject.addSafely(u);
  }

  void userStausChanged(UserStatusInfo u) {
    if (u.userID != null && (u.status == null || u.status == 0)) {
      LastOnlineCache.markOfflineNow(u.userID!);
    }
    userStatusChangedSubject.addSafely(u);
  }

  void uploadLogsProgress(int current, int size) {
    onUploadProgress?.call(current, size);
  }

  void recvMessageRevoked(RevokedInfo info) {
    onRecvMessageRevoked?.call(info);
  }

  void recvC2CMessageReadReceipt(List<ReadReceiptInfo> list) {
    onRecvC2CReadReceipt?.call(list);
  }

  void recvNewMessage(Message msg) {
    if (!SessionGuard.shouldNotify) return;
    initLogic.showNotification(msg);
    onRecvNewMessage?.call(msg);
  }

  void recvOfflineMessage(Message msg) {
    if (!SessionGuard.shouldNotify) return;
    initLogic.showNotification(msg);
    onRecvOfflineMessage?.call(msg);
  }

  void recvCustomBusinessMessage(String s) {
    try {
      dynamic detail = jsonDecode(s);
      if (detail is String) detail = jsonDecode(detail);
      if (detail is! Map) return;
      if (detail['key'] != 'groupReadReceipt') return;
      dynamic data = detail['data'];
      if (data is String) data = jsonDecode(data);
      if (data is! Map) return;
      groupReadReceiptSubject.addSafely(
          GroupReadReceiptEvent.fromJson(Map<String, dynamic>.from(data)));
    } catch (e, stack) {
      Logger.print('recvCustomBusinessMessage parse error: $e $stack');
    }
  }

  void progressCallback(String msgId, int progress) {
    onMsgSendProgress?.call(msgId, progress);
  }

  void blacklistAdded(BlacklistInfo u) {
    onBlacklistAdd?.call(u);
  }

  void blacklistDeleted(BlacklistInfo u) {
    onBlacklistDeleted?.call(u);
  }

  void friendApplicationAccepted(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendApplicationAdded(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
    final nickname = u.fromNickname ?? u.fromUserID ?? '';
    initLogic.showFriendApplicationNotification(nickname: nickname);
  }

  void friendApplicationDeleted(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendApplicationRejected(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendInfoChanged(FriendInfo u) {
    friendInfoChangedSubject.addSafely(u);
  }

  void friendAdded(FriendInfo u) {
    friendAddSubject.addSafely(u);
  }

  void friendDeleted(FriendInfo u) {
    friendDelSubject.addSafely(u);
  }

  void conversationChanged(List<ConversationInfo> list) {
    conversationChangedSubject.addSafely(list);
  }

  void newConversation(List<ConversationInfo> list) {
    conversationAddedSubject.addSafely(list);
  }

  void groupApplicationAccepted(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupApplicationAdded(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupApplicationDeleted(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupApplicationRejected(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupInfoChanged(GroupInfo info) {
    groupInfoUpdatedSubject.addSafely(info);
  }

  void groupMemberAdded(GroupMembersInfo info) {
    memberAddedSubject.add(info);
  }

  void groupMemberDeleted(GroupMembersInfo info) {
    memberDeletedSubject.add(info);
  }

  void groupMemberInfoChanged(GroupMembersInfo info) {
    memberInfoChangedSubject.add(info);
  }

  void joinedGroupAdded(GroupInfo info) {
    joinedGroupAddedSubject.add(info);
  }

  void joinedGroupDeleted(GroupInfo info) {
    joinedGroupDeletedSubject.add(info);
  }

  void totalUnreadMsgCountChanged(int count) {
    // Ignore SDK unread callbacks after logout / before login.
    if (SessionGuard.suppressNotifications ||
        DataSp.userID == null ||
        DataSp.userID!.isEmpty) {
      initLogic.clearBadgeForLoggedOut();
      unreadMsgCountEventSubject.addSafely(0);
      return;
    }
    initLogic.showBadge(count);
    unreadMsgCountEventSubject.addSafely(count);
  }

  void inputStateChanged(InputStatusChangedData status) {
    inputStateChangedSubject.addSafely(status);
  }

  void close() {
    initializedSubject.close();
    friendApplicationChangedSubject.close();
    friendAddSubject.close();
    friendDelSubject.close();
    friendInfoChangedSubject.close();
    selfInfoUpdatedSubject.close();
    groupInfoUpdatedSubject.close();
    conversationAddedSubject.close();
    conversationChangedSubject.close();
    memberAddedSubject.close();
    memberDeletedSubject.close();
    memberInfoChangedSubject.close();
    onKickedOfflineSubject.close();
    groupApplicationChangedSubject.close();
    imSdkStatusSubject.close();
    imSdkStatusPublishSubject.close();
    joinedGroupDeletedSubject.close();
    joinedGroupAddedSubject.close();
    groupReadReceiptSubject.close();
  }
}
