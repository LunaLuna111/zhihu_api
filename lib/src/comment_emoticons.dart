import 'dart:convert';

final RegExp _commentEmoticonNumericEntity = RegExp(
  r'&#(?:x([0-9a-fA-F]+)|([0-9]+));',
);

String normalizeCommentEmoticonToken(Object? value) {
  var normalized = value?.toString() ?? '';
  normalized = normalized
      .replaceAll('&lbrack;', '[')
      .replaceAll('&rbrack;', ']')
      .replaceAll('&#91;', '[')
      .replaceAll('&#93;', ']')
      .replaceAll('［', '[')
      .replaceAll('］', ']')
      .replaceAll('【', '[')
      .replaceAll('】', ']');
  return normalized.replaceAllMapped(_commentEmoticonNumericEntity, (match) {
    final raw = match.group(1) ?? match.group(2);
    final codePoint = raw == null
        ? null
        : int.tryParse(raw, radix: match.group(1) == null ? 10 : 16);
    if (codePoint == null || codePoint < 0 || codePoint > 0x10ffff) {
      return match.group(0) ?? '';
    }
    return String.fromCharCode(codePoint);
  });
}

Iterable<String> commentEmoticonLookupKeys(Object? value) sync* {
  final normalized = normalizeCommentEmoticonToken(value).trim();
  if (normalized.isEmpty) return;
  yield normalized;
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    final bare = normalized.substring(1, normalized.length - 1).trim();
    if (bare.isNotEmpty) yield bare;
  } else {
    yield '[$normalized]';
  }
}

class CommentEmoticon {
  const CommentEmoticon({
    required this.id,
    required this.title,
    required this.groupId,
    required this.groupType,
    required this.staticImageUrl,
    required this.dynamicImageUrl,
    required this.stickerType,
    required this.status,
    this.assetImagePath = '',
  });

  final String id;
  final String title;
  final String groupId;
  final String groupType;
  final String staticImageUrl;
  final String dynamicImageUrl;
  final int stickerType;
  final int status;
  final String assetImagePath;

  bool get isVisible => status != 3 && status != 4;

  bool get isInlineEmoji =>
      groupId == 'EMOJI_GROUP_ID' ||
      groupId == 'VIP_EMOJI_GROUP_ID' ||
      groupType == 'official' ||
      groupType == 'vip';

  bool get isVip => stickerType == 2 || groupType == 'vip';

  String get imageUrl =>
      dynamicImageUrl.isNotEmpty ? dynamicImageUrl : staticImageUrl;

  factory CommentEmoticon.fromJson(
    Map<String, dynamic> json, {
    String fallbackGroupId = '',
    String fallbackGroupType = '',
  }) => CommentEmoticon(
    id: _text(json['id']),
    title: _text(json['title']),
    groupId: _text(json['group_id']).isNotEmpty
        ? _text(json['group_id'])
        : fallbackGroupId,
    groupType: _text(json['group_type']).isNotEmpty
        ? _text(json['group_type'])
        : fallbackGroupType,
    staticImageUrl: _httpsUrl(json['static_image_url']),
    dynamicImageUrl: _httpsUrl(json['dynamic_image_url']),
    stickerType: _integer(json['sticker_type']),
    status: _integer(json['status'], fallback: 1),
    assetImagePath: _text(json['asset_image_path']),
  );

  /// The 11.4.0 editor sends non-emoji stickers as one inline anchor after
  /// the typed text. Official and VIP emoji titles are inserted into text
  /// directly and therefore never use this markup.
  String submissionMarkup() {
    if (isInlineEmoji || id.isEmpty || title.isEmpty || imageUrl.isEmpty) {
      return '';
    }
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    return '<a href="${escape.convert(imageUrl)}" class="comment_sticker" '
        'data-width="0" data-height="0" '
        'data-sticker-id="${escape.convert(id)}">'
        '[${escape.convert(title)}]</a>';
  }

  static CommentEmoticon fallback(String value) => CommentEmoticon(
    id: 'fallback-${value.runes.map((rune) => rune.toRadixString(16)).join('-')}',
    title: value,
    groupId: 'EMOJI_GROUP_ID',
    groupType: 'official',
    staticImageUrl: '',
    dynamicImageUrl: '',
    stickerType: 1,
    status: 1,
  );
}

class CommentEmoticonGroup {
  const CommentEmoticonGroup({
    required this.id,
    required this.title,
    required this.type,
    required this.iconUrl,
    required this.selectedIconUrl,
    required this.version,
    required this.emoticons,
    this.assetIconPath = '',
    this.assetSelectedIconPath = '',
  });

  final String id;
  final String title;
  final String type;
  final String iconUrl;
  final String selectedIconUrl;
  final int version;
  final List<CommentEmoticon> emoticons;
  final String assetIconPath;
  final String assetSelectedIconPath;

  factory CommentEmoticonGroup.fromJson(Map<String, dynamic> json) {
    final id = _text(json['id']);
    final type = _text(json['type']);
    return CommentEmoticonGroup(
      id: id,
      title: _text(json['title']),
      type: type,
      iconUrl: _httpsUrl(json['icon_url']),
      selectedIconUrl: _httpsUrl(json['selected_icon_url']),
      version: _integer(json['version']),
      assetIconPath: _text(json['asset_icon_path']),
      assetSelectedIconPath: _text(json['asset_selected_icon_path']),
      emoticons: _mapList(json['stickers'])
          .map(
            (value) => CommentEmoticon.fromJson(
              value,
              fallbackGroupId: id,
              fallbackGroupType: type,
            ),
          )
          .where((value) => value.isVisible && value.title.isNotEmpty)
          .toList(growable: false),
    );
  }

  CommentEmoticonGroup withDetail(Map<String, dynamic> json) {
    final payload = _map(json['data']) ?? json;
    final detailed = CommentEmoticonGroup.fromJson({...toJson(), ...payload});
    return detailed.emoticons.isEmpty ? this : detailed;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'icon_url': iconUrl,
    'selected_icon_url': selectedIconUrl,
    'version': version,
    'asset_icon_path': assetIconPath,
    'asset_selected_icon_path': assetSelectedIconPath,
    'stickers': emoticons
        .map(
          (value) => {
            'id': value.id,
            'title': value.title,
            'group_id': value.groupId,
            'group_type': value.groupType,
            'static_image_url': value.staticImageUrl,
            'dynamic_image_url': value.dynamicImageUrl,
            'sticker_type': value.stickerType,
            'status': value.status,
            'asset_image_path': value.assetImagePath,
          },
        )
        .toList(growable: false),
  };

  static List<CommentEmoticonGroup> parseList(Map<String, dynamic> json) {
    final data = json['data'];
    final values = data is List
        ? data
        : data is Map
        ? data['sticker_groups'] ?? data['groups'] ?? const <Object?>[]
        : json['sticker_groups'] ?? json['groups'] ?? const <Object?>[];
    return _mapList(values)
        .map(CommentEmoticonGroup.fromJson)
        .where((value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  static CommentEmoticonGroup fallback() => CommentEmoticonGroup(
    id: 'EMOJI_GROUP_ID',
    title: '表情',
    type: 'official',
    iconUrl: '',
    selectedIconUrl: '',
    version: 1,
    emoticons: _fallbackEmojiValues
        .map(CommentEmoticon.fallback)
        .toList(growable: false),
  );
}

const _fallbackEmojiValues = <String>[
  '😀',
  '😃',
  '😄',
  '😁',
  '😆',
  '😅',
  '😂',
  '🤣',
  '😊',
  '😇',
  '🙂',
  '🙃',
  '😉',
  '😌',
  '😍',
  '🥰',
  '😘',
  '😗',
  '😚',
  '😜',
  '🤪',
  '🤨',
  '🤔',
  '🤭',
  '🤫',
  '🙄',
  '😬',
  '😏',
  '😒',
  '😔',
  '😪',
  '🤤',
  '😴',
  '😷',
  '🤒',
  '🤕',
  '🤢',
  '🥵',
  '🥶',
  '😎',
  '🥳',
  '🥺',
  '😢',
  '😭',
  '😤',
  '😡',
  '🤯',
  '😱',
  '👍',
  '👎',
  '👏',
  '🙌',
  '🙏',
  '💪',
  '🤝',
  '❤️',
  '💔',
  '🔥',
  '✨',
  '🎉',
];

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value.map(_map).whereType<Map<String, dynamic>>().toList();
}

String _text(Object? value) => value?.toString().trim() ?? '';

int _integer(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? fallback;

String _httpsUrl(Object? value) {
  final text = _text(value);
  final uri = Uri.tryParse(text);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? text
      : '';
}
