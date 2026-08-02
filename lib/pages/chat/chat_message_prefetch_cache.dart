import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

class PrefetchedChatMessages {
  const PrefetchedChatMessages({
    required this.messages,
    required this.isEnd,
  });

  final List<Message> messages;
  final bool isEnd;
}

class ChatMessagePrefetchCache {
  ChatMessagePrefetchCache._();

  static const int pageSize = 40;
  static const int _maxEntries = 12;

  static final _cache = <String, PrefetchedChatMessages>{};
  static final _inFlight = <String, Future<PrefetchedChatMessages>>{};

  static String _key(ConversationInfo conversationInfo) =>
      conversationInfo.conversationID;

  static PrefetchedChatMessages? peek(ConversationInfo conversationInfo) {
    final key = _key(conversationInfo);
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  static void invalidate(ConversationInfo conversationInfo) {
    _cache.remove(_key(conversationInfo));
  }

  static Future<PrefetchedChatMessages> prefetch(
    ConversationInfo conversationInfo,
  ) {
    final key = _key(conversationInfo);
    final cached = peek(conversationInfo);
    // Skip empty cache so a race during sync cannot stick forever.
    if (cached != null && cached.messages.isNotEmpty) {
      return Future.value(cached);
    }
    if (cached != null && cached.messages.isEmpty && cached.isEnd) {
      return Future.value(cached);
    }

    final running = _inFlight[key];
    if (running != null) return running;

    final future = OpenIM.iMManager.messageManager
        .getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: pageSize,
      startMsg: null,
    )
        .then((result) {
      final value = PrefetchedChatMessages(
        messages: List<Message>.of(result.messageList ?? const []),
        isEnd: result.isEnd == true,
      );
      // Only cache non-empty or confirmed end results.
      if (value.messages.isNotEmpty || value.isEnd) {
        _put(key, value);
      }
      return value;
    }).catchError((Object error, StackTrace stackTrace) {
      Logger.print('prefetch chat messages failed: $key, $error');
      throw error;
    }).whenComplete(() {
      _inFlight.remove(key);
    });

    _inFlight[key] = future;
    return future;
  }

  static void _put(String key, PrefetchedChatMessages value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
