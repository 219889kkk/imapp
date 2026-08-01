class ConversationAutoCategory {
  static const unread = 'unread';
  static const single = 'single';
  static const group = 'group';
}

class ConversationTag {
  ConversationTag({
    required this.id,
    required this.name,
    required this.sort,
  });

  factory ConversationTag.fromJson(Map<String, dynamic> json) =>
      ConversationTag(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        sort: json['sort'] ?? 0,
      );

  final String id;
  String name;
  int sort;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort': sort,
      };
}

class ConversationCategoryConfig {
  ConversationCategoryConfig({
    this.folderTabsEnabled = true,
    List<String>? enabledAutoCategories,
    List<ConversationTag>? customTags,
    Map<String, List<String>>? conversationTags,
  })  : enabledAutoCategories = enabledAutoCategories ?? [],
        customTags = customTags ?? [],
        conversationTags = conversationTags ?? {};

  factory ConversationCategoryConfig.fromJson(Map<String, dynamic> json) {
    final rawConversationTags = json['conversationTags'];
    final conversationTags = <String, List<String>>{};
    if (rawConversationTags is Map) {
      rawConversationTags.forEach((key, value) {
        if (value is List) {
          conversationTags[key.toString()] =
              value.map((e) => e.toString()).toList();
        }
      });
    }

    return ConversationCategoryConfig(
      folderTabsEnabled: json['folderTabsEnabled'] != false,
      enabledAutoCategories: _toStringList(json['enabledAutoCategories']),
      customTags: _toList(json['customTags'], ConversationTag.fromJson),
      conversationTags: conversationTags,
    );
  }

  bool folderTabsEnabled;
  List<String> enabledAutoCategories;
  List<ConversationTag> customTags;
  Map<String, List<String>> conversationTags;

  Map<String, dynamic> toJson() => {
        'folderTabsEnabled': folderTabsEnabled,
        'enabledAutoCategories': enabledAutoCategories,
        'customTags': customTags.map((e) => e.toJson()).toList(),
      };
}

List<T> _toList<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((e) => convert(Map<String, dynamic>.from(e)))
      .toList();
}

List<String> _toStringList(dynamic value) {
  if (value is! List) return [];
  return value.map((e) => e.toString()).toList();
}
