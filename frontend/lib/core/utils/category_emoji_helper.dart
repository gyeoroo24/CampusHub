/// Utility for managing consistent category emojis and clean names across CampusHub.
///
/// Rules:
/// - In Module pages (Buy & Sell feed, Lost & Found feed): Display with emoji.
/// - In Admin / Moderator panel: Display clean text without emoji.
/// - If a user enters an emoji in the name, it is preserved for feeds and stripped in admin panel.
class CategoryEmojiHelper {
  static final RegExp _leadingEmojiRegex = RegExp(
    r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}\s]+',
    unicode: true,
  );

  static const Map<String, String> _knownCategoryEmojis = {
    'all': '✨',
    'books': '📚',
    'books & notes': '📚',
    'cycles': '🚲',
    'bicycle': '🚲',
    'electronics': '💻',
    'furniture': '🪑',
    'lab equipment': '🔬',
    'lab': '🔬',
    'stationery': '📝',
    'notes': '📝',
    'clothing': '👕',
    'sports & fitness': '🏸',
    'sports': '🏸',
    'kitchen & appliances': '🍳',
    'kitchen': '🍳',
    'id cards & wallets': '🪪',
    'id card': '🪪',
    'keys': '🔑',
    'bags & backpacks': '🎒',
    'bags': '🎒',
    'bottle': '🍼',
    'flower': '🌸',
    'others': '📦',
  };

  /// Returns clean name without leading emojis.
  /// Example: "📚 Books" -> "Books", "Books" -> "Books".
  static String cleanName(String name) {
    final stripped = name.replaceFirst(_leadingEmojiRegex, '').trim();
    return stripped.isNotEmpty ? stripped : name.trim();
  }

  /// Extracts or maps the appropriate emoji for this category.
  static String getEmoji(String name) {
    final trimmed = name.trim();
    final match = _leadingEmojiRegex.firstMatch(trimmed);
    if (match != null && match.group(0)!.trim().isNotEmpty) {
      return match.group(0)!.trim();
    }

    final clean = cleanName(trimmed).toLowerCase();
    for (final entry in _knownCategoryEmojis.entries) {
      if (clean == entry.key || clean.contains(entry.key)) {
        return entry.value;
      }
    }
    return '🏷️';
  }

  /// Formats category name with its appropriate emoji for feed pills.
  /// Example: "Books" -> "📚 Books", "📚 Books" -> "📚 Books".
  static String withEmoji(String name) {
    final clean = cleanName(name);
    if (clean.toLowerCase() == 'all') return '✨ All';
    final emoji = getEmoji(name);
    return '$emoji $clean';
  }
}
