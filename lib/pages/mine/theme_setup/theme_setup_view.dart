import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import 'theme_setup_logic.dart';

class ThemeSetupPage extends StatelessWidget {
  final logic = Get.find<ThemeSetupLogic>();

  ThemeSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (context) => Scaffold(
        appBar: TitleBar.back(title: StrRes.themeSetup),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                12.verticalSpace,
                _buildItemView(
                  label: StrRes.followSystem,
                  isChecked: logic.isFollowSystem.value,
                  onTap: () => logic.switchThemeMode(0),
                  isTopRadius: true,
                ),
                _divider,
                _buildItemView(
                  label: StrRes.lightMode,
                  isChecked: logic.isLight.value,
                  onTap: () => logic.switchThemeMode(1),
                ),
                _divider,
                _buildItemView(
                  label: StrRes.darkMode,
                  isChecked: logic.isDark.value,
                  onTap: () => logic.switchThemeMode(2),
                  isBottomRadius: true,
                ),
                24.verticalSpace,
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: StrRes.themeColor.toText
                    ..style = Styles.ts_8E9AB0_14sp,
                ),
                8.verticalSpace,
                _buildColorSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorSection(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 10.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Wrap(
        spacing: 16.w,
        runSpacing: 16.h,
        children: [
          ...ThemeColorPresets.presets.map(_buildPresetSwatch),
          _buildCustomSwatch(context),
        ],
      ),
    );
  }

  Widget _buildPresetSwatch(Color color) => _buildSwatch(
        color: color,
        isSelected: logic.isPresetSelected(color),
        onTap: () => logic.selectColor(color),
      );

  Widget _buildCustomSwatch(BuildContext context) => _buildSwatch(
        color: logic.isCustomSelected
            ? logic.selectedColor.value
            : Styles.c_F0F2F6,
        isSelected: logic.isCustomSelected,
        onTap: () => logic.openCustomPicker(context),
        child: logic.isCustomSelected
            ? null
            : Icon(Icons.add, color: Styles.c_8E9AB0, size: 22.w),
        label: StrRes.themeColorCustom,
      );

  Widget _buildSwatch({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? child,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Styles.c_0089FF : Styles.c_E8EAEF,
                width: isSelected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: child ??
                (isSelected
                    ? Icon(Icons.check,
                        color: _checkIconColor(color), size: 22.w)
                    : null),
          ),
          if (label != null) ...[
            6.verticalSpace,
            SizedBox(
              width: 56.w,
              child: label.toText
                ..style = Styles.ts_8E9AB0_12sp
                ..maxLines = 1
                ..overflow = TextOverflow.ellipsis
                ..textAlign = TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Color _checkIconColor(Color background) =>
      background.computeLuminance() > 0.55 ? Styles.c_0C1C33 : Styles.c_FFFFFF;

  Widget get _divider => Container(
        margin: EdgeInsets.only(left: 26.w, right: 10.w),
        color: Styles.c_E8EAEF,
        height: .5,
      );

  Widget _buildItemView({
    required String label,
    bool isChecked = false,
    bool isTopRadius = false,
    bool isBottomRadius = false,
    Function()? onTap,
  }) =>
      Container(
        margin: EdgeInsets.symmetric(horizontal: 10.w),
        child: Ink(
          height: 60.h,
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isTopRadius ? 6.r : 0),
              topRight: Radius.circular(isTopRadius ? 6.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  label.toText..style = Styles.ts_0C1C33_17sp,
                  const Spacer(),
                  if (isChecked)
                    ImageRes.checked.toImage
                      ..width = 24.w
                      ..height = 24.h,
                ],
              ),
            ),
          ),
        ),
      );
}
