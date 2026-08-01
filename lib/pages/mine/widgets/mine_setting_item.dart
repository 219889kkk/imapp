import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class MineSettingItem extends StatelessWidget {
  final String label;
  final TextStyle? textStyle;
  final String? value;
  final bool switchOn;
  final bool isTopRadius;
  final bool isBottomRadius;
  final bool showRightArrow;
  final bool showSwitchButton;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  const MineSettingItem({
    super.key,
    required this.label,
    this.textStyle,
    this.value,
    this.switchOn = false,
    this.isTopRadius = false,
    this.isBottomRadius = false,
    this.showRightArrow = false,
    this.showSwitchButton = false,
    this.onChanged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 10.w),
      child: Ink(
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(isTopRadius ? 6.r : 0),
            topLeft: Radius.circular(isTopRadius ? 6.r : 0),
            bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
            bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 46.h,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                label.toText..style = textStyle ?? Styles.ts_0C1C33_17sp,
                const Spacer(),
                if (showSwitchButton)
                  CupertinoSwitch(
                    value: switchOn,
                    activeColor: Styles.c_0089FF,
                    onChanged: onChanged,
                  ),
                if (value != null && value!.isNotEmpty)
                  value!.toText..style = Styles.ts_8E9AB0_14sp,
                if (showRightArrow)
                  ImageRes.rightArrow.toImage
                    ..width = 24.w
                    ..height = 24.h
                    ..color = Styles.c_8E9AB0,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
