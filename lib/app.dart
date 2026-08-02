import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'core/controller/im_controller.dart';
import 'routes/app_pages.dart';
import 'widgets/app_view.dart';

class ChatApp extends StatelessWidget {
  const ChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppView(
      builder: (locale, themeMode, builder) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        enableLog: false,
        builder: builder,
        translations: TranslationService(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        fallbackLocale: TranslationService.fallbackLocale,
        locale: locale,
        localeResolutionCallback: (locale, list) {
          Get.locale ??= locale;
          return locale;
        },
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        getPages: AppPages.routes,
        initialBinding: InitBinding(),
        initialRoute: AppRoutes.splash,
        theme: _themeData(false),
        darkTheme: _themeData(true),
        themeMode: themeMode,
      ),
    );
  }

  ThemeData _themeData(bool dark) {
    final p = Styles.palette(dark);
    final bg = p.page;
    final surface = p.surface;
    final text = p.textPrimary;
    final disabled = p.input;
    final track = p.surfaceVariant;

    return (dark ? ThemeData.dark() : ThemeData.light()).copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.primary,
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: p.primary,
        surface: surface,
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: p.primary),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabled;
          }
          if (states.contains(WidgetState.selected)) {
            return p.primary;
          }
          return surface;
        }),
        side: BorderSide(
            color: dark ? p.divider : Colors.grey.shade500, width: 1),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.0),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 16.sp,
              color: text,
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(text),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: track,
        circularTrackColor: track,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        primaryColor: p.primary,
        barBackgroundColor: surface,
        applyThemeToAll: true,
        textTheme: CupertinoTextThemeData(
          navActionTextStyle: TextStyle(color: text, fontSize: 17.sp),
          actionTextStyle: TextStyle(color: p.primary, fontSize: 17.sp),
          textStyle: TextStyle(color: text, fontSize: 17.sp),
          navLargeTitleTextStyle: TextStyle(color: text, fontSize: 20.sp),
          navTitleTextStyle: TextStyle(color: text, fontSize: 17.sp),
          pickerTextStyle: TextStyle(color: text, fontSize: 17.sp),
          tabLabelTextStyle: TextStyle(color: text, fontSize: 17.sp),
          dateTimePickerTextStyle: TextStyle(color: text, fontSize: 17.sp),
        ),
      ),
    );
  }
}

class InitBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<IMController>(IMController());
    Get.put<PushController>(PushController());
    Get.put<CacheController>(CacheController());
  }
}
