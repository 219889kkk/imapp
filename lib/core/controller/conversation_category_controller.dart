import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ConversationCategoryController extends GetxController {
  static const all = 'all';

  final config = ConversationCategoryConfig().obs;
  final selectedCategory = all.obs;

  bool get showTabs =>
      config.value.folderTabsEnabled &&
      (config.value.enabledAutoCategories.isNotEmpty ||
          config.value.customTags.isNotEmpty);

  List<String> get tabKeys => [
        all,
        ...config.value.enabledAutoCategories,
        ...config.value.customTags.map((e) => e.id),
      ];

  @override
  void onReady() {
    load();
    super.onReady();
  }

  Future<void> load() async {
    try {
      config.value = await Apis.getConversationCategoryConfig();
    } catch (e, s) {
      Logger.print('load conversation category error: e:$e s:$s');
    }
  }

  void selectCategory(String key) {
    if (selectedCategory.value == key) return;
    selectedCategory.value = key;
  }

  String labelOf(String key) {
    switch (key) {
      case all:
        return StrRes.allConversations;
      case ConversationAutoCategory.unread:
        return StrRes.unreadConversations;
      case ConversationAutoCategory.single:
        return StrRes.singleChats;
      case ConversationAutoCategory.group:
        return StrRes.groupChats;
      default:
        for (final tag in config.value.customTags) {
          if (tag.id == key) return tag.name;
        }
        return key;
    }
  }

  List<ConversationInfo> filter(List<ConversationInfo> source) {
    final key = selectedCategory.value;
    if (key == all) return source;
    switch (key) {
      case ConversationAutoCategory.unread:
        return source.where((e) => e.unreadCount > 0).toList();
      case ConversationAutoCategory.single:
        return source.where((e) => e.isSingleChat).toList();
      case ConversationAutoCategory.group:
        return source.where((e) => e.isGroupChat).toList();
      default:
        return source
            .where((e) =>
                config.value.conversationTags[e.conversationID]
                    ?.contains(key) ==
                true)
            .toList();
    }
  }

  List<ConversationTag> tagsOf(String conversationID) {
    final ids = config.value.conversationTags[conversationID] ?? [];
    return config.value.customTags.where((e) => ids.contains(e.id)).toList();
  }

  bool autoEnabled(String key) =>
      config.value.enabledAutoCategories.contains(key);

  Future<void> toggleFolderTabs(bool enabled) async {
    await _updateConfig(folderTabsEnabled: enabled);
  }

  Future<void> toggleAutoCategory(String key, bool enabled) async {
    final categories = [...config.value.enabledAutoCategories];
    enabled ? categories.add(key) : categories.remove(key);
    await _updateConfig(enabledAutoCategories: categories.toSet().toList());
  }

  Future<void> createTag() async {
    final name = await _input(StrRes.createTag);
    if (name == null || name.isEmpty) return;
    config.value = await Apis.createConversationTag(name: name);
  }

  Future<void> renameTag(ConversationTag tag) async {
    final name = await _input(StrRes.renameTag, text: tag.name);
    if (name == null || name.isEmpty) return;
    config.value = await Apis.renameConversationTag(
      tagID: tag.id,
      name: name,
    );
  }

  Future<void> deleteTag(ConversationTag tag) async {
    final confirm = await Get.dialog(CustomDialog(title: StrRes.delete));
    if (confirm != true) return;
    config.value = await Apis.deleteConversationTag(tagID: tag.id);
    if (selectedCategory.value == tag.id) {
      selectedCategory.value = all;
    }
  }

  Future<void> setTags(String conversationID, List<String> tagIDs) async {
    config.value = await Apis.setConversationTags(
      conversationID: conversationID,
      tagIDs: tagIDs,
    );
  }

  Future<void> _updateConfig({
    bool? folderTabsEnabled,
    List<String>? enabledAutoCategories,
  }) async {
    config.value = await Apis.updateConversationCategoryConfig(
      folderTabsEnabled: folderTabsEnabled ?? config.value.folderTabsEnabled,
      enabledAutoCategories:
          enabledAutoCategories ?? config.value.enabledAutoCategories,
      customTags: config.value.customTags,
    );
  }

  Future<String?> _input(String title, {String? text}) async {
    final inputCtrl = TextEditingController(text: text);
    final result = await Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: inputCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(StrRes.cancel),
          ),
          TextButton(
            onPressed: () => Get.back(result: inputCtrl.text.trim()),
            child: Text(StrRes.confirm),
          ),
        ],
      ),
    );
    inputCtrl.dispose();
    return result;
  }
}
