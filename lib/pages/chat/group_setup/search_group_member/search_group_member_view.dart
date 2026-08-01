import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:search_keyword_text/search_keyword_text.dart';

import 'search_group_member_logic.dart';

class SearchGroupMemberPage extends StatelessWidget {
  final logic = Get.find<SearchGroupMemberLogic>();

  SearchGroupMemberPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TouchCloseSoftKeyboard(
      child: Scaffold(
        appBar: TitleBar.search(
          controller: logic.searchCtrl,
          focusNode: logic.focusNode,
          onSubmitted: (_) => logic.search(),
          onCleared: () => logic.focusNode.requestFocus(),
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => logic.isSearchNotResult
              ? _emptyListView
              : ListView.builder(
                  itemCount: logic.resultList.length,
                  itemBuilder: (_, index) =>
                      _buildItemView(logic.resultList[index]),
                ),
        ),
      ),
    );
  }

  Widget _buildItemView(GroupMembersInfo info) => Ink(
        height: 64.h,
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: () => logic.clickMember(info),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                AvatarView(
                  url: info.faceURL,
                  text: info.nickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: SearchKeywordText(
                    text: info.nickname ?? info.userID ?? '',
                    keyText: logic.searchKey,
                    style: Styles.ts_0C1C33_17sp,
                    keyStyle: Styles.ts_0089FF_17sp,
                  ),
                ),
                if (info.roleLevel == GroupRoleLevel.owner)
                  StrRes.groupOwner.toText..style = Styles.ts_8E9AB0_17sp,
                if (info.roleLevel == GroupRoleLevel.admin)
                  StrRes.groupAdmin.toText..style = Styles.ts_8E9AB0_17sp,
              ],
            ),
          ),
        ),
      );

  Widget get _emptyListView => SizedBox(
        width: 1.sw,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            44.verticalSpace,
            StrRes.searchNotFound.toText..style = Styles.ts_8E9AB0_17sp,
          ],
        ),
      );
}
