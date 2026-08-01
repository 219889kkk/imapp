import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_read_detail_logic.dart';

class ChatReadDetailPage extends StatelessWidget {
  final logic = Get.find<ChatReadDetailLogic>();

  ChatReadDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        appBar: TitleBar.back(title: StrRes.messageRecipientList),
        backgroundColor: Styles.pageBackground,
        body: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              _buildSummary(),
              _buildTabs(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final total = logic.totalMemberCount.value;
    final read = logic.hasReadCount.value;
    final unread = logic.unreadCount.value;
    return Container(
      color: Styles.c_FFFFFF,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              count: read,
              total: total,
              label: StrRes.hasRead,
              color: Styles.c_0089FF,
            ),
          ),
          12.horizontalSpace,
          Expanded(
            child: _buildSummaryCard(
              count: unread,
              total: total,
              label: StrRes.unread,
              color: Styles.c_FF381F,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required int count,
    required int total,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: Styles.c_F0F2F6,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label.toText..style = Styles.ts_8E9AB0_14sp,
          6.verticalSpace,
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              '$count'.toText
                ..style = TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              4.horizontalSpace,
              if (total > 0) '/ $total'.toText..style = Styles.ts_8E9AB0_12sp,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Material(
      color: Styles.c_FFFFFF,
      child: TabBar(
        labelColor: Styles.c_0089FF,
        unselectedLabelColor: Styles.c_8E9AB0,
        indicatorColor: Styles.c_0089FF,
        tabs: [
          Tab(text: '${StrRes.hasRead} ${logic.readList.length}'),
          Tab(text: '${StrRes.unread} ${logic.unreadList.length}'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (logic.loading.value) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (logic.failed.value) {
      return _buildError();
    }
    return TabBarView(
      children: [
        _buildList(logic.readList),
        _buildList(logic.unreadList),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrRes.networkError.toText..style = Styles.ts_8E9AB0_14sp,
          12.verticalSpace,
          GestureDetector(
            onTap: logic.loadReaders,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Styles.c_0089FF,
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: StrRes.retry.toText..style = Styles.ts_FFFFFF_14sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<GroupMembersInfo> list) {
    if (list.isEmpty) {
      return Center(child: StrRes.empty.toText..style = Styles.ts_8E9AB0_14sp);
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, index) => _buildItem(list[index]),
    );
  }

  Widget _buildItem(GroupMembersInfo member) {
    final isSelf = member.userID == OpenIM.iMManager.userID;
    return Container(
      height: 64.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      color: Styles.c_FFFFFF,
      child: Row(
        children: [
          AvatarView(
            url: member.faceURL,
            text: member.nickname,
          ),
          10.horizontalSpace,
          Expanded(
            child: (member.nickname ?? '').toText
              ..style = Styles.ts_0C1C33_17sp
              ..maxLines = 1
              ..overflow = TextOverflow.ellipsis,
          ),
          if (isSelf) StrRes.me.toText..style = Styles.ts_8E9AB0_14sp,
          if (member.roleLevel == GroupRoleLevel.owner)
            StrRes.groupOwner.toText..style = Styles.ts_8E9AB0_14sp
          else if (member.roleLevel == GroupRoleLevel.admin)
            StrRes.groupAdmin.toText..style = Styles.ts_8E9AB0_14sp,
        ],
      ),
    );
  }
}
