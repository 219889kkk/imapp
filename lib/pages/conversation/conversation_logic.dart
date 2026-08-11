import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/conversation_category_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../chat/chat_message_prefetch_cache.dart';
import '../contacts/add_by_search/add_by_search_logic.dart';
import '../home/home_logic.dart';
import 'widgets/conversation_category_manage_sheet.dart';
import 'widgets/conversation_tag_sheet.dart';

class ConversationLogic extends GetxController {
  final popCtrl = CustomPopupMenuController();
  final list = <ConversationInfo>[].obs;
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final appLogic = Get.find<AppController>();
  final categoryLogic = Get.find<ConversationCategoryController>();
  final refreshController = RefreshController();
  final tempDraftText = <String, String>{};
  final _contentPreviewCache = <String, String>{};
  final pageSize = 400;
  Timer? _prefetchTimer;

  final imStatus = IMSdkStatus.connectionSucceeded.obs;
  bool reInstall = false;

  final onChangeConversations = <ConversationInfo>[];

  List<ConversationInfo> get filteredList =>
      categoryLogic.filter(_withoutSelfConversations(list));

  /// Never show a 1:1 chat with myself (e.g. test0099 chatting test0099).
  bool _isSelfConversation(ConversationInfo info) {
    final self = OpenIM.iMManager.userID.trim();
    if (self.isEmpty) return false;
    if (info.userID?.trim() == self) return true;
    return false;
  }

  List<ConversationInfo> _withoutSelfConversations(
      Iterable<ConversationInfo> source) {
    return source.where((e) => !_isSelfConversation(e)).toList();
  }

  /// Answered voice/video records keep history but must not show unread badges.
  bool _isAnsweredCallLatest(ConversationInfo info) {
    final msg = info.latestMsg;
    if (msg == null || !msg.isCustomType) return false;
    try {
      final map = json.decode(msg.customElem!.data!);
      final customType = map['customType'];
      if (customType == CustomMessageType.callingAccept ||
          customType == CustomMessageType.callingHungup) {
        return true;
      }
      if (customType == CustomMessageType.call) {
        final data = map['data'];
        final state =
            data is Map ? data['state']?.toString() ?? '' : '';
        return state == 'hangup' ||
            state == 'beHangup' ||
            state == 'calling' ||
            state == 'beAccepted';
      }
    } catch (_) {}
    return false;
  }

  @override
  void onInit() {
    getFirstPage();
    imLogic.conversationAddedSubject.listen(onChanged);
    imLogic.conversationChangedSubject.listen(onChanged);
    imLogic.imSdkStatusSubject.listen((value) async {
      final status = value.status;
      final appReInstall = value.reInstall;
      final progress = value.progress;
      imStatus.value = status;

      if (status == IMSdkStatus.syncStart) {
        reInstall = appReInstall;
      }

      Logger.print(
          'IM SDK Status: $status, reinstall: $reInstall, progress: $progress');

      if (status == IMSdkStatus.syncEnded ||
          status == IMSdkStatus.syncFailed) {
        if (status == IMSdkStatus.syncEnded) {
          onRefresh();
        }
        reInstall = false;
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    _prefetchTimer?.cancel();
    refreshController.dispose();
    list.clear();
    reInstall = false;
    super.onClose();
  }

  void onChanged(List<ConversationInfo> newList) {
    final incoming = _withoutSelfConversations(newList);
    if (reInstall) {
      onChangeConversations.addAll(incoming);
    }
    for (var newValue in incoming) {
      // Only drop prefetch when the latest message actually changed — sync storms
      // used to invalidate every update and force cold history pulls.
      final existing = list.firstWhereOrNull(
          (e) => e.conversationID == newValue.conversationID);
      final oldLatest = existing?.latestMsg?.clientMsgID;
      final newLatest = newValue.latestMsg?.clientMsgID;
      if (oldLatest != newLatest) {
        ChatMessagePrefetchCache.invalidate(newValue);
      }
      _contentPreviewCache.remove(newValue.conversationID);
      _contentPreviewCache.removeWhere(
          (k, _) => k.startsWith('_k_${newValue.conversationID}|'));
      list.removeWhere((e) => e.conversationID == newValue.conversationID);
      // Connected call left invite unread — clear on list update.
      if (_isAnsweredCallLatest(newValue) && newValue.unreadCount > 0) {
        unawaited(_silentMarkConversationRead(newValue));
        newValue.unreadCount = 0;
      }
    }
    // Drop any self rows that were already in the list.
    list.removeWhere(_isSelfConversation);

    if (incoming.length > pageSize) {
      final tempList = List<ConversationInfo>.from(incoming);

      while (true) {
        final temp = tempList.sublist(0, pageSize);
        list.insertAll(0, temp);
        _sortConversationList();

        if (tempList.length <= pageSize) {
          break;
        }

        tempList.removeRange(0, pageSize);
      }
    } else {
      list.insertAll(0, incoming);
      _sortConversationList();
    }
    _schedulePrefetchFirstPages();
  }

  void promptSoundOrNotification(ConversationInfo info) {
    if (imLogic.userInfo.value.globalRecvMsgOpt == 0 &&
        info.recvMsgOpt == 0 &&
        info.unreadCount > 0 &&
        info.latestMsg?.sendID != OpenIM.iMManager.userID) {
      appLogic.promptSoundOrNotification(info.latestMsg!);
    }
  }

  String getConversationID(ConversationInfo info) {
    return info.conversationID;
  }

  String? getPrefixTag(ConversationInfo info) {
    if (info.groupAtType == GroupAtType.groupNotification) {
      return '[${StrRes.groupAc}]';
    }

    return null;
  }

  String getContent(ConversationInfo info) {
    final cached = _contentPreviewCache[info.conversationID];
    final draft = info.draftText ?? '';
    final latestId = info.latestMsg?.clientMsgID ?? '';
    final cacheKey = '${info.conversationID}|$draft|$latestId|${info.latestMsg?.contentType}|${info.latestMsg?.seq}';
    if (cached != null && _contentPreviewCache.containsKey('_k_$cacheKey')) {
      return cached;
    }
    try {
      String result = '';
      if (null != info.draftText && '' != info.draftText) {
        var map = json.decode(info.draftText!);
        String text = map['text'];
        if (text.isNotEmpty) {
          result = text;
        }
      }

      if (result.isEmpty) {
        if (null == info.latestMsg) {
          result = '';
        } else {
          final text = IMUtils.parseNtf(info.latestMsg!, isConversation: true);
          if (text != null) {
            result = text;
          } else if (info.isSingleChat ||
              info.latestMsg!.sendID == OpenIM.iMManager.userID) {
            result = IMUtils.parseMsg(info.latestMsg!, isConversation: true);
          } else {
            result =
                '${info.latestMsg!.senderNickname}: ${IMUtils.parseMsg(info.latestMsg!, isConversation: true)}';
          }
        }
      }

      _contentPreviewCache[info.conversationID] = result;
      _contentPreviewCache['_k_$cacheKey'] = '1';
      // Drop stale key markers for this conversation (keep map bounded).
      _contentPreviewCache.removeWhere((k, _) =>
          k.startsWith('_k_${info.conversationID}|') && k != '_k_$cacheKey');
      return result;
    } catch (e, s) {
      Logger.print('------e:$e s:$s');
    }
    return '';
  }

  String? getAvatar(ConversationInfo info) {
    return info.faceURL;
  }

  bool isGroupChat(ConversationInfo info) {
    return info.isGroupChat;
  }

  String getShowName(ConversationInfo info) {
    if (info.showName == null || info.showName.isBlank!) {
      return info.userID!;
    }
    return info.showName!;
  }

  String getTime(ConversationInfo info) {
    return IMUtils.getChatTimeline(info.latestMsgSendTime!);
  }

  int getUnreadCount(ConversationInfo info) {
    // Missed calls may keep unread; answered voice/video only keep the record.
    if (_isAnsweredCallLatest(info)) return 0;
    return info.unreadCount;
  }

  bool existUnreadMsg(ConversationInfo info) {
    return getUnreadCount(info) > 0;
  }

  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt != 0;

  void showConversationActionSheet(ConversationInfo info) {
    final actions = <_ConversationActionInfo>[
      _ConversationActionInfo(
        info.isPinned == true ? StrRes.cancelTop : StrRes.top,
        () => togglePinConversation(info),
      ),
      _ConversationActionInfo(
        isNotDisturb(info)
            ? '${StrRes.cancel}${StrRes.messageNotDisturb}'
            : StrRes.messageNotDisturb,
        () => toggleNotDisturb(info),
      ),
      if (info.unreadCount > 0)
        _ConversationActionInfo(
          StrRes.markHasRead,
          () => markConversationAsRead(info),
        ),
      _ConversationActionInfo(
        StrRes.delete,
        () => deleteConversation(info),
      ),
      _ConversationActionInfo(
        StrRes.setConversationTags,
        () => showConversationTagSheet(info),
      ),
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
              ...actions.map(_buildActionItem),
              Container(height: 8, color: Styles.groupedSeparator),
              _buildActionItem(
                _ConversationActionInfo(StrRes.cancel, () => Get.back()),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  void showConversationTagSheet(ConversationInfo info) {
    Get.bottomSheet(
      ConversationTagSheet(conversationID: info.conversationID),
      isScrollControlled: true,
    );
  }

  void showCategoryManageSheet() {
    Get.bottomSheet(
      ConversationCategoryManageSheet(),
      isScrollControlled: true,
    );
  }

  Widget _buildActionItem(_ConversationActionInfo action) => InkWell(
        onTap: () {
          Get.back();
          action.onTap();
        },
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: action.label.toText..style = Styles.ts_0C1C33_17sp,
        ),
      );

  Future<void> togglePinConversation(ConversationInfo info) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(isPinned: info.isPinned != true),
      ),
    );
    info.isPinned = info.isPinned != true;
    _sortConversationList();
    list.refresh();
  }

  Future<void> toggleNotDisturb(ConversationInfo info) async {
    final recvMsgOpt = isNotDisturb(info) ? 0 : 2;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(recvMsgOpt: recvMsgOpt),
      ),
    );
    info.recvMsgOpt = recvMsgOpt;
    list.refresh();
  }

  Future<void> markConversationAsRead(ConversationInfo info) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => _silentMarkConversationRead(info),
    );
    list.refresh();
  }

  Future<void> _silentMarkConversationRead(ConversationInfo info) async {
    try {
      await OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
        conversationID: info.conversationID,
      );
      info.unreadCount = 0;
    } catch (e, s) {
      Logger.print('silentMarkConversationRead failed: $e $s');
    }
  }

  Future<void> clearAllUnread() async {
    try {
      final localUnread =
          list.where((e) => e.unreadCount > 0).toList(growable: false);
      final totalStr =
          await OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount();
      final totalUnread = int.tryParse(totalStr) ?? 0;

      if (localUnread.isEmpty && totalUnread == 0) {
        IMViews.showToast(StrRes.noUnreadMessage);
        return;
      }

      var unreadConversations = localUnread;
      if (unreadConversations.isEmpty && totalUnread > 0) {
        unreadConversations = await _loadUnreadConversations();
      }
      if (unreadConversations.isEmpty) {
        IMViews.showToast(StrRes.noUnreadMessage);
        return;
      }

      await LoadingView.singleton.wrap(
        asyncFunction: () async {
          for (final info in unreadConversations) {
            await OpenIM.iMManager.conversationManager
                .markConversationMessageAsRead(
              conversationID: info.conversationID,
            );
          }
        },
      );

      for (final info in unreadConversations) {
        info.unreadCount = 0;
      }
      homeLogic.unreadMsgCount.value = 0;
      appLogic.showBadge(0);
      list.refresh();
      IMViews.showToast(StrRes.allRead);
    } catch (e, s) {
      Logger.print('clearAllUnread failed: $e $s');
      IMViews.showToast(StrRes.networkError);
    }
  }

  Future<List<ConversationInfo>> _loadUnreadConversations() async {
    final unread = <ConversationInfo>[];
    var offset = 0;

    while (true) {
      final page = await OpenIM.iMManager.conversationManager
          .getConversationListSplit(offset: offset, count: pageSize);
      if (page.isEmpty) break;

      unread.addAll(page.where((e) => e.unreadCount > 0));
      offset += page.length;
      if (page.length < pageSize) break;
    }

    return unread;
  }

  Future<void> deleteConversation(ConversationInfo info) async {
    final confirm = await Get.dialog(CustomDialog(
      title: StrRes.confirmClearChatHistory,
    ));
    if (confirm != true) return;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.conversationManager
          .deleteConversationAndDeleteAllMsg(
        conversationID: info.conversationID,
      ),
    );
    list.removeWhere((e) => e.conversationID == info.conversationID);
  }

  bool isUserGroup(int index) => list.elementAt(index).isGroupChat;

  String? get imSdkStatus {
    switch (imStatus.value) {
      case IMSdkStatus.syncStart:
      case IMSdkStatus.synchronizing:
      case IMSdkStatus.syncProgress:
        return StrRes.synchronizing;
      case IMSdkStatus.syncFailed:
        return StrRes.syncFailed;
      case IMSdkStatus.connecting:
        return StrRes.connecting;
      case IMSdkStatus.connectionFailed:
        return StrRes.connectionFailed;
      case IMSdkStatus.connectionSucceeded:
      case IMSdkStatus.syncEnded:
        return null;
    }
  }

  bool get isFailedSdkStatus =>
      imStatus.value == IMSdkStatus.connectionFailed ||
      imStatus.value == IMSdkStatus.syncFailed;

  void _sortConversationList() =>
      OpenIM.iMManager.conversationManager.simpleSort(list);

  Future<void> onRefresh() async {
    try {
      final list = _withoutSelfConversations(await _request());
      this.list.assignAll(list);
      _schedulePrefetchFirstPages();
      refreshController.refreshCompleted();
    } catch (_) {
      refreshController.refreshFailed();
    }
  }

  static Future<List<ConversationInfo>> getConversationFirstPage() async {
    final result = await OpenIM.iMManager.conversationManager
        .getConversationListSplit(offset: 0, count: 400);
    final self = OpenIM.iMManager.userID.trim();
    if (self.isEmpty) return result;
    return result.where((e) => e.userID?.trim() != self).toList();
  }

  void getFirstPage() async {
    try {
      final result =
          _withoutSelfConversations(await getConversationFirstPage());
      list.assignAll(result);
      homeLogic.conversationsAtFirstPage = List.of(result);
      for (final info in result) {
        if (_isAnsweredCallLatest(info) && info.unreadCount > 0) {
          unawaited(_silentMarkConversationRead(info));
          info.unreadCount = 0;
        }
      }
    } catch (e, s) {
      Logger.print('getFirstPage error: $e $s');
      list.assignAll(
          _withoutSelfConversations(homeLogic.conversationsAtFirstPage));
    }
    _sortConversationList();
    _schedulePrefetchFirstPages();
  }

  void clearConversations() {
    list.clear();
  }

  _request() async {
    final temp = <ConversationInfo>[];

    while (true) {
      var result =
          await OpenIM.iMManager.conversationManager.getConversationListSplit(
        offset: temp.length,
        count: pageSize,
      );
      if (onChangeConversations.isNotEmpty) {
        final bSet = Set.from(onChangeConversations);

        Logger.print(
            'replace conversation: [${onChangeConversations.length}], $bSet');

        for (int i = 0; i < result.length; i++) {
          final info = result[i];

          if (bSet.contains(info)) {
            result[i] =
                onChangeConversations[onChangeConversations.indexOf(info)];
          }
        }
      }
      temp.addAll(result);

      if (result.length < pageSize) {
        break;
      }
    }
    onChangeConversations.clear();

    return temp;
  }

  bool isValidConversation(ConversationInfo info) {
    return info.isValid;
  }

  static Future<ConversationInfo> _createConversation({
    required String sourceID,
    required int sessionType,
  }) =>
      LoadingView.singleton.wrap(
          asyncFunction: () =>
              OpenIM.iMManager.conversationManager.getOneConversation(
                sourceID: sourceID,
                sessionType: sessionType,
              ));

  Future<bool> _jumpOANtf(ConversationInfo info) async {
    if (info.conversationType == ConversationType.notification) {
      return true;
    }
    return false;
  }

  void toChat({
    bool offUntilHome = true,
    String? userID,
    String? groupID,
    String? nickname,
    String? faceURL,
    int? sessionType,
    ConversationInfo? conversationInfo,
    Message? searchMessage,
  }) async {
    conversationInfo ??= await _createConversation(
      sourceID: userID ?? groupID!,
      sessionType: userID == null ? sessionType! : ConversationType.single,
    );

    if (await _jumpOANtf(conversationInfo)) return;

    PrefetchedChatMessages? prefetchedMessages;
    try {
      prefetchedMessages =
          await ChatMessagePrefetchCache.prefetch(conversationInfo);
    } catch (_) {}

    await AppNavigator.startChat(
      offUntilHome: offUntilHome,
      draftText: conversationInfo.draftText,
      conversationInfo: conversationInfo,
      searchMessage: searchMessage,
      prefetchedMessages: prefetchedMessages?.messages,
      prefetchedMessagesIsEnd: prefetchedMessages?.isEnd ?? false,
    );

    bool equal(e) => e.conversationID == conversationInfo?.conversationID;

    var groupAtType = list.firstWhereOrNull(equal)?.groupAtType;
    if (groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  void _schedulePrefetchFirstPages() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 350), () {
      _prefetchFirstPages();
    });
  }

  Future<void> _prefetchFirstPages() async {
    final candidates = filteredList.take(10).toList(growable: false);
    for (final conversation in candidates) {
      if (ChatMessagePrefetchCache.peek(conversation) != null) continue;
      try {
        await ChatMessagePrefetchCache.prefetch(conversation);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  addFriend() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.user);

  void scan() => AppNavigator.startScan();

  createGroup() => AppNavigator.startCreateGroup(
      defaultCheckedList: [OpenIM.iMManager.userInfo]);

  addGroup() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.group);

  void globalSearch() => AppNavigator.startGlobalSearch();
}

class _ConversationActionInfo {
  const _ConversationActionInfo(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
