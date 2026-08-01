import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'theme_color.dart';

class Styles {
  Styles._();

  /// Package fonts need the package prefix when referenced by the host app.
  static const emojiFontFamily = 'packages/openim_common/NotoColorEmoji';

  static bool isDark = false;

  static Color _accentSeed = ThemeColorPresets.defaultBlue;
  static _StylePalette? _lightPalette;
  static _StylePalette? _darkPalette;

  static _StylePalette get _p =>
      isDark ? (_darkPalette ?? _buildPalette(true)) : (_lightPalette ?? _buildPalette(false));

  static _StylePalette palette(bool dark) =>
      dark ? (_darkPalette ?? _buildPalette(true)) : (_lightPalette ?? _buildPalette(false));

  static void updateAccentColor(Color color) {
    _accentSeed = color;
    _lightPalette = _buildPalette(false);
    _darkPalette = _buildPalette(true);
  }

  static Color get accentSeed => _accentSeed;

  static void updateThemeMode(ThemeMode mode, Brightness platformBrightness) {
    isDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
  }

  static _StylePalette _buildPalette(bool dark) {
    final base = dark ? _StylePalette.darkBase : _StylePalette.lightBase;
    final accent = ThemeColorResolver.resolve(_accentSeed, dark);
    return _StylePalette(
      primary: accent.primary,
      textPrimary: base.textPrimary,
      textSecondary: base.textSecondary,
      textTertiary: base.textTertiary,
      divider: base.divider,
      danger: base.danger,
      surface: base.surface,
      success: base.success,
      input: base.input,
      disabledBlue: accent.disabledBlue,
      primaryWeak: accent.primaryWeak,
      primaryContainer: accent.primaryContainer,
      page: base.page,
      insetBackground: base.insetBackground,
      groupedSeparator: base.groupedSeparator,
      momentText: accent.momentText,
      warning: base.warning,
      dangerWeak: base.dangerWeak,
      neutral: base.neutral,
      surfaceVariant: base.surfaceVariant,
      bubbleSent: accent.bubbleSent,
      bubbleReceived: base.bubbleReceived,
      bubbleSentLink: accent.bubbleSentLink,
      bubbleUnread: accent.bubbleUnread,
      bubbleSentText: accent.bubbleSentText,
      textInverse: base.textInverse,
      onDark: base.onDark,
      popoverBackground: base.popoverBackground,
      toastBackground: base.toastBackground,
      toastText: base.toastText,
      scrim: base.scrim,
      shadow: base.shadow,
      noticeBanner: accent.noticeBanner,
    );
  }

  static Color get pageBackground => c_F8F9FA;
  static Color get cardBackground => c_FFFFFF;
  static Color get inputBackground => c_F0F2F6;
  static Color get textPrimary => c_0C1C33;
  static Color get textSecondary => c_8E9AB0;
  static Color get textTertiary => _p.textTertiary;
  static Color get divider => c_E8EAEF;
  static Color get insetBackground => _p.insetBackground;
  static Color get groupedSeparator => _p.groupedSeparator;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onDark => _p.onDark;
  static Color get popoverBackground => _p.popoverBackground;
  static Color get toastBackground => _p.toastBackground;
  static Color get toastText => _p.toastText;
  static Color get scrim => _p.scrim;
  static Color get shadow => _p.shadow;
  static Color get noticeBanner => _p.noticeBanner;
  static Color get bubbleReceived => _p.bubbleReceived;
  static Color get bubbleSentLink => _p.bubbleSentLink;
  static Color get bubbleUnread => _p.bubbleUnread;
  static Color get bubbleSentText => _p.bubbleSentText;

  static Color get c_0089FF => _p.primary;
  static Color get c_0C1C33 => _p.textPrimary;
  static Color get c_8E9AB0 => _p.textSecondary;
  static Color get c_E8EAEF => _p.divider;
  static Color get c_FF381F => _p.danger;
  static Color get c_FFFFFF => _p.surface;
  static Color get c_18E875 => _p.success;
  static Color get c_F0F2F6 => _p.input;
  static Color get c_000000 => const Color(0xFF000000);
  static Color get c_92B3E0 => _p.disabledBlue;
  static Color get c_F2F8FF => _p.primaryWeak;
  static Color get c_F8F9FA => _p.page;
  static Color get c_6085B1 => _p.momentText;
  static Color get c_FFB300 => _p.warning;
  static Color get c_FFE1DD => _p.dangerWeak;
  static Color get c_707070 => _p.neutral;

  static Color get c_92B3E0_opacity50 => c_92B3E0.withOpacity(.5);
  static Color get c_E8EAEF_opacity50 => c_E8EAEF.withOpacity(.5);
  static Color get c_F4F5F7 => _p.surfaceVariant;
  static Color get c_CCE7FE => _p.bubbleSent;

  static Color get c_FFFFFF_opacity0 => c_FFFFFF.withOpacity(.0);
  static Color get c_FFFFFF_opacity70 => c_FFFFFF.withOpacity(.7);
  static Color get c_FFFFFF_opacity50 => c_FFFFFF.withOpacity(.5);
  static Color get onDark_opacity50 => onDark.withOpacity(.5);
  static Color get onDark_opacity70 => onDark.withOpacity(.7);
  static Color get c_0089FF_opacity10 => c_0089FF.withOpacity(.1);
  static Color get c_0089FF_opacity20 => c_0089FF.withOpacity(.2);
  static Color get c_0089FF_opacity50 => c_0089FF.withOpacity(.5);
  static Color get c_FF381F_opacity10 => c_FF381F.withOpacity(.1);
  static Color get c_8E9AB0_opacity13 => c_8E9AB0.withOpacity(.13);
  static Color get c_8E9AB0_opacity15 => c_8E9AB0.withOpacity(.15);
  static Color get c_8E9AB0_opacity16 => c_8E9AB0.withOpacity(.16);
  static Color get c_8E9AB0_opacity30 => c_8E9AB0.withOpacity(.3);
  static Color get c_8E9AB0_opacity50 => c_8E9AB0.withOpacity(.5);
  static Color get c_0C1C33_opacity30 => c_0C1C33.withOpacity(.3);
  static Color get c_0C1C33_opacity60 => c_0C1C33.withOpacity(.6);
  static Color get c_0C1C33_opacity85 => c_0C1C33.withOpacity(.85);
  static Color get c_0C1C33_opacity80 => c_0C1C33.withOpacity(.8);
  static Color get c_FF381F_opacity70 => c_FF381F.withOpacity(.7);
  static Color get c_000000_opacity70 => scrim;
  static Color get c_000000_opacity15 => c_000000.withOpacity(.15);
  static Color get c_000000_opacity12 => c_000000.withOpacity(.12);
  static Color get c_000000_opacity4 => shadow;

  static TextStyle _text(Color color, double size, [FontWeight? weight]) =>
      TextStyle(color: color, fontSize: size.sp, fontWeight: weight);

  static Color get _whiteText => _p.textInverse;

  static TextStyle get ts_FFFFFF_21sp => _text(_whiteText, 21);
  static TextStyle get ts_FFFFFF_20sp_medium => _text(_whiteText, 20, FontWeight.w500);
  static TextStyle get ts_FFFFFF_18sp_medium => _text(_whiteText, 18, FontWeight.w500);
  static TextStyle get ts_FFFFFF_17sp => _text(_whiteText, 17);
  static TextStyle get ts_FFFFFF_opacity70_17sp => _text(_whiteText.withOpacity(.7), 17);
  static TextStyle get ts_FFFFFF_17sp_semibold => _text(_whiteText, 17, FontWeight.w600);
  static TextStyle get ts_FFFFFF_17sp_medium => _text(_whiteText, 17, FontWeight.w500);
  static TextStyle get ts_FFFFFF_16sp => _text(_whiteText, 16);
  static TextStyle get ts_FFFFFF_14sp => _text(_whiteText, 14);
  static TextStyle get ts_FFFFFF_opacity70_14sp => _text(_whiteText.withOpacity(.7), 14);
  static TextStyle get ts_FFFFFF_14sp_medium => _text(_whiteText, 14, FontWeight.w500);
  static TextStyle get ts_FFFFFF_12sp => _text(_whiteText, 12);
  static TextStyle get ts_FFFFFF_10sp => _text(_whiteText, 10);

  static TextStyle get ts_8E9AB0_10sp_semibold => _text(c_8E9AB0, 10, FontWeight.w600);
  static TextStyle get ts_8E9AB0_10sp => _text(c_8E9AB0, 10);
  static TextStyle get ts_8E9AB0_12sp => _text(c_8E9AB0, 12);
  static TextStyle get ts_8E9AB0_13sp => _text(c_8E9AB0, 13);
  static TextStyle get ts_8E9AB0_14sp => _text(c_8E9AB0, 14);
  static TextStyle get ts_8E9AB0_15sp => _text(c_8E9AB0, 15);
  static TextStyle get ts_8E9AB0_16sp => _text(c_8E9AB0, 16);
  static TextStyle get ts_8E9AB0_17sp => _text(c_8E9AB0, 17);
  static TextStyle get ts_8E9AB0_opacity50_17sp => _text(c_8E9AB0_opacity50, 17);

  static TextStyle get ts_0C1C33_10sp => _text(c_0C1C33, 10);
  static TextStyle get ts_0C1C33_12sp => _text(c_0C1C33, 12);
  static TextStyle get ts_0C1C33_12sp_medium => _text(c_0C1C33, 12, FontWeight.w500);
  static TextStyle get ts_0C1C33_14sp => _text(c_0C1C33, 14);
  static TextStyle get ts_0C1C33_14sp_medium => _text(c_0C1C33, 14, FontWeight.w500);
  static TextStyle get ts_0C1C33_17sp => _text(c_0C1C33, 17);
  static TextStyle get ts_0C1C33_17sp_medium => _text(c_0C1C33, 17, FontWeight.w500);
  static TextStyle get ts_0C1C33_17sp_semibold => _text(c_0C1C33, 17, FontWeight.w600);
  static TextStyle get ts_0C1C33_20sp => _text(c_0C1C33, 20);
  static TextStyle get ts_0C1C33_20sp_medium => _text(c_0C1C33, 20, FontWeight.w500);
  static TextStyle get ts_0C1C33_20sp_semibold => _text(c_0C1C33, 20, FontWeight.w600);

  static TextStyle get ts_0089FF_10sp_semibold => _text(c_0089FF, 10, FontWeight.w600);
  static TextStyle get ts_0089FF_10sp => _text(c_0089FF, 10);
  static TextStyle get ts_0089FF_12sp => _text(c_0089FF, 12);
  static TextStyle get ts_0089FF_14sp => _text(c_0089FF, 14);
  static TextStyle get ts_0089FF_16sp => _text(c_0089FF, 16);
  static TextStyle get ts_0089FF_16sp_medium => _text(c_0089FF, 16, FontWeight.w500);
  static TextStyle get ts_0089FF_17sp => _text(c_0089FF, 17);
  static TextStyle get ts_0089FF_17sp_semibold => _text(c_0089FF, 17, FontWeight.w600);
  static TextStyle get ts_0089FF_17sp_medium => _text(c_0089FF, 17, FontWeight.w500);
  static TextStyle get ts_0089FF_14sp_medium => _text(c_0089FF, 14, FontWeight.w500);
  static TextStyle get ts_0089FF_22sp_semibold => _text(c_0089FF, 22, FontWeight.w600);

  static TextStyle get ts_FF381F_17sp => _text(c_FF381F, 17);
  static TextStyle get ts_FF381F_14sp => _text(c_FF381F, 14);
  static TextStyle get ts_FF381F_12sp => _text(c_FF381F, 12);
  static TextStyle get ts_FF381F_10sp => _text(c_FF381F, 10);

  static TextStyle get ts_6085B1_17sp_medium => _text(c_6085B1, 17, FontWeight.w500);
  static TextStyle get ts_6085B1_17sp => _text(c_6085B1, 17);
  static TextStyle get ts_6085B1_12sp => _text(c_6085B1, 12);
  static TextStyle get ts_6085B1_14sp => _text(c_6085B1, 14);

  static TextStyle get ts_bubbleSentLink_17sp => _text(bubbleSentLink, 17);
  static TextStyle get ts_bubbleSentText_17sp => _text(bubbleSentText, 17);
  static TextStyle get ts_bubbleSentText_14sp => _text(bubbleSentText, 14);
  static TextStyle get ts_bubbleUnread_12sp => _text(bubbleUnread, 12);
}

class _StylePalette {
  const _StylePalette({
    required this.primary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.danger,
    required this.surface,
    required this.success,
    required this.input,
    required this.disabledBlue,
    required this.primaryWeak,
    required this.primaryContainer,
    required this.page,
    required this.insetBackground,
    required this.groupedSeparator,
    required this.momentText,
    required this.warning,
    required this.dangerWeak,
    required this.neutral,
    required this.surfaceVariant,
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.bubbleSentLink,
    required this.bubbleUnread,
    required this.bubbleSentText,
    required this.textInverse,
    required this.onDark,
    required this.popoverBackground,
    required this.toastBackground,
    required this.toastText,
    required this.scrim,
    required this.shadow,
    required this.noticeBanner,
  });

  final Color primary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color danger;
  final Color surface;
  final Color success;
  final Color input;
  final Color disabledBlue;
  final Color primaryWeak;
  final Color primaryContainer;
  final Color page;
  final Color insetBackground;
  final Color groupedSeparator;
  final Color momentText;
  final Color warning;
  final Color dangerWeak;
  final Color neutral;
  final Color surfaceVariant;
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color bubbleSentLink;
  final Color bubbleUnread;
  final Color bubbleSentText;
  final Color textInverse;
  final Color onDark;
  final Color popoverBackground;
  final Color toastBackground;
  final Color toastText;
  final Color scrim;
  final Color shadow;
  final Color noticeBanner;

  static const lightBase = _StylePalette(
    primary: Color(0xFF0089FF),
    textPrimary: Color(0xFF0C1C33),
    textSecondary: Color(0xFF8E9AB0),
    textTertiary: Color(0xFF8E9AB0),
    divider: Color(0xFFE8EAEF),
    danger: Color(0xFFFF381F),
    surface: Color(0xFFFFFFFF),
    success: Color(0xFF18E875),
    input: Color(0xFFF0F2F6),
    disabledBlue: Color(0xFF92B3E0),
    primaryWeak: Color(0xFFF2F8FF),
    primaryContainer: Color(0xFFF2F8FF),
    page: Color(0xFFF8F9FA),
    insetBackground: Color(0xFFF8F9FA),
    groupedSeparator: Color(0xFFF8F9FA),
    momentText: Color(0xFF6085B1),
    warning: Color(0xFFFFB300),
    dangerWeak: Color(0xFFFFE1DD),
    neutral: Color(0xFF707070),
    surfaceVariant: Color(0xFFF4F5F7),
    bubbleSent: Color(0xFF95EC69),
    bubbleReceived: Color(0xFFFFFFFF),
    bubbleSentLink: Color(0xFF576B95),
    bubbleUnread: Color(0xFF576B95),
    bubbleSentText: Color(0xFF000000),
    textInverse: Color(0xFFFFFFFF),
    onDark: Color(0xFFFFFFFF),
    popoverBackground: Color(0xD90C1C33),
    toastBackground: Color(0xD90C1C33),
    toastText: Color(0xFFFFFFFF),
    scrim: Color(0x80000000),
    shadow: Color(0x0A000000),
    noticeBanner: Color(0xFFF2F8FF),
  );

  static const darkBase = _StylePalette(
    primary: Color(0xFF0A95FF),
    textPrimary: Color(0xFFE6EAF2),
    textSecondary: Color(0xFFA8B3C7),
    textTertiary: Color(0xFFA8B3C7),
    divider: Color(0xFF48484A),
    danger: Color(0xFFFF453A),
    surface: Color(0xFF1C1C1E),
    success: Color(0xFF30D158),
    input: Color(0xFF3A3A3C),
    disabledBlue: Color(0xFF526985),
    primaryWeak: Color(0xFF0B2238),
    primaryContainer: Color(0xFF1A3A5C),
    page: Color(0xFF000000),
    insetBackground: Color(0xFF2C2C2E),
    groupedSeparator: Color(0xFF000000),
    momentText: Color(0xFF9BBBE0),
    warning: Color(0xFFFFC542),
    dangerWeak: Color(0xFF3A1D1A),
    neutral: Color(0xFFA0A0A0),
    surfaceVariant: Color(0xFF2C2C2E),
    bubbleSent: Color(0xFF2F5939),
    bubbleReceived: Color(0xFF2C2C2C),
    bubbleSentLink: Color(0xFF7D90A9),
    bubbleUnread: Color(0xFF7D90A9),
    bubbleSentText: Color(0xFFFFFFFF),
    textInverse: Color(0xFFFFFFFF),
    onDark: Color(0xFFFFFFFF),
    popoverBackground: Color(0xD90C1C33),
    toastBackground: Color(0xE62C2C2E),
    toastText: Color(0xFFE6EAF2),
    scrim: Color(0xB3000000),
    shadow: Color(0x14FFFFFF),
    noticeBanner: Color(0xFF1C1C1E),
  );
}
