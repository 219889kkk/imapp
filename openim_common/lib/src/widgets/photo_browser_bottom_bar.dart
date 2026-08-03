import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

enum OperateType {
  forward,
  save,
  edit,
}

class PhotoBrowserBottomBar extends StatelessWidget {
  PhotoBrowserBottomBar({
    super.key,
    this.onPressedButton,
    this.onlySave = false,
    this.showEdit = false,
  });

  final ValueChanged<OperateType>? onPressedButton;
  final bool onlySave;
  final bool showEdit;

  static void show(
    BuildContext context, {
    bool onlySave = false,
    bool showEdit = false,
    ValueChanged<OperateType>? onPressedButton,
  }) {
    showModalBottomSheet(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      context: context,
      builder: (context) {
        return PhotoBrowserBottomBar(
          onPressedButton: onPressedButton,
          onlySave: onlySave,
          showEdit: showEdit,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildBar(context);
  }

  Widget _buildBar(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 142),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F2F6),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8.0),
          topRight: Radius.circular(8.0),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (!onlySave)
                _buildItem(ImageRes.forwardIcon.toImage, StrRes.menuForward,
                    onPressed: () {
                  Navigator.of(context).pop();
                  onPressedButton?.call(OperateType.forward);
                }),
              if (showEdit)
                _buildItem(
                    const Icon(Icons.edit, size: 22, color: Color(0xFF0C1C33)),
                    StrRes.editDoodle, onPressed: () {
                  Navigator.of(context).pop();
                  onPressedButton?.call(OperateType.edit);
                }),
              _buildItem(
                  ImageRes.saveIcon.toImage
                    ..width = 20
                    ..height = 20,
                  StrRes.save, onPressed: () {
                Navigator.of(context).pop();
                onPressedButton?.call(OperateType.save);
              })
            ],
          ),
          Divider(height: 6.h),
          ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width, maxHeight: 40.h),
            child: CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 40.h,
                child: Text(StrRes.cancel, style: Styles.ts_0C1C33_12sp),
                onPressed: () {
                  Navigator.of(context).pop();
                }),
          )
        ],
      ),
    );
  }

  Widget _buildItem(Widget icon, String title, {VoidCallback? onPressed}) {
    return Column(children: [
      CupertinoButton(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Container(
            decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.all(Radius.circular(5))),
            height: 48,
            width: 48,
            child: Center(child: icon),
          ),
          onPressed: onPressed),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Styles.ts_0C1C33_10sp,
      )
    ]);
  }
}
