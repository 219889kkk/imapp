import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../group_member_list/group_member_list_logic.dart';

class SearchGroupMemberLogic extends GetxController {
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();
  final resultList = <GroupMembersInfo>[].obs;
  final hasSearched = false.obs;
  late GroupInfo groupInfo;
  late GroupMemberOpType opType;

  String get searchKey => searchCtrl.text.trim();

  bool get isSearchNotResult => hasSearched.value && resultList.isEmpty;

  bool get excludeSelfFromList =>
      opType == GroupMemberOpType.call ||
      opType == GroupMemberOpType.at ||
      opType == GroupMemberOpType.transferRight ||
      opType == GroupMemberOpType.setAdmin ||
      opType == GroupMemberOpType.muteMember;

  @override
  void onInit() {
    groupInfo = Get.arguments['groupInfo'];
    opType = Get.arguments['opType'];
    searchCtrl.addListener(() {
      if (searchKey.isEmpty) {
        resultList.clear();
        hasSearched.value = false;
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    focusNode.dispose();
    searchCtrl.dispose();
    super.onClose();
  }

  void search() async {
    if (searchKey.isEmpty) {
      resultList.clear();
      hasSearched.value = false;
      return;
    }

    final list = await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.groupManager.searchGroupMembers(
        groupID: groupInfo.groupID,
        keywordList: [searchKey],
        isSearchUserID: true,
        isSearchMemberNickname: true,
        count: 100,
      ),
    );
    resultList.assignAll(list.where((e) => !_hiddenMember(e)));
    hasSearched.value = true;
  }

  void clickMember(GroupMembersInfo info) {
    if (opType == GroupMemberOpType.view) {
      AppNavigator.startUserProfilePane(
        userID: info.userID!,
        groupID: info.groupID,
        nickname: info.nickname,
        faceURL: info.faceURL,
      );
    } else {
      Get.back(result: info);
    }
  }

  bool _hiddenMember(GroupMembersInfo info) =>
      (excludeSelfFromList && info.userID == OpenIM.iMManager.userID) ||
      ((opType == GroupMemberOpType.setAdmin ||
              opType == GroupMemberOpType.muteMember) &&
          info.roleLevel == GroupRoleLevel.owner);
}
