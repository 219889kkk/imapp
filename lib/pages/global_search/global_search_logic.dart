import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../conversation/conversation_logic.dart';

class GlobalSearchLogic extends CommonSearchLogic {
  final conversationLogic = Get.find<ConversationLogic>();
  final textMessageRefreshCtrl = RefreshController();
  final fileMessageRefreshCtrl = RefreshController();
  final contactsList = <dynamic>[].obs;
  final groupList = <GroupInfo>[].obs;
  final textSearchResultItems = <SearchResultItems>[].obs;

  final fileMessageList = <Message>[].obs;
  final index = 0.obs;
  final hasSearched = false.obs;
  final isSearching = false.obs;
  final inputKeyword = ''.obs;
  final tabs = [
    StrRes.globalSearchAll,
    StrRes.globalSearchContacts,
    StrRes.globalSearchGroup,
    StrRes.globalSearchChatHistory,
    StrRes.globalSearchChatFile,
  ];

  int textMessagePageIndex = 1;
  int fileMessagePageIndex = 1;
  int count = 20;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  void switchTab(int index) {
    this.index.value = index;
  }

  @override
  void clearList() {
    contactsList.clear();
    groupList.clear();
    textSearchResultItems.clear();
    fileMessageList.clear();
    hasSearched.value = false;
    isSearching.value = false;
  }

  bool get isSearchNotResult =>
      hasSearched.value &&
      contactsList.isEmpty &&
      groupList.isEmpty &&
      textSearchResultItems.isEmpty &&
      fileMessageList.isEmpty;

  void onSearchChanged(String value) {
    _searchDebounce?.cancel();
    inputKeyword.value = value.trim();

    if (inputKeyword.value.isEmpty) {
      _searchSeq++;
      clearList();
      return;
    }

    isSearching.value = true;
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => search(showing: false),
    );
  }

  void onSearchCleared() {
    _searchDebounce?.cancel();
    _searchSeq++;
    inputKeyword.value = '';
    clearList();
    focusNode.requestFocus();
  }

  Future<void> search({bool showing = true}) async {
    _searchDebounce?.cancel();
    final keyword = searchKey;
    inputKeyword.value = keyword;

    if (keyword.isEmpty) {
      _searchSeq++;
      clearList();
      return;
    }

    final currentSeq = ++_searchSeq;
    isSearching.value = true;
    try {
      final result = await LoadingView.singleton.wrap(
        showing: showing,
        asyncFunction: () => Future.wait([
          searchFriend(keyword: keyword),
          searchGroup(keyword: keyword),
          searchTextMessage(keyword: keyword),
          searchFileMessage(keyword: keyword),
        ]),
      );
      if (currentSeq != _searchSeq || keyword != searchKey) return;

      contactsList.assignAll(result[0] as List<FriendInfo>);
      groupList.assignAll(result[1] as List<GroupInfo>);
      final textResult = result[2] as SearchResult;
      final fileResult = result[3] as SearchResult;
      textSearchResultItems.assignAll(textResult.searchResultItems ?? []);
      fileMessageList.assignAll(
        (fileResult.searchResultItems ?? [])
            .expand((e) => e.messageList ?? <Message>[])
            .toList(),
      );
      hasSearched.value = true;
    } catch (e, s) {
      if (currentSeq != _searchSeq) return;
      Logger.print('global search failed: $e $s');
      contactsList.clear();
      groupList.clear();
      textSearchResultItems.clear();
      fileMessageList.clear();
      hasSearched.value = true;
      IMViews.showToast(StrRes.networkError);
    } finally {
      if (currentSeq == _searchSeq) {
        isSearching.value = false;
      }
    }
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    super.onClose();
  }

  void viewContact(dynamic info) {
    final userID = parseID(info);
    if (userID == null) return;
    AppNavigator.startUserProfilePane(
      userID: userID,
      nickname: parseNickname(info),
      faceURL: parseFaceURL(info),
    );
  }

  void viewGroup(GroupInfo info) {
    conversationLogic.toChat(
      offUntilHome: false,
      groupID: info.groupID,
      nickname: info.groupName,
      faceURL: info.faceURL,
      sessionType: info.sessionType,
    );
  }

  void viewSearchResultItems(SearchResultItems items) {
    final messages = items.messageList ?? [];
    if (messages.length == 1) {
      viewMessage(items, messages.first);
    } else {
      AppNavigator.startExpandChatHistory(
        searchResultItems: items,
        defaultSearchKey: searchKey,
      );
    }
  }

  void viewMessage(SearchResultItems items, Message message) async {
    final conversationID = items.conversationID;
    if (conversationID == null) return;
    final list = await LoadingView.singleton.wrap(
      asyncFunction: () =>
          OpenIM.iMManager.conversationManager.getMultipleConversation(
        conversationIDList: [conversationID],
      ),
    );
    final conversationInfo = list.isEmpty ? null : list.first;
    if (conversationInfo == null) return;
    conversationLogic.toChat(
      offUntilHome: false,
      conversationInfo: conversationInfo,
      searchMessage: message,
    );
  }
}

abstract class CommonSearchLogic extends GetxController {
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();

  void clearList();

  @override
  void onInit() {
    searchCtrl.addListener(_clearInput);
    super.onInit();
  }

  @override
  void onClose() {
    focusNode.dispose();
    searchCtrl.dispose();
    super.onClose();
  }

  void _clearInput() {
    if (searchKey.isEmpty) {
      clearList();
    }
  }

  String get searchKey => searchCtrl.text.trim();

  Future<List<FriendInfo>> searchFriend({String? keyword}) =>
      Apis.searchFriendInfo(keyword ?? searchKey).then(
          (list) => list.map((e) => FriendInfo.fromJson(e.toJson())).toList());

  Future<List<GroupInfo>> searchGroup({String? keyword}) =>
      OpenIM.iMManager.groupManager.searchGroups(
          keywordList: [keyword ?? searchKey],
          isSearchGroupName: true,
          isSearchGroupID: true);

  Future<SearchResult> searchTextMessage({
    String? keyword,
    int pageIndex = 1,
    int count = 20,
  }) =>
      OpenIM.iMManager.messageManager.searchLocalMessages(
        keywordList: [keyword ?? searchKey],
        messageTypeList: [MessageType.text, MessageType.atText],
        pageIndex: pageIndex,
        count: count,
      );

  Future<SearchResult> searchFileMessage({
    String? keyword,
    int pageIndex = 1,
    int count = 20,
  }) =>
      OpenIM.iMManager.messageManager.searchLocalMessages(
        keywordList: [keyword ?? searchKey],
        messageTypeList: [MessageType.file],
        pageIndex: pageIndex,
        count: count,
      );

  String? parseID(dynamic e) {
    if (e is ConversationInfo) {
      return e.isSingleChat ? e.userID : e.groupID;
    } else if (e is GroupInfo) {
      return e.groupID;
    } else if (e is UserInfo) {
      return e.userID;
    } else if (e is FriendInfo) {
      return e.userID;
    } else {
      return null;
    }
  }

  String? parseNickname(dynamic e) {
    if (e is ConversationInfo) {
      return e.showName;
    } else if (e is GroupInfo) {
      return e.groupName;
    } else if (e is UserInfo) {
      return e.nickname;
    } else if (e is FriendInfo) {
      return e.nickname;
    } else {
      return null;
    }
  }

  String? parseFaceURL(dynamic e) {
    if (e is ConversationInfo) {
      return e.faceURL;
    } else if (e is GroupInfo) {
      return e.faceURL;
    } else if (e is UserInfo) {
      return e.faceURL;
    } else if (e is FriendInfo) {
      return e.faceURL;
    } else {
      return null;
    }
  }
}
