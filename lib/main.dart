import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';

void main() {
  runZonedGuarded(() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Logger.print('FlutterError: ${details.exception.toString()}, ${details.stack.toString()}');
    };

    WidgetsFlutterBinding.ensureInitialized();
    // 预热液态玻璃 shader,避免底部 Dock 首帧白闪
    await LiquidGlassWidgets.initialize();
    Config.init(() => runApp(const ChatApp()));
  }, (error, stackTrace) {
    Logger.print('FlutterError: ${error.toString()}, ${stackTrace.toString()}', onlyConsole: true);
  });
}
