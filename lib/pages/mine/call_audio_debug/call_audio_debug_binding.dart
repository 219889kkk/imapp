import 'package:get/get.dart';

import 'call_audio_debug_logic.dart';

class CallAudioDebugBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => CallAudioDebugLogic());
  }
}
