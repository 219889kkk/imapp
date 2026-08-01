import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../routes/app_navigator.dart';
import '../group_member_list/group_member_list_logic.dart';

class GroupManageLogic extends GetxController {
  final groupSetupLogic = Get.find<GroupSetupLogic>();
  final groupMuted = false.obs;

  Rx<GroupInfo> get groupInfo => groupSetupLogic.groupInfo;

  int get needVerification =>
      groupInfo.value.needVerification ??
      GroupVerification.applyNeedVerificationInviteDirectly;

  void transferGroupOwnerRight() async {
    var result = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo.value,
      opType: GroupMemberOpType.transferRight,
    );
    if (result is GroupMembersInfo) {
      await LoadingView.singleton.wrap(
        asyncFunction: () => OpenIM.iMManager.groupManager.transferGroupOwner(
          groupID: groupInfo.value.groupID,
          userID: result.userID!,
        ),
      );
      groupInfo.update((val) {
        val?.ownerUserID = result.userID;
      });
      Get.back();
    }
  }

  Future<void> toggleGroupMute(bool value) async {
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.groupManager.changeGroupMute(
        groupID: groupInfo.value.groupID,
        mute: value,
      ),
    );
    groupMuted.value = value;
  }

  Future<void> setAdminRole() async {
    final member = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo.value,
      opType: GroupMemberOpType.setAdmin,
    );
    if (member is! GroupMembersInfo) return;
    final isAdmin = member.roleLevel == GroupRoleLevel.admin;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.groupManager.setGroupMemberInfo(
        groupMembersInfo: SetGroupMemberInfo(
          groupID: groupInfo.value.groupID,
          userID: member.userID!,
          roleLevel: isAdmin ? GroupRoleLevel.member : GroupRoleLevel.admin,
        ),
      ),
    );
  }

  Future<void> setMemberMute() async {
    final member = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo.value,
      opType: GroupMemberOpType.muteMember,
    );
    if (member is! GroupMembersInfo) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isMuted = (member.muteEndTime ?? 0) > now;
    await LoadingView.singleton.wrap(
      asyncFunction: () => OpenIM.iMManager.groupManager.changeGroupMemberMute(
        groupID: groupInfo.value.groupID,
        userID: member.userID!,
        seconds: isMuted ? 0 : const Duration(days: 1).inSeconds,
      ),
    );
  }

  String get verificationLabel {
    switch (needVerification) {
      case GroupVerification.directly:
        return StrRes.allowAnyoneJoinGroup;
      case GroupVerification.allNeedVerification:
        return StrRes.needVerification;
      case GroupVerification.applyNeedVerificationInviteDirectly:
      default:
        return StrRes.inviteNotVerification;
    }
  }

  void setGroupVerification() {
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
              _buildVerificationItem(
                StrRes.allowAnyoneJoinGroup,
                GroupVerification.directly,
              ),
              _buildVerificationItem(
                StrRes.inviteNotVerification,
                GroupVerification.applyNeedVerificationInviteDirectly,
              ),
              _buildVerificationItem(
                StrRes.needVerification,
                GroupVerification.allNeedVerification,
              ),
              Container(height: 8, color: Styles.groupedSeparator),
              _buildSheetItem(StrRes.cancel, () => Get.back()),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildVerificationItem(String label, int value) => _buildSheetItem(
        label,
        () async {
          Get.back();
          await LoadingView.singleton.wrap(
            asyncFunction: () => OpenIM.iMManager.groupManager.setGroupInfo(
              GroupInfo(
                groupID: groupInfo.value.groupID,
                needVerification: value,
              ),
            ),
          );
          groupInfo.update((val) {
            val?.needVerification = value;
          });
        },
      );

  Widget _buildSheetItem(String label, Function() onTap) => InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: label.toText..style = Styles.ts_0C1C33_17sp,
        ),
      );
}
