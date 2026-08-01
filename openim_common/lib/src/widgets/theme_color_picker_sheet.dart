import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ThemeColorPickerSheet extends StatefulWidget {
  const ThemeColorPickerSheet({
    super.key,
    required this.initialColor,
    required this.onConfirm,
  });

  final Color initialColor;
  final ValueChanged<Color> onConfirm;

  static Future<void> show(
    BuildContext context, {
    required Color initialColor,
    required ValueChanged<Color> onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Styles.c_FFFFFF,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
      ),
      builder: (_) => ThemeColorPickerSheet(
        initialColor: initialColor,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<ThemeColorPickerSheet> createState() => _ThemeColorPickerSheetState();
}

class _ThemeColorPickerSheetState extends State<ThemeColorPickerSheet> {
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StrRes.themeColorCustom.toText..style = Styles.ts_0C1C33_17sp_semibold,
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: StrRes.cancel.toText..style = Styles.ts_8E9AB0_17sp,
                ),
              ],
            ),
            16.verticalSpace,
            ColorPicker(
              color: _color,
              onColorChanged: (color) => setState(() => _color = color),
              pickersEnabled: const {
                ColorPickerType.wheel: true,
                ColorPickerType.primary: false,
                ColorPickerType.accent: false,
              },
              enableShadesSelection: false,
              width: 44,
              height: 44,
              borderRadius: 22,
            ),
            20.verticalSpace,
            Button(
              text: StrRes.confirm,
              onTap: () {
                widget.onConfirm(_color);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
