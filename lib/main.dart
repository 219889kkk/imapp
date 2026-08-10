import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:livekit_client/livekit_client.dart';
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
    if (Platform.isIOS || Platform.isAndroid) {
      await LiveKitClient.initialize();
    }
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
    Logger.print('Uncaught error: $error', onlyConsole: true);
    EasyLoading.dismiss();
    LoadingView.singleton.dismiss();
  });
}
