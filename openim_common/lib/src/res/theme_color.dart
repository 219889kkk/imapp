import 'package:flutter/material.dart';
import 'package:openim_common/src/res/strings.dart';

class ThemeAccentColors {
  const ThemeAccentColors({
    required this.primary,
    required this.primaryWeak,
    required this.primaryContainer,
    required this.disabledBlue,
    required this.momentText,
    required this.bubbleSent,
    required this.bubbleSentLink,
    required this.bubbleUnread,
    required this.bubbleSentText,
    required this.noticeBanner,
  });

  final Color primary;
  final Color primaryWeak;
  final Color primaryContainer;
  final Color disabledBlue;
  final Color momentText;
  final Color bubbleSent;
  final Color bubbleSentLink;
  final Color bubbleUnread;
  final Color bubbleSentText;
  final Color noticeBanner;
}

class ThemeColorPresets {
  ThemeColorPresets._();

  static const defaultBlue = Color(0xFF5BA8D9);
  static const wechatGreen = Color(0xFF95EC69);
  static const orange = Color(0xFFFF9500);
  static const pink = Color(0xFFFF2D55);
  static const purple = Color(0xFFAF52DE);
  static const teal = Color(0xFF5AC8FA);

  static const List<Color> presets = [
    defaultBlue,
    wechatGreen,
    orange,
    pink,
    purple,
    teal,
  ];

  static bool isPreset(Color color) =>
      presets.any((preset) => preset.value == color.value);

  static String labelFor(Color color) {
    if (color.value == defaultBlue.value) return StrRes.themeColorBlue;
    if (color.value == wechatGreen.value) return StrRes.themeColorGreen;
    if (color.value == orange.value) return StrRes.themeColorOrange;
    if (color.value == pink.value) return StrRes.themeColorPink;
    if (color.value == purple.value) return StrRes.themeColorPurple;
    if (color.value == teal.value) return StrRes.themeColorTeal;
    return StrRes.themeColorCustom;
  }
}

class ThemeColorResolver {
  ThemeColorResolver._();

  static ThemeAccentColors resolve(Color seed, bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final hsl = HSLColor.fromColor(seed);
    final primary = dark
        ? hsl.withLightness((hsl.lightness + 0.05).clamp(0.0, 1.0)).toColor()
        : seed;
    final bubbleSent = dark
        ? hsl.withSaturation(0.35).withLightness(0.22).toColor()
        : seed;
    final bubbleSentLink = hsl
        .withSaturation(0.25)
        .withLightness(dark ? 0.62 : 0.42)
        .toColor();
    final primaryWeak = dark
        ? scheme.primaryContainer
        : Color.alphaBlend(seed.withOpacity(0.12), const Color(0xFFF8F9FA));
    final noticeBanner =
        dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFF9E6);

    return ThemeAccentColors(
      primary: primary,
      primaryWeak: primaryWeak,
      primaryContainer: scheme.primaryContainer,
      disabledBlue: hsl
          .withSaturation(0.35)
          .withLightness(dark ? 0.45 : 0.72)
          .toColor(),
      momentText: hsl
          .withSaturation(0.28)
          .withLightness(dark ? 0.68 : 0.52)
          .toColor(),
      bubbleSent: bubbleSent,
      bubbleSentLink: bubbleSentLink,
      bubbleUnread: bubbleSentLink,
      bubbleSentText: _contrastText(bubbleSent),
      noticeBanner: noticeBanner,
    );
  }

  static Color _contrastText(Color background) =>
      background.computeLuminance() > 0.55
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);
}
