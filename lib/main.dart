import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:openim/core/home_debug.dart';
import 'package:openim/core/liquid_glass_runtime.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';

void main() {
  runZonedGuarded(() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      homeDebugError.value =
          '${details.exceptionAsString()}\n${details.stack}';
      Logger.print('FlutterError: ${details.exception}');
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      homeDebugError.value = details.exceptionAsString();
      return Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              '界面渲染错误（请截图发我）:\n\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ),
      );
    };

    WidgetsFlutterBinding.ensureInitialized();
    if (!Platform.isIOS) {
      try {
        await LiquidGlassWidgets.initialize();
        LiquidGlassRuntime.enabled = true;
      } catch (e, s) {
        LiquidGlassRuntime.enabled = false;
        Logger.print('LiquidGlassWidgets.initialize failed: $e $s');
      }
    } else {
      LiquidGlassRuntime.enabled = false;
    }
    Config.init(() => runApp(const ChatApp()));
  }, (error, stackTrace) {
    homeDebugError.value = '$error\n$stackTrace';
    Logger.print('Uncaught error: $error', onlyConsole: true);
    EasyLoading.dismiss();
    LoadingView.singleton.dismiss();
  });
}
