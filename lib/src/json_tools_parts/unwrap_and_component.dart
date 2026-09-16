import 'components_and_images.dart';
import 'rich_and_feed.dart';

// ordinary library module

final _unwrappedObjectCache = Expando<Map<String, dynamic>>(
  'unwrapped-content-object',
);

Map<String, dynamic> unwrapObject(Map<String, dynamic> source) {
  final cached = _unwrappedObjectCache[source];
  if (cached != null) return cached;
  final resolved = _unwrapObjectUncached(source);
  // API response maps are stable identities. Without this weak cache, each
  // title, metric and relationship lookup rebuilds special SDUI/search maps.
  _unwrappedObjectCache[source] = resolved;
  return resolved;
}

Map<String, dynamic> _unwrapObjectUncached(Map<String, dynamic> source) {
  // `normalizeComponentCard` marks its projection so callers can safely pass
  // it through the generic helpers without rebuilding and rescanning the full
  // SDUI child tree on every field lookup.
  if (source['component_card'] == true) return source;
  final searchContent = _normalizeSearchContentCard(source);
  if (searchContent != null) return searchContent;
  final aggregate = _normalizeAggregateNotification(source);
  if (aggregate != null) return aggregate;
  final hotRank = _normalizeHotRankFeed(source);
  if (hotRank != null) return hotRank;
  var current = source;
  for (var i = 0; i < 4; i++) {
    final marker = plainText(current['type']).toLowerCase();
    final hasOwnContentIdentity =
        (marker.contains('answer') ||
            marker.contains('article') ||
            marker.contains('pin') ||
            marker == 'question' ||
            marker == 'zvideo' ||
            marker == 'video') &&
        const [
          'id',
          'content_id',
          'contentId',
          'token',
          'business_id',
        ].any((key) => plainText(current[key]).isNotEmpty);
    Map<String, dynamic>? nested;
    for (final key in const [
      'target',
      'object',
      'data',
      'pin',
      'result',
      'content',
    ]) {
      // A detail response can legitimately store the post body as a map
      // under `content` (for example a pin document tree). Once the outer
      // map already identifies itself as the answer/article/pin, descending
      // into that body destroys the post identity and makes later metadata
      // and cache checks reject an otherwise valid response.
      if (key == 'content' && hasOwnContentIdentity) continue;
      final value = current[key];
      if (value is Map<String, dynamic>) {
        nested = value;
        break;
      }
    }
    if (nested == null) break;
    current = nested;
  }
  return normalizeComponentCard(current);
}

Map<String, dynamic>? _normalizeSearchContentCard(Map<String, dynamic> source) {
  if (plainText(source['type']).toLowerCase() != 'search_content_card') {
    return null;
  }
  final title = stringMap(source['title']);
  final content = stringMap(source['content']);
  if (title == null && content == null) return null;
  final titleUrl = plainText(title?['url']);
  final contentUrl = plainText(content?['url']);
  var identity = contentIdentityFromUrl(contentUrl);
  if (identity.$1.isEmpty) identity = contentIdentityFromUrl(titleUrl);
  final resource = plainText(source['resource']).toLowerCase();
  final semanticType = identity.$1.isNotEmpty
      ? identity.$1
      : const {
              'question': 'question',
              'answer': 'answer',
              'article': 'article',
              'pin': 'pin',
            }[resource] ??
            'search_content';
  return <String, dynamic>{
    ...source,
    'type': semanticType,
    if (identity.$2.isNotEmpty) 'id': identity.$2,
    'title': plainText(title?['name']),
    'excerpt': plainText(content?['excerpt']),
    if (contentUrl.isNotEmpty) 'url': contentUrl,
    if (titleUrl.isNotEmpty) 'question_url': titleUrl,
    if (source['statistics'] is List) 'search_statistics': source['statistics'],
    '_search_content_card': true,
  };
}

Map<String, dynamic>? _normalizeHotRankFeed(Map<String, dynamic> source) {
  final target = stringMap(source['target']);
  if (target == null ||
      (target['title_area'] == null && target['hot_event'] == null)) {
    return null;
  }
  final titleArea = stringMap(target['title_area']);
  final excerptArea = stringMap(target['excerpt_area']);
  final imageArea = stringMap(target['image_area']);
  final metricsArea = stringMap(target['metrics_area']);
  final linkArea = stringMap(target['link']);
  final hotEvent = stringMap(target['hot_event']);
  final link = plainText(linkArea?['url'] ?? hotEvent?['redirect_url']);
  final identity = contentIdentityFromUrl(link);
  final sourceId = plainText(source['id'] ?? source['card_id']);
  return <String, dynamic>{
    ...source,
    'type': identity.$1.isEmpty ? 'hot_list_feed' : identity.$1,
    if (identity.$2.isNotEmpty || sourceId.isNotEmpty)
      'id': identity.$2.isNotEmpty ? identity.$2 : sourceId,
    'title': plainText(titleArea?['text'] ?? hotEvent?['event_name']),
    'excerpt': plainText(excerptArea?['text']),
    if (plainText(imageArea?['url']).isNotEmpty)
      'image_url': plainText(imageArea?['url']),
    if (link.isNotEmpty) 'url': link,
    if (plainText(metricsArea?['text']).isNotEmpty)
      'metrics_text': plainText(metricsArea?['text']),
    if (source['seq_num'] != null) 'rank': source['seq_num'],
    '_hot_rank': true,
  };
}

(String, String) contentIdentityFromUrl(String value) {
  if (value.isEmpty) return ('', '');
  final parsed = Uri.tryParse(value);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    final host = parsed.host.toLowerCase();
    final isZhihuHost =
        host == 'www.zhihu.com' ||
        host == 'zhihu.com' ||
        host == 'api.zhihu.com' ||
        host == 'zhuanlan.zhihu.com' ||
        host == 'story.zhihu.com' ||
        host == 'link.zhihu.com';
    if (!isZhihuHost) return ('', '');
    if (host == 'link.zhihu.com') {
      final target =
          parsed.queryParameters['target'] ??
          parsed.queryParameters['url'] ??
          '';
      if (target.isNotEmpty && target != value) {
        return contentIdentityFromUrl(target);
      }
    }
  }
  final patterns = <(String, RegExp)>[
    // A comment deep link may also contain an answer segment; prefer the
    // comment id so the native reply surface opens instead of the answer
    // page's generic comment sheet.
    (
      'comment',
      RegExp(r'(?:comments?|comment)/([0-9]+)', caseSensitive: false),
    ),
    ('zvideo', RegExp(r'(?:zvideos?|video)/([0-9]+)', caseSensitive: false)),
    ('answer', RegExp(r'(?:answers?|answer)/([0-9]+)', caseSensitive: false)),
    ('question', RegExp(r'questions?/([0-9]+)', caseSensitive: false)),
    ('article', RegExp(r'(?:articles?|p)/([0-9]+)', caseSensitive: false)),
    ('pin', RegExp(r'(?:pins?|pin)/([0-9]+)', caseSensitive: false)),
    ('topic', RegExp(r'topics?/([0-9]+)', caseSensitive: false)),
  ];
  for (final candidate in patterns) {
    final match = candidate.$2.firstMatch(value);
    if (match != null) return (candidate.$1, match.group(1)!);
  }
  final uri = parsed;
  if (uri != null && uri.scheme == 'zhihu') {
    final kind = uri.host.toLowerCase();
    String? id;
    for (final segment in uri.pathSegments) {
      if (RegExp(r'^\d+$').hasMatch(segment)) {
        id = segment;
        break;
      }
    }
    if (id != null) {
      if (kind.contains('question')) return ('question', id);
      if (kind.contains('answer')) return ('answer', id);
      if (kind.contains('comment')) return ('comment', id);
      if (kind.contains('article')) return ('article', id);
      if (kind.contains('pin')) return ('pin', id);
      if (kind.contains('topic')) return ('topic', id);
      if (kind.contains('zvideo') || kind == 'video') return ('zvideo', id);
    }
  }
  return ('', '');
}

Map<String, dynamic>? stringMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? _normalizeAggregateNotification(
  Map<String, dynamic> source,
) {
  final wrapperType = plainText(source['type']).toLowerCase();
  if (!wrapperType.contains('aggregate_notification')) return null;

  final content = stringMap(source['content']);
  final targetSource = stringMap(source['target_source']);
  final head = stringMap(source['head']);
  if (content == null && targetSource == null) return null;

  const supportedTypes = {
    'answer',
    'article',
    'question',
    'pin',
    'people',
    'member',
    'column',
  };

  String typeHint(Object? value) {
    final hint = plainText(value).toLowerCase();
    if (hint.isEmpty) return '';
    for (final type in supportedTypes) {
      final aliases = type == 'article'
          ? const ['article', 'articles', 'zhuanlan.zhihu.com/p/']
          : type == 'people' || type == 'member'
          ? const ['people', 'member']
          : [type, '${type}s'];
      if (aliases.any(hint.contains)) return type;
    }
    return '';
  }

  final targetExtra = stringMap(targetSource?['extra']);
  final links = [
    targetSource?['target_link'],
    content?['target_link'],
    content?['sub_target_link'],
  ];
  var semanticType = '';
  for (final candidate in [
    source['noti_subtype'],
    targetSource?['object_type'],
    targetSource?['type'],
    content?['object_type'],
    content?['type'],
    targetExtra?['object_type'],
    ...links,
  ]) {
    semanticType = typeHint(candidate);
    if (semanticType.isNotEmpty) break;
  }
  if (!supportedTypes.contains(semanticType)) return null;

  final objectId = plainText(
    targetSource?['object_id'] ?? content?['object_id'],
  );
  if (objectId.isEmpty) return null;

  String firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = plainText(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  final author = stringMap(head?['author']);
  final image = firstText([
    targetSource?['image'],
    httpsImageUrl(targetSource?['image_display_info']),
    content?['image'],
  ]);
  final targetLink = firstText(links);

  return <String, dynamic>{
    'type': semanticType,
    'id': objectId,
    'title': firstText([
      content?['title'],
      targetSource?['text'],
      targetSource?['full_text'],
    ]),
    'excerpt': firstText([
      content?['abstract_text'],
      content?['text'],
      targetSource?['sub_text'],
      targetSource?['full_text'],
    ]),
    'author': ?author,
    if (image.isNotEmpty) 'image_url': image,
    if (targetLink.isNotEmpty) 'url': targetLink,
    if (source['created'] != null) 'created_time': source['created'],
  };
}

Iterable<Map<String, dynamic>> walkVisibleMaps(Object? value) sync* {
  if (value is Map) {
    final map = value.map((key, value) => MapEntry(key.toString(), value));
    if (map['visible'] == false) return;
    yield map;
    for (final child in map.values) {
      yield* walkVisibleMaps(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* walkVisibleMaps(child);
    }
  }
}

String componentTextByMarker(
  Map<String, dynamic> source,
  Iterable<String> markers,
) {
  for (final node in walkVisibleMaps(source['children'])) {
    final marker = '${node['style'] ?? ''} ${node['test_id'] ?? ''}'
        .toLowerCase();
    if (!markers.any(marker.contains)) continue;
    final text = plainText(node['text']);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String componentMetricByMarker(
  Map<String, dynamic> source,
  Iterable<String> markers,
) {
  for (final node in walkVisibleMaps(source['children'])) {
    final marker = [
      node['id'],
      node['style'],
      node['test_id'],
      node['action_type'],
    ].whereType<Object>().join(' ').toLowerCase();
    if (!markers.any(marker.contains)) continue;
    for (final key in const ['count', 'value', 'text', 'title', 'content']) {
      final text = plainText(node[key]);
      if (RegExp(r'\d').hasMatch(text)) return text;
    }
  }
  return '';
}

Object? firstNestedAlias(Object? source, Iterable<String> aliases) {
  for (final node in walkVisibleMaps(source)) {
    for (final key in aliases) {
      final value = node[key];
      if (value != null && plainText(value).isNotEmpty) return value;
    }
  }
  return null;
}

String? httpsImageUrl(Object? value) {
  String normalize(String raw) => raw
      .trim()
      .replaceAll(r'\/', '/')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('{size}', 'r')
      .replaceAll('{format}', 'jpg');

  String? valid(String raw) {
    var candidate = normalize(raw);
    if (candidate.startsWith('//')) candidate = 'https:$candidate';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return candidate;
  }

  if (value is String) {
    return valid(value);
  }
  final image = stringMap(value);
  if (image == null) return null;
  for (final key in const [
    'url',
    'url_template',
    'image_url',
    'imageUrl',
    'image_url_template',
    'content_url',
    'contentUrl',
    'image_uri',
    'imageUri',
    'display_url',
    'displayUrl',
    'download_url',
    'downloadUrl',
    'static_image_url',
    'staticImageUrl',
    'dynamic_image_url',
    'dynamicImageUrl',
    'sticker_url',
    'stickerUrl',
    'media_url',
    'mediaUrl',
    'image',
    'src',
    'original',
    'original_url',
    'show_url',
    'show_uri',
    'href',
    'thumbnail',
  ]) {
    final candidate = valid(image[key]?.toString() ?? '');
    if (candidate != null) return candidate;
  }
  return null;
}

(String, String) componentIdentity(Map<String, dynamic> source) {
  final candidates = <String>[
    source['extra'] is Map
        ? ((stringMap(source['extra'])?['test_id'] ?? '').toString())
        : '',
    for (final node in walkVisibleMaps(source['children']))
      (node['test_id'] ?? '').toString(),
    if (source['action'] is Map)
      (stringMap(source['action'])?['parameter'] ?? '').toString(),
  ];
  final dotted = RegExp(
    r'(answer|article|question|pin)[./:](\d+)(?:[./:]|$)',
    caseSensitive: false,
  );
  for (final candidate in candidates) {
    final match = dotted.firstMatch(candidate);
    if (match != null) return (match.group(1)!.toLowerCase(), match.group(2)!);
  }
  return ('', '');
}

String componentImage(
  Map<String, dynamic> source,
  Map<String, dynamic>? author,
  Map<String, dynamic>? userInfo,
) {
  final direct = [
    userInfo?['avatarUrl'],
    userInfo?['avatar_url'],
    author?['avatar_url'],
    author?['avatar'],
  ];
  for (final value in direct) {
    final candidate = value?.toString() ?? '';
    if (Uri.tryParse(candidate)?.scheme == 'https') return candidate;
  }
  for (final node in walkVisibleMaps(source['children'])) {
    for (final key in const ['image_url', 'avatar_url', 'avatarUrl', 'image']) {
      final value = node[key];
      if (value is String && Uri.tryParse(value)?.scheme == 'https') {
        return value;
      }
      final image = stringMap(value);
      if (image != null) {
        for (final imageKey in const ['url', 'image_url', 'original']) {
          final candidate = image[imageKey]?.toString() ?? '';
          if (Uri.tryParse(candidate)?.scheme == 'https') return candidate;
        }
      }
    }
  }
  return '';
}
