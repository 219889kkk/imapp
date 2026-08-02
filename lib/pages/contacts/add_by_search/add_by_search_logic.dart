import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

enum SearchType {
  user,
  group,
}

class AddContactsBySearchLogic extends GetxController {
  final refreshCtrl = RefreshController();
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();
  final userInfoList = <UserFullInfo>[].obs;
  final groupInfoList = <GroupInfo>[].obs;
  final hasSearched = false.obs;
  late SearchType searchType;
  int pageNo = 0;

  @override
  void onClose() {
    searchCtrl.dispose();
    focusNode.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    searchType = Get.arguments['searchType'] ?? SearchType.user;
    searchCtrl.addListener(() {
      if (searchKey.isEmpty) {
        focusNode.requestFocus();
        userInfoList.clear();
        groupInfoList.clear();
        hasSearched.value = false;
      }
    });
    super.onInit();
  }

  bool get isSearchUser => searchType == SearchType.user;

  String get searchKey => searchCtrl.text.trim();

  bool get isNotFoundUser =>
      hasSearched.value && userInfoList.isEmpty && searchKey.isNotEmpty;

  bool get isNotFoundGroup =>
      hasSearched.value && groupInfoList.isEmpty && searchKey.isNotEmpty;

  void search() {
    if (searchKey.isEmpty) return;
    if (isSearchUser) {
      searchUser();
    } else {
      searchGroup();
    }
  }

  void searchUser() async {
    var list = await LoadingView.singleton.wrap(
      asyncFunction: () => _searchUserWithFallback(pageNo = 1),
    );
    hasSearched.value = true;
    userInfoList.assignAll(list);
    refreshCtrl.refreshCompleted();
    if (list.isEmpty || list.length < 20) {
      refreshCtrl.loadNoData();
    } else {
      refreshCtrl.loadComplete();
    }
  }

  Future<List<UserFullInfo>> _searchUserWithFallback(int page) async {
    final keyword = searchKey;
    final result = await Apis.searchUserFullInfo(
      content: keyword,
      pageNumber: page,
      showNumber: 20,
    );
    if (result != null && result.isNotEmpty) return result;
    if (page != 1 || keyword.isEmpty) return result ?? [];

    // Fallback: exact match by userID when full-text search misses.
    final byId = await Apis.getUserFullInfo(userIDList: [keyword]);
    if (byId != null && byId.isNotEmpty) return byId;

    try {
      final users = await OpenIM.iMManager.userManager.getUsersInfo(
        userIDList: [keyword],
      );
      if (users.isNotEmpty) {
        return users
            .map((u) => UserFullInfo.fromJson(u.toJson()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void loadMoreUser() async {
    var list = await LoadingView.singleton.wrap(
      asyncFunction: () => _searchUserWithFallback(++pageNo),
    );
    userInfoList.addAll(list);
    refreshCtrl.refreshCompleted();
    if (list.isEmpty || list.length < 20) {
      refreshCtrl.loadNoData();
    } else {
      refreshCtrl.loadComplete();
    }
  }

  void searchGroup() async {
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [searchKey],
    );
    hasSearched.value = true;
    groupInfoList.assignAll(list);
  }

  String? getShowName(dynamic info) {
    if (info is UserFullInfo) {
      return info.nickname;
    } else if (info is GroupInfo) {
      return info.groupName;
    }
    return null;
  }

  void viewInfo(dynamic info) {
    if (info is UserFullInfo) {
      AppNavigator.startUserProfilePane(
        userID: info.userID!,
        nickname: info.nickname,
        faceURL: info.faceURL,
      );
    } else if (info is GroupInfo) {
      AppNavigator.startGroupProfilePanel(
        groupID: info.groupID,
        joinGroupMethod: JoinGroupMethod.search,
      );
    }
  }

  String getShowTitle(info) {
    if (!isSearchUser) {
      return sprintf(StrRes.searchGroupNicknameIs, [getShowName(info)]);
    }

    final user = info as UserFullInfo;
    final nickname = user.nickname?.trim();
    final account = user.account?.trim();
    final userID = user.userID?.trim();
    final phone = user.phoneNumber?.trim();
    final email = user.email?.trim();
    final key = searchKey;

    if (account != null &&
        account.isNotEmpty &&
        account.toLowerCase() == key.toLowerCase()) {
      return '${StrRes.account}:$account';
    }
    if (userID != null && userID == key) {
      return '${StrRes.userID}:$userID';
    }
    if (phone != null && phone.isNotEmpty && phone == key) {
      return '${StrRes.phoneNumber}:$phone';
    }
    if (email != null && email.isNotEmpty && email.toLowerCase() == key.toLowerCase()) {
      return '${StrRes.email}:$email';
    }
    if (nickname != null && nickname.isNotEmpty) {
      final secondary = (account?.isNotEmpty == true)
          ? '${StrRes.account}:$account'
          : '${StrRes.userID}:${userID ?? ''}';
      return '$nickname ($secondary)';
    }
    if (account?.isNotEmpty == true) {
      return '${StrRes.account}:$account';
    }
    return '${StrRes.userID}:${userID ?? key}';
  }

  String getShowSubtitle(UserFullInfo user) {
    final parts = <String>[];
    if (user.account?.isNotEmpty == true) {
      parts.add('${StrRes.account}:${user.account}');
    }
    if (user.userID?.isNotEmpty == true) {
      parts.add('${StrRes.userID}:${user.userID}');
    }
    if (user.phoneNumber?.isNotEmpty == true) {
      parts.add('${StrRes.phoneNumber}:${user.phoneNumber}');
    }
    if (user.email?.isNotEmpty == true) {
      parts.add('${StrRes.email}:${user.email}');
    }
    return parts.join('  ');
  }
}
