import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim/core/liquid_glass_runtime.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';

void main() {
  runZonedGuarded(() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Logger.print('FlutterError: ${details.exception}');
    };

    WidgetsFlutterBinding.ensureInitialized();
    // Shader init can SIGSEGV on OriginOS / Android 15; UI never required it.
    LiquidGlassRuntime.enabled = false;
    Config.init(() => runApp(const ChatApp()));
  }, (error, stackTrace) {
    Logger.print('Uncaught error: $error', onlyConsole: true);
    EasyLoading.dismiss();
    LoadingView.singleton.dismiss();
  });
}
