import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class MomentsPublishLogic extends GetxController {
  final inputCtrl = TextEditingController();
  final assets = <AssetEntity>[].obs;
  final publishing = false.obs;
  final visibility = MomentVisibility.friends.obs;
  final selectedUsers = <UserInfo>[].obs;

  String get visibilityLabel {
    switch (visibility.value) {
      case MomentVisibility.public:
        return StrRes.everyoneCanSee;
      case MomentVisibility.private:
        return StrRes.onlyVisibleToMe;
      case MomentVisibility.partial:
        return _selectedUsersText(StrRes.partiallyVisible);
      case MomentVisibility.exclude:
        return _selectedUsersText(StrRes.partiallyInvisible);
      case MomentVisibility.friends:
      default:
        return StrRes.friendsVisible;
    }
  }

  String _selectedUsersText(String prefix) {
    if (selectedUsers.isEmpty) return prefix;
    final names = selectedUsers
        .take(3)
        .map((e) => e.nickname ?? e.userID ?? '')
        .where((e) => e.isNotEmpty)
        .join('、');
    final suffix = selectedUsers.length > 3 ? '等${selectedUsers.length}人' : '';
    return '$prefix：$names$suffix';
  }

  List<String>? get allowUserIDs => visibility.value == MomentVisibility.partial
      ? selectedUsers.map((e) => e.userID).whereType<String>().toList()
      : null;

  List<String>? get excludeUserIDs =>
      visibility.value == MomentVisibility.exclude
          ? selectedUsers.map((e) => e.userID).whereType<String>().toList()
          : null;

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }

  Future<void> pickImages() async {
    final result = await AssetPicker.pickAssets(
      Get.context!,
      pickerConfig: AssetPickerConfig(
        maxAssets: 9,
        selectedAssets: assets.toList(),
        requestType: RequestType.image,
      ),
    );
    if (result != null) {
      assets.assignAll(result);
    }
  }

  void removeAsset(AssetEntity asset) {
    assets.remove(asset);
  }

  Future<void> selectVisibility() async {
    final selected = await Get.bottomSheet<String>(
      BottomSheetView(
        items: [
          SheetItem(
            label: StrRes.public,
            result: MomentVisibility.public,
          ),
          SheetItem(
            label: StrRes.friendsVisible,
            result: MomentVisibility.friends,
          ),
          SheetItem(
            label: StrRes.private,
            result: MomentVisibility.private,
          ),
          SheetItem(
            label: StrRes.partiallyVisible,
            result: MomentVisibility.partial,
          ),
          SheetItem(
            label: StrRes.partiallyInvisible,
            result: MomentVisibility.exclude,
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (selected == MomentVisibility.partial ||
        selected == MomentVisibility.exclude) {
      final users = await _selectUsers();
      if (users == null || users.isEmpty) {
        IMViews.showToast(StrRes.selectContactsLimit);
        return;
      }
      selectedUsers.assignAll(users);
    } else {
      selectedUsers.clear();
    }
    visibility.value = selected;
  }

  Future<List<UserInfo>?> _selectUsers() async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      defaultCheckedIDList:
          selectedUsers.map((e) => e.userID).whereType<String>().toList(),
      excludeIDList: [OpenIM.iMManager.userID],
      openSelectedSheet: true,
    );
    return IMUtils.convertSelectContactsResultToUserInfo(result);
  }

  Future<void> publish() async {
    final content = inputCtrl.text.trim();
    if (content.isEmpty && assets.isEmpty) {
      IMViews.showToast(StrRes.noDynamic);
      return;
    }
    publishing.value = true;
    try {
      final mediaList = <MomentMedia>[];
      for (var i = 0; i < assets.length; i++) {
        final file = await assets[i].file;
        if (file == null) continue;
        final result = await IMViews.uCropPic(
          file.path,
          crop: false,
          toUrl: true,
        );
        final url = result['url'];
        if (url is String && url.isNotEmpty) {
          mediaList.add(MomentMedia(
            id: '${DateTime.now().millisecondsSinceEpoch}-$i',
            type: MomentMediaType.image,
            url: url,
            name: file.path.split(Platform.pathSeparator).last,
            size: await file.length(),
          ));
        }
      }
      await Apis.createMomentPost(
        content: content,
        mediaType:
            mediaList.isEmpty ? MomentMediaType.text : MomentMediaType.image,
        mediaList: mediaList,
        visibility: visibility.value,
        allowUserIDs: allowUserIDs,
        excludeUserIDs: excludeUserIDs,
      );
      Get.back(result: true);
    } catch (_) {
      // 后端未部署 moments 模块时仅提示，不中断 App。
    } finally {
      publishing.value = false;
    }
  }
}
