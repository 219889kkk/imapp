import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'moments_notifications_logic.dart';

class MomentsNotificationsPage extends StatelessWidget {
  final logic = Get.find<MomentsNotificationsLogic>();

  MomentsNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.pageBackground,
      appBar: TitleBar.back(title: StrRes.notification),
      body: Obx(
        () => SmartRefresher(
          controller: logic.refreshController,
          onRefresh: logic.refreshNotifications,
          onLoading: logic.loadMore,
          enablePullUp: true,
          header: IMViews.buildHeader(),
          footer: IMViews.buildFooter(),
          child: logic.list.isEmpty
              ? Center(
                  child: StrRes.noDynamic.toText..style = Styles.ts_8E9AB0_17sp,
                )
              : ListView.builder(
                  itemCount: logic.list.length,
                  itemBuilder: (_, index) {
                    final item = logic.list[index];
                    return Container(
                      color: Styles.c_FFFFFF,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 12.h,
                      ),
                      child: Row(
                        children: [
                          AvatarView(
                            width: 42.w,
                            height: 42.h,
                            text: item.operator.nickname,
                            url: item.operator.faceURL,
                          ),
                          10.horizontalSpace,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                '${item.operator.nickname} ${logic.titleFor(item)}'
                                    .toText
                                  ..style = Styles.ts_0C1C33_17sp
                                  ..maxLines = 1
                                  ..overflow = TextOverflow.ellipsis,
                                if (item.content?.isNotEmpty == true)
                                  4.verticalSpace,
                                if (item.content?.isNotEmpty == true)
                                  item.content!.toText
                                    ..style = Styles.ts_8E9AB0_14sp
                                    ..maxLines = 2
                                    ..overflow = TextOverflow.ellipsis,
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
