import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'call_audio_debug_logic.dart';

class CallAudioDebugPage extends StatelessWidget {
  CallAudioDebugPage({super.key});

  final logic = Get.find<CallAudioDebugLogic>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(
        title: '通话音频调试',
        right: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: logic.refreshSnapshot,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: '刷新'.toText..style = Styles.ts_0C1C33_14sp,
              ),
            ),
            GestureDetector(
              onTap: logic.copyAll,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: '复制'.toText..style = Styles.ts_0089FF_14sp,
              ),
            ),
            GestureDetector(
              onTap: logic.clearLogs,
              child: Padding(
                padding: EdgeInsets.only(left: 8.w, right: 4.w),
                child: '清空'.toText..style = Styles.ts_0C1C33_14sp,
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Styles.pageBackground,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 0),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Styles.c_FFFFFF,
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Obx(
              () => SelectableText(
                logic.snapshotText.value.isEmpty
                    ? '加载中…'
                    : logic.snapshotText.value,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Styles.c_0C1C33,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          8.verticalSpace,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: '复现无声后点「复制」，把日志发给开发'.toText
              ..style = Styles.ts_8E9AB0_12sp,
          ),
          8.verticalSpace,
          Expanded(
            child: Container(
              margin: EdgeInsets.fromLTRB(10.w, 0, 10.w, 10.h),
              decoration: BoxDecoration(
                color: Styles.c_FFFFFF,
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: CallAudioDebugLog.revision,
                builder: (_, __, ___) {
                  final lines = CallAudioDebugLog.lines;
                  if (lines.isEmpty) {
                    return Center(
                      child: '暂无事件，请先打一通锁屏电话'.toText
                        ..style = Styles.ts_8E9AB0_14sp,
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.all(10.w),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Styles.c_E8EAEF,
                    ),
                    itemBuilder: (_, i) {
                      // Newest at bottom; show chronological.
                      final line = lines[i];
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.h),
                        child: SelectableText(
                          line,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Styles.c_0C1C33,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
