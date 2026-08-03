import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:common_utils/common_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:openim_live/openim_live.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../contacts/select_contacts/select_contacts_logic.dart';
import '../conversation/conversation_logic.dart';
import 'chat_message_prefetch_cache.dart';
import 'group_setup/group_member_list/group_member_list_logic.dart';

class ChatLogic extends SuperController {
  final imLogic = Get.find<IMController>();
  final appLogic = Get.find<AppController>();
  final conversationLogic = Get.find<ConversationLogic>();
  final cacheLogic = Get.find<CacheController>();

  final inputCtrl = ChatEmojiTextEditingController();
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  final refreshController = RefreshController();
  bool playOnce = false;

  final forceCloseToolbox = PublishSubject<bool>();
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  final quoteMessage = Rxn<Message>();
  final isMultiSelectMode = false.obs;
  final selectedMessages = <Message>[].obs;
  final atUserInfoMap = <String, AtUserInfo>{};
  bool _selectingAtMember = false;

  late ConversationInfo conversationInfo;
  Message? searchMessage;
  final nickname = ''.obs;
  final faceUrl = ''.obs;
  Timer? _debounce;
  final messageList = <Message>[].obs;
  final tempMessages = <Message>[];
  final scaleFactor = Config.textScaleFactor.obs;
  final background = "".obs;
  final memberUpdateInfoMap = <String, GroupMembersInfo>{};
  final groupMemberRoleLevel = 1.obs;
  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  List<GroupMembersInfo> ownerAndAdmin = [];

  final isInGroup = true.obs;
  final memberCount = 0.obs;
  final privateMessageList = <Message>[];
  final isInBlacklist = false.obs;

  final scrollingCacheMessageList = <Message>[];
  final announcement = ''.obs;
  final showAnnouncement = false.obs;
  late StreamSubscription conversationSub;
  late StreamSubscription memberAddSub;
  late StreamSubscription memberDelSub;
  late StreamSubscription joinedGroupAddedSub;
  late StreamSubscription joinedGroupDeletedSub;
  late StreamSubscription memberInfoChangedSub;
  late StreamSubscription groupInfoUpdatedSub;
  late StreamSubscription friendInfoChangedSub;
  StreamSubscription? userStatusChangedSub;
  StreamSubscription? selfInfoUpdatedSub;
  StreamSubscription? inputStatusSub;
  StreamSubscription? groupReadReceiptSub;

  late StreamSubscription connectionSub;
  final syncStatus = IMSdkStatus.syncEnded.obs;
  int? lastMinSeq;

  final showCallingMember = false.obs;

  bool _isReceivedMessageWhenSyncing = false;
  bool _isStartSyncing = false;
  bool _isFirstLoad = true;
  bool hasMoreHistory = true;
  bool shouldAutoLoadInitialMessages = true;
  Timer? _typingTimer;

  final copyTextMap = <String?, String?>{};

  String? groupOwnerID;

  final _pageSize = 40;

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get rtcIsBusy => rtcBridge?.hasConnection == true;

  String? get userID => conversationInfo.userID;

  String? get groupID => conversationInfo.groupID;

  bool get isSingleChat => null != userID && userID!.trim().isNotEmpty;

  bool get isGroupChat => null != groupID && groupID!.trim().isNotEmpty;

  String get memberStr => isSingleChat ? "" : "($memberCount)";

  final typingStatus = ''.obs;
  final onlineStatusDesc = ''.obs;

  String? get senderName => isSingleChat
      ? OpenIM.iMManager.userInfo.nickname
      : groupMembersInfo?.nickname;

  bool get isAdminOrOwner =>
      groupMemberRoleLevel.value == GroupRoleLevel.admin ||
      groupMemberRoleLevel.value == GroupRoleLevel.owner;

  final directionalUsers = <GroupMembersInfo>[].obs;

  bool isCurrentChat(Message message) {
    var senderId = message.sendID;
    var receiverId = message.recvID;
    var groupId = message.groupID;

    var isCurSingleChat = message.isSingleChat &&
        isSingleChat &&
        (senderId == userID ||
            senderId == OpenIM.iMManager.userID && receiverId == userID);
    var isCurGroupChat =
        message.isGroupChat && isGroupChat && groupID == groupId;
    return isCurSingleChat || isCurGroupChat;
  }

  void scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      scrollController.jumpTo(0);
    });
  }

  Future<List<Message>> searchMediaMessage() async {
    final messageList = await OpenIM.iMManager.messageManager
        .searchLocalMessages(
            conversationID: conversationInfo.conversationID,
            messageTypeList: [MessageType.picture, MessageType.video],
            count: 500);
    return messageList.searchResultItems?.first.messageList?.reversed
            .toList() ??
        [];
  }

  @override
  void onReady() {
    _resetGroupAtType();
    _clearUnreadCount();
    _initChatConfigAfterFirstFrame();
    _subscribePeerOnlineStatus();

    scrollController.addListener(() {
      focusNode.unfocus();
    });
    super.onReady();
  }

  void _subscribePeerOnlineStatus() async {
    if (!isSingleChat || userID == null || userID!.isEmpty) return;

    userStatusChangedSub?.cancel();
    userStatusChangedSub = imLogic.userStatusChangedSubject.listen((u) {
      if (u.userID == userID) {
        _updateOnlineStatusDesc(u.status == 1);
      }
    });

    try {
      final list =
          await OpenIM.iMManager.userManager.subscribeUsersStatus([userID!]);
      final info = list.firstWhereOrNull((e) => e.userID == userID);
      if (info != null) {
        _updateOnlineStatusDesc(info.status == 1);
        return;
      }
    } catch (_) {}

    final list = await Apis.getUsersOnlineStatus(userIDList: [userID!]);
    _updateOnlineStatusDesc(list.firstOrNull?.isOnline == true);
  }

  void _updateOnlineStatusDesc(bool isOnline) {
    if (isOnline) {
      onlineStatusDesc.value = StrRes.online;
      return;
    }
    final last = LastOnlineCache.format(userID!);
    onlineStatusDesc.value = last == null
        ? StrRes.offline
        : sprintf(StrRes.lastOnlineTime, [last]);
  }

  @override
  void onInit() {
    var arguments = Get.arguments;
    conversationInfo = arguments['conversationInfo'];
    searchMessage = arguments['searchMessage'];
    _applyPrefetchedMessages(
      arguments['prefetchedMessages'],
      arguments['prefetchedMessagesIsEnd'] == true,
    );
    nickname.value = conversationInfo.showName ?? '';
    faceUrl.value = conversationInfo.faceURL ?? '';
    appLogic.viewingConversationID = conversationInfo.conversationID;
    _setSdkSyncDataListener();

    conversationSub = imLogic.conversationChangedSubject.listen((value) {
      final obj = value.firstWhereOrNull(
          (e) => e.conversationID == conversationInfo.conversationID);

      if (obj != null) {
        conversationInfo = obj;
      }
    });

    imLogic.onRecvNewMessage = (Message message) async {
      if (isCurrentChat(message)) {
        if (message.contentType == MessageType.typing) {
          if (isSingleChat) {
            _showTypingStatus();
          } else if (message.sendID != OpenIM.iMManager.userID) {
            final nickname = _resolveTypingNickname(message.sendID);
            _showTypingStatus(nickname: nickname);
          }
        } else if (!message.isCallingSignalingType) {
          if (!messageList.contains(message) &&
              !scrollingCacheMessageList.contains(message)) {
            _isReceivedMessageWhenSyncing = true;
            if (scrollController.offset != 0) {
              scrollingCacheMessageList.add(message);
            } else {
              messageList.add(message);
              scrollBottom();
            }
          }
        }
      }
    };

    inputStatusSub = imLogic.inputStateChangedSubject.listen((data) {
      if (data.conversationID != conversationInfo.conversationID) return;
      if (isSingleChat) {
        if (data.userID == userID) _showTypingStatus();
      } else {
        if (data.userID == OpenIM.iMManager.userID) return;
        final nickname = _resolveTypingNickname(data.userID);
        _showTypingStatus(nickname: nickname);
      }
    });

    imLogic.onRecvMessageRevoked = (RevokedInfo info) {
      handleMessageRevoked(info);
    };

    imLogic.onRecvC2CReadReceipt = (List<ReadReceiptInfo> list) {
      try {
        for (var readInfo in list) {
          if (readInfo.userID == userID) {
            for (var e in messageList) {
              if (readInfo.msgIDList?.contains(e.clientMsgID) == true) {
                e.isRead = true;
                e.hasReadTime = _timestamp;
              }
            }
          }
        }
        messageList.refresh();
      } catch (e) {}
    };

    groupReadReceiptSub = imLogic.groupReadReceiptSubject.listen((event) {
      if (!isGroupChat ||
          event.conversationID != conversationInfo.conversationID) {
        return;
      }
      var changed = false;
      for (final readInfo in event.msgs) {
        if (readInfo.clientMsgID.isEmpty) continue;
        final message = messageList
            .firstWhereOrNull((e) => e.clientMsgID == readInfo.clientMsgID);
        if (message == null || message.sendID != OpenIM.iMManager.userID) {
          continue;
        }
        message.attachedInfoElem ??= AttachedInfoElem();
        message.attachedInfoElem!.groupHasReadInfo = GroupHasReadInfo(
          hasReadCount: readInfo.hasReadCount,
          unreadCount: readInfo.unreadCount,
          groupMemberCount: readInfo.groupMemberCount,
        );
        changed = true;
      }
      if (changed) {
        messageList.refresh();
      }
    });

    joinedGroupAddedSub = imLogic.joinedGroupAddedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = true;
        _queryGroupInfo();
      }
    });

    joinedGroupDeletedSub = imLogic.joinedGroupDeletedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberAddSub = imLogic.memberAddedSubject.listen((info) {
      var groupId = info.groupID;
      if (groupId == groupID) {
        _putMemberInfo([info]);
      }
    });

    memberDelSub = imLogic.memberDeletedSubject.listen((info) {
      if (info.groupID == groupID && info.userID == OpenIM.iMManager.userID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((info) {
      if (info.groupID == groupID) {
        if (info.userID == OpenIM.iMManager.userID) {
          groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
          groupMembersInfo = info;
          ();
        }
        _putMemberInfo([info]);

        final index = ownerAndAdmin
            .indexWhere((element) => element.userID == info.userID);
        if (info.roleLevel == GroupRoleLevel.member) {
          if (index > -1) {
            ownerAndAdmin.removeAt(index);
          }
        } else if (info.roleLevel == GroupRoleLevel.admin ||
            info.roleLevel == GroupRoleLevel.owner) {
          if (index == -1) {
            ownerAndAdmin.add(info);
          } else {
            ownerAndAdmin[index] = info;
          }
        }

        for (var msg in messageList) {
          if (msg.sendID == info.userID) {
            if (msg.isNotificationType) {
              final map = json.decode(msg.notificationElem!.detail!);
              final ntf = GroupNotification.fromJson(map);
              ntf.opUser?.nickname = info.nickname;
              ntf.opUser?.faceURL = info.faceURL;
              msg.notificationElem?.detail = jsonEncode(ntf);
            } else {
              msg.senderFaceUrl = info.faceURL;
              msg.senderNickname = info.nickname;
            }
          }
        }

        messageList.refresh();
      }
    });

    groupInfoUpdatedSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (groupID == value.groupID) {
        groupInfo = value;
        nickname.value = value.groupName ?? '';
        faceUrl.value = value.faceURL ?? '';
        memberCount.value = value.memberCount ?? 0;
        _syncAnnouncement();
      }
    });

    friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (userID == value.userID) {
        nickname.value = value.getShowName();
        faceUrl.value = value.faceURL ?? '';

        for (var msg in messageList) {
          if (msg.sendID == value.userID) {
            msg.senderFaceUrl = value.faceURL;
            msg.senderNickname = value.nickname;
          }
        }

        messageList.refresh();
      }
    });

    selfInfoUpdatedSub = imLogic.selfInfoUpdatedSubject.listen((value) {
      for (var msg in messageList) {
        if (msg.sendID == value.userID) {
          msg.senderFaceUrl = value.faceURL;
          msg.senderNickname = value.nickname;
        }
      }

      messageList.refresh();
    });

    inputCtrl.addListener(() {
      sendTypingMsg(focus: true);
      _maybeSelectAtMember();
      if (_debounce?.isActive ?? false) _debounce?.cancel();

      _debounce = Timer(1.seconds, () {
        sendTypingMsg(focus: false);
      });
    });

    focusNode.addListener(() {
      focusNodeChanged(focusNode.hasFocus);
    });

    imLogic.onSignalingMessage = (value) {
      if (value.userID == userID) {
        messageList.add(value.message);
        scrollBottom();
      }
    };

    super.onInit();
  }

  Future chatSetup() => isSingleChat
      ? AppNavigator.startChatSetup(conversationInfo: conversationInfo)
      : AppNavigator.startGroupChatSetup(conversationInfo: conversationInfo);

  void _putMemberInfo(List<GroupMembersInfo>? list) {
    list?.forEach((member) {
      memberUpdateInfoMap[member.userID!] = member;
    });

    messageList.refresh();
  }

  void sendTextMsg() async {
    var content = IMUtils.safeTrim(inputCtrl.text);
    if (content.isEmpty) return;
    final quoted = quoteMessage.value;
    final atUserInfoList = _validAtUserInfoList(content);
    Message message;
    if (atUserInfoList.isNotEmpty) {
      message = await OpenIM.iMManager.messageManager.createTextAtMessage(
        text: content,
        atUserIDList: atUserInfoList.map((e) => e.atUserID!).toList(),
        atUserInfoList: atUserInfoList,
        quoteMessage: quoted,
      );
    } else {
      message = quoted == null
          ? await OpenIM.iMManager.messageManager.createTextMessage(
              text: content,
            )
          : await OpenIM.iMManager.messageManager.createQuoteMessage(
              text: content,
              quoteMsg: quoted,
            );
    }

    _sendMessage(message);
  }

  List<AtUserInfo> _validAtUserInfoList(String content) => atUserInfoMap.values
      .where((e) =>
          e.atUserID?.isNotEmpty == true &&
          e.groupNickname?.isNotEmpty == true &&
          content.contains('@${e.groupNickname}'))
      .toList();

  Future sendPicture({required String path, bool sendNow = true}) async {
    final file = await IMUtils.compressImageAndGetFile(File(path));

    var message =
        await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file!.path,
    );

    if (sendNow) {
      return _sendMessage(message);
    } else {
      messageList.add(message);
      tempMessages.add(message);
    }
  }

  void onTapFile() async {
    try {
      forceCloseToolbox.addSafely(true);
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final file = result?.files.single;
      final path = file?.path;
      if (path == null || path.isEmpty) return;
      await sendFile(path: path, fileName: file?.name ?? path.split('/').last);
    } catch (e) {
      IMViews.showToast(e.toString());
    }
  }

  Future<void> sendFile({
    required String path,
    required String fileName,
  }) async {
    final message =
        await OpenIM.iMManager.messageManager.createFileMessageFromFullPath(
      filePath: path,
      fileName: fileName,
    );
    await _sendMessage(message);
  }

  Future<void> sendVideo({
    required String videoPath,
    required String videoType,
    required int duration,
    required String snapshotPath,
    bool sendNow = true,
  }) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists() || await videoFile.length() == 0) {
        IMViews.showToast(StrRes.networkError);
        return;
      }
      final snapshotFile = File(snapshotPath);
      if (!await snapshotFile.exists()) {
        IMViews.showToast(StrRes.networkError);
        return;
      }

      final videoName = videoPath.substring(videoPath.lastIndexOf('/') + 1);
      final snapshotName =
          snapshotPath.substring(snapshotPath.lastIndexOf('/') + 1);
      final videoUrl = await HttpUtil.uploadFileForMinio(
        path: videoPath,
        fileName: videoName,
        fileType: 2,
      );
      final snapshotUrl = await HttpUtil.uploadFileForMinio(
        path: snapshotPath,
        fileName: snapshotName,
        fileType: 1,
      );

      final message =
          await OpenIM.iMManager.messageManager.createVideoMessageByURL(
        videoElem: VideoElem(
          videoPath: videoPath,
          videoUUID: videoName,
          videoUrl: videoUrl,
          videoType: videoType,
          videoSize: await videoFile.length(),
          duration: duration,
          snapshotPath: snapshotPath,
          snapshotUUID: snapshotName,
          snapshotUrl: snapshotUrl,
          snapshotSize: await snapshotFile.length(),
        ),
      );
      if (sendNow) {
        await _sendMessage(message, sendNotOss: true);
      } else {
        messageList.add(message);
        tempMessages.add(message);
      }
    } catch (e, s) {
      Logger.print('sendVideo error: $e $s');
      final detail = '$e';
      final message = detail.contains('minio_upload') ||
              detail.contains('token') ||
              detail.contains('Connection')
          ? detail
          : '${StrRes.networkError} ($detail)';
      IMViews.showToast(
        message.length > 120 ? message.substring(0, 120) : message,
      );
    }
  }

  Future<void> sendVoice({
    required String path,
    required int duration,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        IMViews.showToast(StrRes.voiceRecordFailed);
        return;
      }
      final fileName = path.substring(path.lastIndexOf("/") + 1);
      final sourceUrl = await HttpUtil.uploadFileForMinio(
        path: path,
        fileName: fileName,
      );
      final message =
          await OpenIM.iMManager.messageManager.createSoundMessageByURL(
        soundElem: SoundElem(
          uuid: fileName,
          soundPath: path,
          sourceUrl: sourceUrl,
          dataSize: await file.length(),
          duration: duration,
        ),
      );
      await _sendMessage(message, sendNotOss: true);
    } catch (e, s) {
      Logger.print('sendVoice error: $e $s');
      final detail = '$e';
      final message = detail.contains('minio_upload') ||
              detail.contains('token') ||
              detail.contains('Connection')
          ? detail
          : '${StrRes.networkError} ($detail)';
      IMViews.showToast(
        message.length > 120 ? message.substring(0, 120) : message,
      );
    }
  }

  Future<void> sendForwardRemarkMsg(
    String content, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );
    await _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future<void> sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    await _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future<void> sendMergeForwardMsg(
    List<Message> messages, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createMergerMessage(
      messageList: messages,
      title: '${nickname.value}${StrRes.chatRecord}',
      summaryList: messages.take(4).map(IMUtils.createSummary).toList(),
    );
    await _sendMessage(message, userId: userId, groupId: groupId);
  }

  void showMessageActionSheet(Message message) {
    if (message.isNotificationType || message.status == MessageStatus.sending) {
      return;
    }

    final actions = <_MessageActionInfo>[
      if (_canCopyMessage(message))
        _MessageActionInfo(StrRes.menuCopy, () => copyMessage(message)),
      _MessageActionInfo(StrRes.menuReply, () => quoteReplyMessage(message)),
      _MessageActionInfo(StrRes.menuForward, () => forwardMessage(message)),
      _MessageActionInfo(StrRes.menuMulti, () => enterMultiSelectMode(message)),
      _MessageActionInfo(StrRes.menuDel, () => deleteMessage(message)),
      if (_canRevokeMessage(message))
        _MessageActionInfo(StrRes.menuRevoke, () => revokeMessage(message)),
    ];

    Get.bottomSheet(
      SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...actions.map(_buildMessageActionItem),
              Container(height: 8, color: Styles.groupedSeparator),
              _buildMessageActionItem(
                _MessageActionInfo(StrRes.cancel, () => Get.back()),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildMessageActionItem(_MessageActionInfo action) => InkWell(
        onTap: () {
          Get.back();
          action.onTap();
        },
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(action.label, style: Styles.ts_0C1C33_17sp),
        ),
      );

  bool _canCopyMessage(Message message) =>
      message.contentType == MessageType.text ||
      message.contentType == MessageType.atText ||
      message.contentType == MessageType.quote;

  bool _canRevokeMessage(Message message) =>
      message.sendID == OpenIM.iMManager.userID &&
      message.status == MessageStatus.succeeded &&
      !isExceed24H(message);

  bool canSelectMessage(Message message) =>
      !message.isNotificationType && message.status == MessageStatus.succeeded;

  bool isSelectedMessage(Message message) =>
      selectedMessages.any((e) => e.clientMsgID == message.clientMsgID);

  void enterMultiSelectMode(Message message) {
    if (!canSelectMessage(message)) return;
    isMultiSelectMode.value = true;
    selectedMessages.clear();
    selectedMessages.add(message);
    forceCloseToolbox.addSafely(true);
    focusNode.unfocus();
  }

  void exitMultiSelectMode() {
    isMultiSelectMode.value = false;
    selectedMessages.clear();
  }

  void toggleSelectedMessage(Message message) {
    if (!canSelectMessage(message)) return;
    final index = selectedMessages
        .indexWhere((e) => e.clientMsgID == message.clientMsgID);
    if (index >= 0) {
      selectedMessages.removeAt(index);
    } else {
      if (selectedMessages.length >= 20) {
        IMViews.showToast(StrRes.forwardMaxCountHint);
        return;
      }
      selectedMessages.add(message);
    }
  }

  List<Message> get orderedSelectedMessages => messageList
      .where((message) => selectedMessages
          .any((selected) => selected.clientMsgID == message.clientMsgID))
      .toList();

  String? get quoteContent {
    final message = quoteMessage.value;
    if (message == null) return null;
    final sender = message.senderNickname ?? StrRes.you;
    return '$sender: ${IMUtils.parseMsg(message)}';
  }

  void quoteReplyMessage(Message message) {
    quoteMessage.value = message;
    focusNode.requestFocus();
  }

  void clearQuoteMessage() {
    quoteMessage.value = null;
  }

  void _maybeSelectAtMember() {
    if (_selectingAtMember || !isGroupChat || !inputCtrl.text.endsWith('@')) {
      return;
    }
    selectAtMember();
  }

  Future<void> selectAtMember() async {
    if (_selectingAtMember) return;
    _selectingAtMember = true;
    try {
      final info = await _ensureGroupInfo();
      if (info == null) return;
      final member = await AppNavigator.startSearchGroupMember(
        groupInfo: info,
        opType: GroupMemberOpType.at,
      );
      if (member is GroupMembersInfo && member.userID?.isNotEmpty == true) {
        final nickname = member.nickname?.isNotEmpty == true
            ? member.nickname!
            : member.userID!;
        final prefix = inputCtrl.text.substring(0, inputCtrl.text.length - 1);
        inputCtrl.text = '$prefix@$nickname ';
        inputCtrl.selection = TextSelection.collapsed(
          offset: inputCtrl.text.length,
        );
        atUserInfoMap[member.userID!] = AtUserInfo(
          atUserID: member.userID,
          groupNickname: nickname,
        );
      }
    } finally {
      _selectingAtMember = false;
    }
  }

  Future<GroupInfo?> _ensureGroupInfo() async {
    if (groupInfo != null) return groupInfo;
    if (!isGroupChat) return null;
    final list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID!],
    );
    groupInfo = list.firstOrNull;
    return groupInfo;
  }

  void copyMessage(Message message) {
    final text = copyTextMap[message.clientMsgID] ??
        message.textElem?.content ??
        message.atTextElem?.text ??
        message.quoteElem?.text;
    if (text?.isNotEmpty == true) {
      IMUtils.copy(text: text!);
    }
  }

  void deleteMessage(Message message) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () =>
          OpenIM.iMManager.messageManager.deleteMessageFromLocalAndSvr(
        conversationID: conversationInfo.conversationID,
        clientMsgID: message.clientMsgID!,
      ),
    );
    messageList.removeWhere((e) => e.clientMsgID == message.clientMsgID);
  }

  void revokeMessage(Message message) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: conversationInfo.conversationID,
        clientMsgID: message.clientMsgID!,
      ),
    );
    messageList.removeWhere((e) => e.clientMsgID == message.clientMsgID);
  }

  void handleMessageRevoked(RevokedInfo info) {
    final clientMsgID = info.clientMsgID;
    if (clientMsgID == null) return;
    messageList.removeWhere((e) => e.clientMsgID == clientMsgID);
    scrollingCacheMessageList.removeWhere((e) => e.clientMsgID == clientMsgID);
    selectedMessages.removeWhere((e) => e.clientMsgID == clientMsgID);
    if (quoteMessage.value?.clientMsgID == clientMsgID) {
      clearQuoteMessage();
    }
  }

  void forwardMessage(Message message) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: IMUtils.parseMsg(message),
    );
    if (result is Map) {
      final checkedList = result['checkedList'];
      if (checkedList is Iterable) {
        for (var info in checkedList) {
          final userID = IMUtils.convertCheckedToUserID(info);
          final groupID = IMUtils.convertCheckedToGroupID(info);
          await sendForwardMsg(message, userId: userID, groupId: groupID);
        }
      }
    }
  }

  void forwardSelectedMessages() async {
    final messages = orderedSelectedMessages;
    if (messages.isEmpty) {
      return;
    }
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: sprintf(StrRes.mergeForwardHint, [messages.length]),
    );
    if (result is Map) {
      final checkedList = result['checkedList'];
      if (checkedList is Iterable) {
        for (var info in checkedList) {
          final userID = IMUtils.convertCheckedToUserID(info);
          final groupID = IMUtils.convertCheckedToGroupID(info);
          await sendMergeForwardMsg(messages, userId: userID, groupId: groupID);
        }
        exitMultiSelectMode();
      }
    }
  }

  void sendTypingMsg({bool focus = false}) async {
    OpenIM.iMManager.conversationManager.changeInputStates(
        conversationID: conversationInfo.conversationID, focus: focus);
  }

  void _showTypingStatus({String? nickname}) {
    typingStatus.value =
        nickname == null ? StrRes.typing : '$nickname ${StrRes.typing}';
    _typingTimer?.cancel();
    _typingTimer = Timer(3.seconds, () {
      typingStatus.value = '';
    });
  }

  String? _resolveTypingNickname(String? userID) {
    if (userID == null) return null;
    final member = memberUpdateInfoMap[userID];
    return member?.nickname?.isNotEmpty == true ? member!.nickname : userID;
  }

  void sendCarte({
    required String userID,
    String? nickname,
    String? faceURL,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCardMessage(
      userID: userID,
      nickname: nickname!,
      faceURL: faceURL,
    );
    _sendMessage(message);
  }

  void onTapCarte() async {
    forceCloseToolbox.addSafely(true);
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.carte,
    );
    if (result is UserInfo) {
      sendCarte(
        userID: result.userID!,
        nickname: result.nickname,
        faceURL: result.faceURL,
      );
    }
  }

  void onTapLocation() async {
    forceCloseToolbox.addSafely(true);
    final result = await Get.to<LocationPickerResult>(
      () => const LocationPickerView(),
    );
    if (result != null) {
      final message =
          await OpenIM.iMManager.messageManager.createLocationMessage(
        latitude: result.latitude,
        longitude: result.longitude,
        description: result.description,
      );
      _sendMessage(message);
    }
  }

  void sendCustomMsg({
    required String data,
    required String extension,
    required String description,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    _sendMessage(message);
  }

  Future _sendMessage(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
    bool sendNotOss = false,
  }) {
    log('send : ${json.encode(message)}');
    userId = IMUtils.emptyStrToNull(userId);
    groupId = IMUtils.emptyStrToNull(groupId);
    if (null == userId && null == groupId ||
        userId == userID && userId != null ||
        groupId == groupID && groupId != null) {
      if (addToUI) {
        messageList.add(message);
        scrollBottom();
      }
    }
    Logger.print('uid:$userID userId:$userId gid:$groupID groupId:$groupId');
    _reset(message);
    bool useOuterValue = null != userId || null != groupId;

    final recvUserID = useOuterValue ? userId : userID;
    message.recvID = recvUserID;

    final sendFuture = sendNotOss
        ? OpenIM.iMManager.messageManager.sendMessageNotOss(
            message: message,
            userID: recvUserID,
            groupID: useOuterValue ? groupId : groupID,
            offlinePushInfo: Config.offlinePushInfo,
          )
        : OpenIM.iMManager.messageManager.sendMessage(
            message: message,
            userID: recvUserID,
            groupID: useOuterValue ? groupId : groupID,
            offlinePushInfo: Config.offlinePushInfo,
          );

    return sendFuture
        .then((value) => _sendSucceeded(message, value))
        .catchError(
            (error, _) => _senFailed(message, groupId, userId, error, _))
        .whenComplete(() => _completed());
  }

  void _sendSucceeded(Message oldMsg, Message newMsg) {
    Logger.print('message send success----');
    oldMsg.update(newMsg);
    _ensureGroupReadInfo(oldMsg);
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: oldMsg.clientMsgID!,
      value: true,
    ));
  }

  void _ensureGroupReadInfo(Message message) {
    if (!isGroupChat ||
        message.sendID != OpenIM.iMManager.userID ||
        message.status != MessageStatus.succeeded ||
        message.isNotificationType ||
        message.contentType == MessageType.typing) {
      return;
    }
    message.attachedInfoElem ??= AttachedInfoElem();
    final current = message.attachedInfoElem?.groupHasReadInfo;
    final hasValidCount =
        (current?.hasReadCount ?? 0) > 0 || (current?.unreadCount ?? 0) > 0;
    if (hasValidCount) return;
    final fallbackTotal = (current?.groupMemberCount ?? 0) > 0
        ? current!.groupMemberCount! - 1
        : 0;
    final total = memberCount.value > 0 ? memberCount.value - 1 : fallbackTotal;
    message.attachedInfoElem!.groupHasReadInfo = GroupHasReadInfo(
      hasReadCount: 0,
      unreadCount: total,
      hasReadUserIDList: const [],
      groupMemberCount: total,
    );
  }

  void _senFailed(
      Message message, String? groupId, String? userId, error, stack) async {
    Logger.print(
        'message send failed userID: $userId groupId:$groupId, catch error :$error  $stack');
    message.status = MessageStatus.failed;
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: false,
    ));
    if (error is PlatformException) {
      int code = int.tryParse(error.code) ?? 0;
      if (isSingleChat) {
        int? customType;
        if (code == SDKErrorCode.hasBeenBlocked) {
          customType = CustomMessageType.blockedByFriend;
        } else if (code == SDKErrorCode.notFriend) {
          customType = CustomMessageType.deletedByFriend;
        }
        if (null != customType) {
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(type: customType))
            ..status = 2
            ..isRead = true;
          if (userId != null) {
            if (userId == userID) {
              messageList.add(hintMessage);
            }
          } else {
            messageList.add(hintMessage);
          }
          OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
            message: hintMessage,
            receiverID: userId ?? userID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      } else {
        if ((code == SDKErrorCode.userIsNotInGroup ||
                code == SDKErrorCode.groupDisbanded) &&
            null == groupId) {
          final status = groupInfo?.status;
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(
                  type: status == 2
                      ? CustomMessageType.groupDisbanded
                      : CustomMessageType.removedFromGroup))
            ..status = 2
            ..isRead = true;
          messageList.add(hintMessage);
          OpenIM.iMManager.messageManager.insertGroupMessageToLocalStorage(
            message: hintMessage,
            groupID: groupID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      }
    }
  }

  void _reset(Message message) {
    if (message.contentType == MessageType.text ||
        message.contentType == MessageType.quote ||
        message.contentType == MessageType.atText) {
      inputCtrl.clear();
      clearQuoteMessage();
      atUserInfoMap.clear();
    }
  }

  void _completed() {
    messageList.refresh();
  }

  void markMessageAsRead(Message message, bool visible) async {
    Logger.print('markMessageAsRead: ${message.textElem?.content}, $visible');
    if (visible &&
        message.contentType! < 1000 &&
        message.contentType! != MessageType.voice) {
      var data = IMUtils.parseCustomMessage(message);
      if (null != data && data['viewType'] == CustomMessageType.call) {
        Logger.print('markMessageAsRead: call message $data');
        return;
      }
      _markMessageAsRead(message);
    }
  }

  _markMessageAsRead(Message message) async {
    if (!message.isRead! && message.sendID != OpenIM.iMManager.userID) {
      try {
        Logger.print(
            'mark conversation message as read：${message.clientMsgID!} ${message.isRead}');
        await OpenIM.iMManager.conversationManager
            .markConversationMessageAsRead(
                conversationID: conversationInfo.conversationID);
      } catch (e) {
        Logger.print(
            'failed to send group message read receipt： ${message.clientMsgID} ${message.isRead}');
      } finally {
        message.isRead = true;
        message.hasReadTime = _timestamp;
        messageList.refresh();
      }
    }
  }

  _clearUnreadCount() {
    if (conversationInfo.unreadCount > 0) {
      OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
          conversationID: conversationInfo.conversationID);
    }
  }

  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  void onTapAlbum() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(Get.context!,
        pickerConfig: AssetPickerConfig(
            sortPathsByModifiedDate: true,
            filterOptions: PMFilter.defaultValue(containsPathModified: true),
            selectPredicate: (_, entity, isSelected) async {
              if (entity.type == AssetType.image) {
                if (await allowSendImageType(entity)) {
                  return true;
                }

                IMViews.showToast(StrRes.supportsTypeHint);

                return false;
              }

              if (entity.videoDuration > const Duration(seconds: 5 * 60)) {
                IMViews.showToast(
                    sprintf(StrRes.selectVideoLimit, [5]) + StrRes.minute);
                return false;
              }
              return true;
            }));
    if (null != assets) {
      for (var asset in assets) {
        await _handleAssets(asset, sendNow: false);
      }

      for (var msg in tempMessages) {
        await _sendMessage(msg, addToUI: false);
      }

      tempMessages.clear();
    }
  }

  void onTapCamera() async {
    forceCloseToolbox.addSafely(true);
    final AssetEntity? asset = await CameraPicker.pickFromCamera(
      Get.context!,
      locale: Get.locale,
      pickerConfig: CameraPickerConfig(
        enableAudio: true,
        enableRecording: true,
        enableScaledPreview: false,
        maximumRecordingDuration: 5.minutes,
        onMinimumRecordDurationNotMet: () {
          IMViews.showToast(StrRes.tapTooShort);
        },
      ),
    );
    await _handleAssets(asset);
  }

  Future<bool> allowSendImageType(AssetEntity entity) async {
    final mimeType = await entity.mimeTypeAsync;

    return IMUtils.allowImageType(mimeType);
  }

  Future _handleAssets(AssetEntity? asset, {bool sendNow = true}) async {
    if (null != asset) {
      Logger.print(
          '--------assets type-----${asset.type} create time: ${asset.createDateTime}');
      final originalFile = await asset.file;
      final originalPath = originalFile!.path;
      var path = originalPath.toLowerCase().endsWith('.gif')
          ? originalPath
          : originalFile.path;
      Logger.print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          final ctx = Get.context;
          if (ctx == null) break;
          // GIF keeps original path; other images open edit/crop/doodle first.
          if (path.toLowerCase().endsWith('.gif')) {
            await sendPicture(path: path, sendNow: sendNow);
          } else {
            final edited = await ImageEditHelper.openFromPath(ctx, path);
            if (edited == null || edited.isEmpty) break;
            await sendPicture(path: edited, sendNow: sendNow);
          }
          break;
        case AssetType.video:
          final thumbnailData = await asset.thumbnailDataWithSize(
            const ThumbnailSize(480, 480),
            quality: 90,
          );
          if (thumbnailData == null) break;
          final tempDir = await getTemporaryDirectory();
          final snapshotName =
              asset.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          final snapshotPath =
              '${tempDir.path}/${snapshotName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(snapshotPath).writeAsBytes(thumbnailData);
          await sendVideo(
            videoPath: path,
            videoType: await asset.mimeTypeAsync ??
                IMUtils.getMediaType(path) ??
                'video/mp4',
            duration: asset.videoDuration.inSeconds,
            snapshotPath: snapshotPath,
            sendNow: sendNow,
          );
          break;
        default:
          break;
      }
      if (Platform.isIOS && asset.type == AssetType.image) {
        originalFile.deleteSync();
      }
    }
  }

  void onTapDirectionalMessage() async {
    if (null != groupInfo) {
      final list = await AppNavigator.startGroupMemberList(
        groupInfo: groupInfo!,
        opType: GroupMemberOpType.call,
      );
      if (list is List<GroupMembersInfo>) {
        directionalUsers.assignAll(list);
      }
    }
  }

  TextSpan? directionalText() {
    if (directionalUsers.isNotEmpty) {
      final temp = <TextSpan>[];

      for (var e in directionalUsers) {
        final r = TextSpan(
          text: '${e.nickname ?? ''} ${directionalUsers.last == e ? '' : ','} ',
          style: Styles.ts_0089FF_14sp,
        );

        temp.add(r);
      }

      return TextSpan(
        text: '${StrRes.directedTo}:',
        style: Styles.ts_8E9AB0_14sp,
        children: temp,
      );
    }

    return null;
  }

  void onClearDirectional() {
    directionalUsers.clear();
  }

  void parseClickEvent(Message msg) async {
    log('parseClickEvent:${jsonEncode(msg)}');
    if (msg.contentType == MessageType.custom) {
      var data = msg.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      if (CustomMessageType.call == customType && !isInBlacklist.value) {}

      return;
    }

    if (msg.isCardType) {
      final card = msg.cardElem;
      if (card?.userID != null) {
        viewUserInfo(
          UserInfo()
            ..userID = card!.userID
            ..nickname = card.nickname
            ..faceURL = card.faceURL,
          isCard: true,
        );
      }
      return;
    }

    IMUtils.parseClickEvent(
      msg,
      onViewUserInfo: (userInfo) {
        viewUserInfo(userInfo, isCard: msg.isCardType);
      },
    );
  }

  void onTapLeftAvatar(Message message) {
    viewUserInfo(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapReadTag(Message message) {
    if (isGroupChat && message.groupID != null && message.groupID!.isNotEmpty) {
      AppNavigator.startChatReadDetail(
        message: message,
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  String? get _lastOwnGroupMessageClientMsgID {
    for (var i = messageList.length - 1; i >= 0; i--) {
      final message = messageList[i];
      if (message.sendID != OpenIM.iMManager.userID ||
          message.status != MessageStatus.succeeded ||
          message.isNotificationType ||
          message.contentType == MessageType.typing) {
        continue;
      }
      return message.clientMsgID;
    }
    return null;
  }

  bool shouldShowReadTag(Message message) {
    if (message.sendID != OpenIM.iMManager.userID) return false;
    if (!isGroupChat) return true;
    return message.clientMsgID == _lastOwnGroupMessageClientMsgID;
  }

  void onTapRightAvatar() {
    viewUserInfo(OpenIM.iMManager.userInfo);
  }

  void viewUserInfo(UserInfo userInfo, {bool isCard = false}) {
    if (isGroupChat && !isAdminOrOwner && !isCard) {
      if (groupInfo!.lookMemberInfo != 1) {
        AppNavigator.startUserProfilePane(
          userID: userInfo.userID!,
          nickname: userInfo.nickname,
          faceURL: userInfo.faceURL,
          groupID: groupID,
          offAllWhenDelFriend: isSingleChat,
        );
      }
    } else {
      AppNavigator.startUserProfilePane(
        userID: userInfo.userID!,
        nickname: userInfo.nickname,
        faceURL: userInfo.faceURL,
        groupID: groupID,
        offAllWhenDelFriend: isSingleChat,
        forceCanAdd: isCard,
      );
    }
  }

  void clickLinkText(url, type) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  exit() async {
    Get.back();

    return true;
  }

  void focusNodeChanged(bool hasFocus) {
    if (hasFocus) {
      Logger.print('focus:$hasFocus');
      scrollBottom();
    }
  }

  Message indexOfMessage(int index, {bool calculate = true}) =>
      IMUtils.calChatTimeInterval(
        messageList,
        calculate: calculate,
      ).reversed.elementAt(index);

  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);

  @override
  void onClose() {
    sendTypingMsg();
    _clearUnreadCount();
    if (appLogic.viewingConversationID == conversationInfo.conversationID) {
      appLogic.viewingConversationID = null;
    }
    ChatMessagePrefetchCache.invalidate(conversationInfo);
    inputCtrl.dispose();
    focusNode.dispose();
    forceCloseToolbox.close();
    conversationSub.cancel();
    sendStatusSub.close();
    memberAddSub.cancel();
    memberDelSub.cancel();
    memberInfoChangedSub.cancel();
    groupInfoUpdatedSub.cancel();
    friendInfoChangedSub.cancel();
    userStatusChangedSub?.cancel();
    selfInfoUpdatedSub?.cancel();
    inputStatusSub?.cancel();
    groupReadReceiptSub?.cancel();
    joinedGroupAddedSub.cancel();
    joinedGroupDeletedSub.cancel();
    connectionSub.cancel();
    if (isSingleChat && userID != null && userID!.isNotEmpty) {
      OpenIM.iMManager.userManager.unsubscribeUsersStatus([userID!]);
    }
    imLogic.onRecvMessageRevoked = null;
    imLogic.onRecvNewMessage = null;
    imLogic.onRecvC2CReadReceipt = null;

    _debounce?.cancel();
    _typingTimer?.cancel();
    super.onClose();
  }

  String? getShowTime(Message message) {
    if (message.exMap['showTime'] == true) {
      return IMUtils.getChatTimeline(message.sendTime!);
    }
    return null;
  }

  void clearAllMessage() {
    messageList.clear();
  }

  void _initChatConfig() async {
    scaleFactor.value = DataSp.getChatFontSizeFactor();
    var path = DataSp.getChatBackground(otherId) ?? '';
    if (path.isNotEmpty && (await File(path).exists())) {
      background.value = path;
    }
  }

  void _initChatConfigAfterFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      _initChatConfig();
    });
  }

  String get otherId => isSingleChat ? userID! : groupID!;

  void failedResend(Message message) {
    Logger.print('failedResend: ${message.clientMsgID}');
    if (message.status == MessageStatus.sending) {
      return;
    }
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: true,
    ));

    Logger.print('failedResending: ${message.clientMsgID}');
    _sendMessage(message..status = MessageStatus.sending, addToUI: false);
  }

  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  void destroyMsg() {
    for (var message in privateMessageList) {
      OpenIM.iMManager.messageManager.deleteMessageFromLocalAndSvr(
        conversationID: conversationInfo.conversationID,
        clientMsgID: message.clientMsgID!,
      );
    }
  }

  Future _queryMyGroupMemberInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
      groupID: groupID!,
      userIDList: [OpenIM.iMManager.userID],
    );
    groupMembersInfo = list.firstOrNull;
    groupMemberRoleLevel.value =
        groupMembersInfo?.roleLevel ?? GroupRoleLevel.member;
    if (null != groupMembersInfo) {
      memberUpdateInfoMap[OpenIM.iMManager.userID] = groupMembersInfo!;
    }

    return;
  }

  Future _queryOwnerAndAdmin() async {
    if (isGroupChat) {
      ownerAndAdmin = await OpenIM.iMManager.groupManager
          .getGroupMemberList(groupID: groupID!, filter: 5, count: 20);
    }
    return;
  }

  void _isJoinedGroup() async {
    if (!isGroupChat) {
      return;
    }
    isInGroup.value = await OpenIM.iMManager.groupManager.isJoinedGroup(
      groupID: groupID!,
    );
    if (!isInGroup.value) {
      return;
    }
    _queryGroupInfo();
    _queryOwnerAndAdmin();
  }

  void _queryGroupInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID!],
    );
    groupInfo = list.firstOrNull;
    groupOwnerID = groupInfo?.ownerUserID;
    if (null != groupInfo?.memberCount) {
      memberCount.value = groupInfo!.memberCount!;
    }
    _syncAnnouncement();
    _queryMyGroupMemberInfo();
  }

  void _syncAnnouncement() {
    if (!isGroupChat) {
      showAnnouncement.value = false;
      announcement.value = '';
      return;
    }
    final content = groupInfo?.notification?.trim() ?? '';
    announcement.value = content;
    if (content.isEmpty) {
      showAnnouncement.value = false;
      return;
    }
    final dismissedTime = DataSp.getDismissedGroupAnnouncementTime(groupID!);
    final updateTime = groupInfo?.notificationUpdateTime ?? 0;
    showAnnouncement.value = updateTime > dismissedTime;
  }

  void closeAnnouncement() {
    if (groupID == null) return;
    final updateTime = groupInfo?.notificationUpdateTime ?? 0;
    DataSp.putDismissedGroupAnnouncementTime(groupID!, updateTime);
    showAnnouncement.value = false;
    _resetGroupAtType();
  }

  void previewAnnouncement() {
    final content = announcement.value.trim();
    if (content.isEmpty) return;
    AppNavigator.startGroupAnnouncementDetail(
      content: content,
      updateTime: groupInfo?.notificationUpdateTime,
    );
  }

  bool get havePermissionMute =>
      isGroupChat &&
      (groupInfo?.ownerUserID ==
          OpenIM.iMManager
              .userID /*||
          groupMembersInfo?.roleLevel == 2*/
      );

  bool isNotificationType(Message message) => message.contentType! >= 1000;

  Map<String, String> getAtMapping(Message message) {
    final newestMapping = memberUpdateInfoMap.map(
      (key, value) => MapEntry(key, value.nickname ?? key),
    );
    return IMUtils.getAtMapping(message, newestMapping);
  }

  void _checkInBlacklist() async {
    if (userID != null) {
      var list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      var user = list.firstWhereOrNull((e) => e.userID == userID);
      isInBlacklist.value = user != null;
    }
  }

  bool isExceed24H(Message message) {
    int milliseconds = message.sendTime!;
    return !DateUtil.isToday(milliseconds);
  }

  String? getNewestNickname(Message message) {
    if (isSingleChat) null;

    return message.senderNickname;
  }

  String? getNewestFaceURL(Message message) {
    return message.senderFaceUrl;
  }

  bool get isInvalidGroup => !isInGroup.value && isGroupChat;

  void _resetGroupAtType() {
    if (conversationInfo.groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  WillPopCallback? willPop() {
    return null;
  }

  void call() => callVoice();

  void callVoice() async {
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }

    closeToolbox();

    Permissions.cameraAndMicrophone(() async {
      if (isGroupChat) {
        await _groupCall(CallType.audio);
        return;
      }
      imLogic.call(
        callObj: CallObj.single,
        callType: CallType.audio,
        inviteeUserIDList: [if (isSingleChat) userID!],
      );
    });
  }

  void callVideo() async {
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }

    closeToolbox();

    Permissions.cameraAndMicrophone(() async {
      if (isGroupChat) {
        await _groupCall(CallType.video);
        return;
      }
      imLogic.call(
        callObj: CallObj.single,
        callType: CallType.video,
        inviteeUserIDList: [if (isSingleChat) userID!],
      );
    });
  }

  Future<void> _groupCall(CallType callType) async {
    if (groupInfo == null) return;
    final selected = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo!,
      opType: GroupMemberOpType.call,
    );
    if (selected is! List<GroupMembersInfo> || selected.isEmpty) return;
    imLogic.call(
      callObj: CallObj.group,
      callType: callType,
      inviteeUserIDList: selected.map((e) => e.userID!).toList(),
      groupID: groupID,
    );
  }

  void onScrollToTop() {
    if (scrollingCacheMessageList.isNotEmpty) {
      messageList.addAll(scrollingCacheMessageList);
      scrollingCacheMessageList.clear();
    }
  }

  String get markText {
    String? phoneNumber = imLogic.userInfo.value.phoneNumber;
    if (phoneNumber != null) {
      int start = phoneNumber.length > 4 ? phoneNumber.length - 4 : 0;
      final sub = phoneNumber.substring(start);
      return "${OpenIM.iMManager.userInfo.nickname!}$sub";
    }
    return OpenIM.iMManager.userInfo.nickname ?? '';
  }

  bool isFailedHintMessage(Message message) {
    if (message.contentType == MessageType.custom) {
      var data = message.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      return customType == CustomMessageType.deletedByFriend ||
          customType == CustomMessageType.blockedByFriend;
    }
    return false;
  }

  void sendFriendVerification() =>
      AppNavigator.startSendVerificationApplication(userID: userID);

  void _setSdkSyncDataListener() {
    connectionSub = imLogic.imSdkStatusPublishSubject.listen((value) {
      syncStatus.value = value.status;
      if (value.status == IMSdkStatus.syncStart) {
        _isStartSyncing = true;
      } else if (value.status == IMSdkStatus.syncEnded) {
        if ((_isReceivedMessageWhenSyncing || _isStartSyncing) &&
            _isStartSyncing) {
          _isReceivedMessageWhenSyncing = false;
          _isStartSyncing = false;
          _isFirstLoad = true;
          _loadHistoryForSyncEnd();
        }
      } else if (value.status == IMSdkStatus.syncFailed) {
        _isReceivedMessageWhenSyncing = false;
        _isStartSyncing = false;
      }
    });
  }

  bool get isSyncFailed => syncStatus.value == IMSdkStatus.syncFailed;

  String? get syncStatusStr {
    switch (syncStatus.value) {
      case IMSdkStatus.syncStart:
      case IMSdkStatus.synchronizing:
        return StrRes.synchronizing;
      case IMSdkStatus.syncFailed:
        return StrRes.syncFailed;
      default:
        return null;
    }
  }

  bool showBubbleBg(Message message) {
    return !isNotificationType(message) && !isFailedHintMessage(message);
  }

  Future<AdvancedMessage> _fetchHistoryMessages() {
    Logger.print(
        '_fetchHistoryMessages: is first load: $_isFirstLoad, last client id: ${_isFirstLoad ? null : messageList.firstOrNull?.clientMsgID}');
    return OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: _pageSize,
      startMsg: _isFirstLoad ? null : messageList.firstOrNull,
    );
  }

  Future<bool> onScrollToBottomLoad() async {
    late List<Message> list;
    final result = await _fetchHistoryMessages();
    hasMoreHistory = result.isEnd != true;
    if (result.messageList == null || result.messageList!.isEmpty) {
      _deferGroupPostMessageWork(const []);

      return false;
    }
    list = result.messageList!
        .where((e) => !e.isCallingSignalingType)
        .toList();
    if (_isFirstLoad) {
      _isFirstLoad = false;
      // remove the message that has been timed down
      messageList.assignAll(list);
      scrollBottom();

      _deferGroupPostMessageWork(messageList);
    } else {
      messageList.insertAll(0, list);
      _ensureGroupReadInfoForList(list);
    }

    return hasMoreHistory;
  }

  Future<void> _loadHistoryForSyncEnd() async {
    final result =
        await OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: messageList.length < _pageSize ? _pageSize : messageList.length,
      startMsg: null,
    );
    if (result.messageList == null || result.messageList!.isEmpty) return;
    final list = result.messageList!
        .where((e) => !e.isCallingSignalingType)
        .toList();

    final offset = scrollController.offset;
    messageList.assignAll(list);
    _ensureGroupReadInfoForList(messageList);
    scrollController.jumpTo(offset);
  }

  void _ensureGroupReadInfoForList(Iterable<Message> list) {
    if (!isGroupChat) return;
    for (final message in list) {
      _ensureGroupReadInfo(message);
    }
    _backfillGroupReadInfo(list);
  }

  void _applyPrefetchedMessages(Object? value, bool isEnd) {
    if (value is! List<Message>) return;

    hasMoreHistory = !isEnd;
    final visible = value.where((e) => !e.isCallingSignalingType).toList();
    if (visible.isEmpty) {
      // Keep auto-load so we fetch from SDK instead of sticking on empty cache.
      return;
    }

    shouldAutoLoadInitialMessages = false;
    _isFirstLoad = false;
    messageList.assignAll(visible);
    scrollBottom();
    _deferGroupPostMessageWork(visible);
  }

  void _deferGroupPostMessageWork(Iterable<Message> messages) {
    final copiedMessages = List<Message>.of(messages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      _ensureGroupReadInfoForList(copiedMessages);
      _getGroupInfoAfterLoadMessage();
    });
  }

  /// Fetches the real read counts of own group messages from the server and
  /// replaces the local zero-value placeholders set by [_ensureGroupReadInfo].
  Future<void> _backfillGroupReadInfo(Iterable<Message> list) async {
    if (!isGroupChat) return;
    final items = <({String clientMsgID, int seq})>[];
    for (final message in list) {
      if (message.sendID != OpenIM.iMManager.userID ||
          message.status != MessageStatus.succeeded ||
          message.isNotificationType ||
          message.contentType == MessageType.typing) {
        continue;
      }
      final seq = message.seq ?? 0;
      final clientMsgID = message.clientMsgID;
      if (seq <= 0 || clientMsgID == null || clientMsgID.isEmpty) continue;
      items.add((clientMsgID: clientMsgID, seq: seq));
    }
    if (items.isEmpty) return;
    final result = await Apis.getGroupMessagesReadInfo(
      conversationID: conversationInfo.conversationID,
      items: items,
    );
    if (result == null || result.isEmpty) return;
    var changed = false;
    for (final info in result) {
      if (info.clientMsgID.isEmpty) continue;
      final message = messageList
          .firstWhereOrNull((e) => e.clientMsgID == info.clientMsgID);
      if (message == null) continue;
      message.attachedInfoElem ??= AttachedInfoElem();
      message.attachedInfoElem!.groupHasReadInfo = GroupHasReadInfo(
        hasReadCount: info.hasReadCount,
        unreadCount: info.unreadCount,
        groupMemberCount: info.groupMemberCount,
      );
      changed = true;
    }
    if (changed) {
      messageList.refresh();
    }
  }

  void _getGroupInfoAfterLoadMessage() {
    if (isGroupChat && ownerAndAdmin.isEmpty) {
      _isJoinedGroup();
    } else {
      _checkInBlacklist();
    }
  }

  recommendFriendCarte(UserInfo userInfo) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.recommend,
      ex: '[${StrRes.carte}]${userInfo.nickname}',
    );
    if (null != result) {
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      for (var info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        if (customEx is String && customEx.isNotEmpty) {
          _sendMessage(
            await OpenIM.iMManager.messageManager.createTextMessage(
              text: customEx,
            ),
            userId: userID,
            groupId: groupID,
          );
        }
        _sendMessage(
          await OpenIM.iMManager.messageManager.createCardMessage(
            userID: userInfo.userID!,
            nickname: userInfo.nickname!,
            faceURL: userInfo.faceURL,
          ),
          userId: userID,
          groupId: groupID,
        );
      }
    }
  }

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() {
    _loadHistoryForSyncEnd();
  }
}

class _MessageActionInfo {
  const _MessageActionInfo(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
