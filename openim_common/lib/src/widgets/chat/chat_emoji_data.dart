import 'package:flutter/material.dart';

class ChatEmojiCategory {
  const ChatEmojiCategory({
    required this.label,
    required this.icon,
    required this.items,
  });

  final String label;
  final IconData icon;
  final List<ChatEmojiItem> items;
}

class ChatEmojiItem {
  const ChatEmojiItem(this.emoji);

  final String emoji;

  String get asset => 'assets/emoji/twemoji/${twemojiAssetName(emoji)}.png';
}

String twemojiAssetName(String emoji) => emoji.runes
    .where((rune) => rune != 0xfe0f)
    .map((rune) => rune.toRadixString(16))
    .join('-');

List<ChatEmojiItem> _items(String emojis) =>
    emojis.split(' ').where((emoji) => emoji.isNotEmpty).map(ChatEmojiItem.new).toList();

final chatEmojiCategories = <ChatEmojiCategory>[
  ChatEmojiCategory(
    label: '常用',
    icon: Icons.access_time,
    items: _items(
      '😀 😂 🤣 😊 😍 🥰 😘 😭 😅 👍 👎 👏 🙏 ❤️ 🔥 ✅ ❌ 🤔 😴 😎 🤩 😢 😡 🤗 👌 ✌️ 🤝 💪 🎉 💯',
    ),
  ),
  ChatEmojiCategory(
    label: 'Smileys',
    icon: Icons.emoji_emotions_outlined,
    items: _items(
      '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 😶 😏',
    ),
  ),
  ChatEmojiCategory(
    label: 'Animals',
    icon: Icons.pets,
    items: _items(
      '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛',
    ),
  ),
  ChatEmojiCategory(
    label: 'Food',
    icon: Icons.fastfood_outlined,
    items: _items(
      '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🥑 🍆 🥔 🥕 🌽 🌶 🥒 🥬 🥦 🧄 🧅 🍄 🥜 🌰',
    ),
  ),
  ChatEmojiCategory(
    label: 'Activity',
    icon: Icons.sports_soccer,
    items: _items(
      '⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸ 🥌',
    ),
  ),
  ChatEmojiCategory(
    label: 'Travel',
    icon: Icons.directions_car_outlined,
    items: _items(
      '🚗 🚕 🚙 🚌 🚎 🏎 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🛵 🏍 🛺 🚲 🛴 🚁 ✈️ 🚀 🛸 🚤 ⛵️ 🚢 ⚓️ 🚧 🚦 🚥 🗺 🏔',
    ),
  ),
  ChatEmojiCategory(
    label: 'Objects',
    icon: Icons.lightbulb_outline,
    items: _items(
      '💡 🔦 🏮 🪔 📱 💻 ⌨️ 🖥 🖨 🖱 🖲 💽 💾 💿 📀 🧭 ⏱ ⏲ ⏰ ⌚️ 📷 📹 🎥 📞 ☎️ 📟 📠 📺 📻 🎙 🎚 🎛',
    ),
  ),
  ChatEmojiCategory(
    label: 'Symbols',
    icon: Icons.favorite_border,
    items: _items(
      '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉 ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎ ♈️ ♉️',
    ),
  ),
];
