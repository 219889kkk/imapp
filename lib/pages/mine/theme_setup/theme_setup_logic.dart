import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim_common/openim_common.dart';

class ThemeSetupLogic extends GetxController {
  final isFollowSystem = false.obs;
  final isLight = false.obs;
  final isDark = false.obs;
  final selectedColor = ThemeColorPresets.defaultBlue.obs;

  @override
  void onInit() {
    _initThemeSetting();
    selectedColor.value = Get.find<AppController>().getThemeColor();
    super.onInit();
  }

  void _initThemeSetting() {
    final themeMode = DataSp.getThemeMode();
    isFollowSystem.value = themeMode == 0;
    isLight.value = themeMode == 1;
    isDark.value = themeMode == 2;
  }

  Future<void> switchThemeMode(int index) async {
    await Get.find<AppController>().switchThemeMode(index);
    isFollowSystem.value = index == 0;
    isLight.value = index == 1;
    isDark.value = index == 2;
  }

  bool isPresetSelected(Color color) => selectedColor.value.value == color.value;

  bool get isCustomSelected => !ThemeColorPresets.isPreset(selectedColor.value);

  Future<void> selectColor(Color color) async {
    await Get.find<AppController>().switchThemeColor(color);
    selectedColor.value = color;
  }

  Future<void> openCustomPicker(BuildContext context) async {
    await ThemeColorPickerSheet.show(
      context,
      initialColor: selectedColor.value,
      onConfirm: selectColor,
    );
  }
}
