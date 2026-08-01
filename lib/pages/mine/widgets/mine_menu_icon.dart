import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

enum MineMenuIconType {
  myInfo,
  chatNotification,
  privacySecurity,
  appearanceLanguage,
  discover,
  aboutUs,
  logout,
}

class MineMenuIcon extends StatelessWidget {
  final MineMenuIconType type;

  const MineMenuIcon({super.key, required this.type});

  Color get _accentColor => switch (type) {
        MineMenuIconType.logout => Styles.c_FF381F,
        _ => Styles.c_0089FF,
      };

  String get _svgPath => switch (type) {
        MineMenuIconType.myInfo => IconRes.mineMyInfo,
        MineMenuIconType.chatNotification => IconRes.mineChatNotification,
        MineMenuIconType.privacySecurity => IconRes.minePrivacySecurity,
        MineMenuIconType.appearanceLanguage => IconRes.mineAppearanceLanguage,
        MineMenuIconType.discover => IconRes.mineDiscover,
        MineMenuIconType.aboutUs => IconRes.mineAboutUs,
        MineMenuIconType.logout => IconRes.mineLogout,
      };

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor;
    return SizedBox(
      width: 24.w,
      height: 24.w,
      child: _svgPath.toSvgIcon
        ..width = 24.w
        ..height = 24.w
        ..color = accentColor,
    );
  }
}
