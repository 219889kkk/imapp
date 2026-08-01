import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'workbench_logic.dart';

class WorkbenchPage extends StatelessWidget {
  final logic = Get.find<WorkbenchLogic>();

  WorkbenchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.pageBackground,
      appBar: TitleBar.back(title: StrRes.workbench),
      body: Obx(
        () => RefreshIndicator(
          onRefresh: logic.refreshWorkbench,
          child: ListView(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            children: [
              _buildSectionTitle(StrRes.miniApps),
              _buildAppletGrid(),
              12.verticalSpace,
              _buildSectionTitle(StrRes.aiAgents),
              ...logic.agents.map(_buildAgentItem),
              if (logic.applets.isEmpty && logic.agents.isEmpty)
                Container(
                  height: 240.h,
                  alignment: Alignment.center,
                  child: (logic.loading.value
                          ? StrRes.synchronizing
                          : StrRes.searchNotResult)
                      .toText
                    ..style = Styles.ts_8E9AB0_17sp,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
        child: title.toText..style = Styles.ts_0C1C33_17sp_medium,
      );

  Widget _buildAppletGrid() => Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: logic.applets.isEmpty
            ? SizedBox(
                height: 72.h,
                child: Center(
                  child: StrRes.searchNotResult.toText
                    ..style = Styles.ts_8E9AB0_14sp,
                ),
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logic.applets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12.h,
                  childAspectRatio: 68.w / 78.h,
                ),
                itemBuilder: (_, index) {
                  final item = logic.applets[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => logic.openApplet(item),
                    child: Column(
                      children: [
                        AvatarView(
                          width: 44.w,
                          height: 44.h,
                          url: item.icon,
                          text: item.name,
                          isGroup: true,
                        ),
                        6.verticalSpace,
                        (item.name ?? '').toText
                          ..style = Styles.ts_0C1C33_14sp
                          ..maxLines = 1
                          ..overflow = TextOverflow.ellipsis,
                      ],
                    ),
                  );
                },
              ),
      );

  Widget _buildAgentItem(AgentInfo agent) => Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w),
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: () => logic.chatWithAgent(agent),
          child: Container(
            height: 64.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              children: [
                AvatarView(
                  width: 44.w,
                  height: 44.h,
                  url: agent.faceURL,
                  text: agent.nickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      agent.nickname.toText
                        ..style = Styles.ts_0C1C33_17sp
                        ..maxLines = 1
                        ..overflow = TextOverflow.ellipsis,
                      if (agent.model?.isNotEmpty == true) 4.verticalSpace,
                      if (agent.model?.isNotEmpty == true)
                        agent.model!.toText
                          ..style = Styles.ts_8E9AB0_14sp
                          ..maxLines = 1
                          ..overflow = TextOverflow.ellipsis,
                    ],
                  ),
                ),
                ImageRes.rightArrow.toImage
                  ..width = 24.w
                  ..height = 24.h,
              ],
            ),
          ),
        ),
      );
}
