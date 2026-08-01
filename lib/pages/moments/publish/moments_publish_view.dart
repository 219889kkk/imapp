import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'moments_publish_logic.dart';

class MomentsPublishPage extends StatelessWidget {
  final logic = Get.find<MomentsPublishLogic>();

  MomentsPublishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.c_FFFFFF,
      appBar: TitleBar.back(
        title: StrRes.publish,
        right: Obx(
          () => StrRes.publish.toText
            ..style = logic.publishing.value
                ? Styles.ts_8E9AB0_17sp
                : Styles.ts_0089FF_17sp
            ..onTap = logic.publishing.value ? null : logic.publish,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: logic.inputCtrl,
                    minLines: 6,
                    maxLines: 10,
                    style: Styles.ts_0C1C33_17sp,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: StrRes.momentPublishHint,
                      hintStyle: Styles.ts_8E9AB0_17sp,
                    ),
                  ),
                  12.verticalSpace,
                  Obx(_buildAssetGrid),
                ],
              ),
            ),
            16.verticalSpace,
            Obx(_buildVisibilityRow),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetGrid() {
    final items = [
      ...logic.assets,
      if (logic.assets.length < 9) null,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6.h,
        crossAxisSpacing: 6.w,
      ),
      itemBuilder: (_, index) {
        final asset = items[index];
        if (asset == null) {
          return GestureDetector(
            onTap: logic.pickImages,
            child: Container(
              decoration: BoxDecoration(
                color: Styles.insetBackground,
                borderRadius: BorderRadius.circular(4.r),
                border: Border.all(color: Styles.c_E8EAEF, width: 0.5),
              ),
              child: Icon(
                Icons.add,
                color: Styles.c_8E9AB0,
                size: 32.w,
              ),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.r),
                child: AssetEntityImage(
                  asset,
                  isOriginal: false,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              right: 4.w,
              top: 4.h,
              child: GestureDetector(
                onTap: () => logic.removeAsset(asset),
                child: Container(
                  width: 20.w,
                  height: 20.w,
                  decoration: BoxDecoration(
                    color: Styles.c_000000_opacity70,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    color: Styles.c_FFFFFF,
                    size: 14.w,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVisibilityRow() => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: logic.selectVisibility,
        child: Container(
          height: 56.h,
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            border: Border(
              top: BorderSide(color: Styles.c_E8EAEF, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              ImageRes.whoCanWatch.toImage
                ..width = 22.w
                ..height = 22.h,
              10.horizontalSpace,
              StrRes.whoCanWatch.toText..style = Styles.ts_0C1C33_17sp,
              const Spacer(),
              Flexible(
                child: logic.visibilityLabel.toText
                  ..style = Styles.ts_8E9AB0_14sp
                  ..maxLines = 1
                  ..overflow = TextOverflow.ellipsis
                  ..textAlign = TextAlign.right,
              ),
              ImageRes.rightArrow.toImage
                ..width = 20.w
                ..height = 20.h,
            ],
          ),
        ),
      );
}
