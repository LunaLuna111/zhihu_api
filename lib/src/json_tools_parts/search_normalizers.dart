import 'content_helpers.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'search_rows.dart';
import 'unwrap_and_component.dart';

// ordinary library module

String saltAuthorName(Object? value) {
  if (value is List) {
    for (final item in value) {
      final name = saltAuthorName(item);
      if (name.isNotEmpty) return name;
    }
    return '';
  }
  final map = stringMap(value);
  if (map == null) return '';
  return plainText(map['name'] ?? map['nickname'] ?? map['title']);
}

String _canonicalSearchObjectType(Map<String, dynamic> object) {
  for (final key in const [
    'type',
    'object_type',
    'resource_type',
    'content_type',
  ]) {
    final marker = plainText(object[key]).toLowerCase();
    if (marker == 'hot_timing') return marker;
    if (marker == 'search_course') return 'search_course';
    if (marker == 'search_special') return 'search_special';
    if (marker == 'zvideo' || marker == 'video') return 'zvideo';
    if (marker == 'ebook' || marker == 'km_ebook') return 'publication';
    for (final type in const [
      'answer',
      'article',
      'question',
      'people',
      'member',
      'topic',
      'column',
      'pin',
      'publication',
      'live',
      'scholar',
      'paper',
      'roundtable',
      'ring',
      'podcast',
    ]) {
      if (marker == type || marker == 'search_$type') return type;
    }
  }
  for (final key in const ['url', 'target_url', 'redirect_url']) {
    final identity = contentIdentityFromUrl(plainText(object[key]));
    if (identity.$1.isNotEmpty) return identity.$1;
  }
  return '';
}

bool isSearchAdvertisementRow(Map<String, dynamic> source) {
  const advertisementTypes = {
    'knowledge_ad',
    'search_advert',
    'advert',
    'advertisement',
    'promotion',
  };
  final wireType = plainText(source['type']).toLowerCase();
  if (advertisementTypes.contains(wireType)) return true;
  final object = stringMap(source['object']);
  final objectType = plainText(object?['type']).toLowerCase();
  return advertisementTypes.contains(objectType);
}

bool isRingBoxSearchRow(Map<String, dynamic> source) {
  final object = stringMap(source['object']);
  for (final marker in [
    source['type'],
    source['card_type'],
    object?['type'],
    object?['card_type'],
  ]) {
    if (plainText(marker).toLowerCase() == 'ring_box') return true;
  }
  return false;
}

String _nestedSearchValue(Object? value, List<String> nestedKeys) {
  final map = stringMap(value);
  if (map == null) return plainText(value);
  for (final key in nestedKeys) {
    final text = plainText(map[key]);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _ringOfficialUrl(String raw, String id) {
  final candidate = raw.trim();
  final uri = Uri.tryParse(candidate);
  if (uri != null && uri.scheme == 'zhihu' && uri.host == 'ring') {
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final routeId = segments.length >= 2 && segments.first == 'host'
        ? segments[1]
        : id;
    if (RegExp(r'^\d+$').hasMatch(routeId)) {
      return 'https://www.zhihu.com/ring/host/$routeId';
    }
  }
  final resolved = candidate.startsWith('/')
      ? Uri.parse('https://www.zhihu.com').resolve(candidate)
      : uri;
  if (resolved != null &&
      resolved.scheme == 'https' &&
      resolved.userInfo.isEmpty &&
      !resolved.hasPort &&
      (resolved.host == 'zhihu.com' || resolved.host.endsWith('.zhihu.com')) &&
      resolved.pathSegments.contains('ring')) {
    return resolved.toString();
  }
  if (RegExp(r'^\d+$').hasMatch(id)) {
    return 'https://www.zhihu.com/ring/host/$id';
  }
  return '';
}

Map<String, dynamic>? _normalizeRingSearchEntity(Map<String, dynamic> source) {
  final candidates = <Map<String, dynamic>>[source];
  var current = source;
  for (var depth = 0; depth < 4; depth++) {
    Map<String, dynamic>? nested;
    for (final key in const [
      'object',
      'ring',
      'ring_info',
      'ringInfo',
      'target',
    ]) {
      nested = stringMap(current[key]);
      if (nested != null) break;
    }
    if (nested == null) break;
    candidates.add(nested);
    current = nested;
  }

  String text(List<String> keys) {
    for (final candidate in candidates.reversed) {
      for (final key in keys) {
        final raw = candidate[key];
        final value = searchTitleText(
          raw is String
              ? raw.replaceAll(
                  RegExp(r'</?em\b[^>]*>', caseSensitive: false),
                  '',
                )
              : raw,
        );
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  String value(List<String> keys, List<String> nestedKeys) {
    for (final candidate in candidates.reversed) {
      for (final key in keys) {
        final result = _nestedSearchValue(candidate[key], nestedKeys);
        if (result.isNotEmpty) return result;
      }
    }
    return '';
  }

  final title = text(const ['title', 'name', 'ring_name', 'ringName']);
  if (title.isEmpty || title.toLowerCase() == 'ring_box') return null;
  final id = value(
    const ['id', 'ring_id', 'ringId', 'token'],
    const ['id', 'value'],
  );
  final rawRoute = value(
    const [
      'action_url',
      'actionUrl',
      'url_to_ring',
      'urlToRing',
      'url',
      'target_url',
      'targetUrl',
      'router',
    ],
    const ['url', 'href', 'uri', 'value'],
  );
  final route = _ringOfficialUrl(rawRoute, id);
  // A label-only box heading is not a result. A real ring must have a stable
  // identity or an official destination that a person can open.
  if (id.isEmpty && route.isEmpty) return null;

  final description = text(const [
    'description',
    'excerpt',
    'summary',
    'ring_desc',
    'ringDesc',
  ]);
  final avatar = value(
    const [
      'avatar_url',
      'avatarUrl',
      'avatar',
      'image_url',
      'imageUrl',
      'cover_url',
      'coverUrl',
      'cover',
    ],
    const ['url', 'url_template', 'src', 'value'],
  );
  final entity = candidates.reversed.fold<Map<String, dynamic>>(
    <String, dynamic>{},
    (result, candidate) => result..addAll(candidate),
  );
  // Generic content helpers recursively unwrap these keys. They belong to
  // the transport container, not to the normalized ring entity; retaining
  // them would hide the canonical title/type/id and could duplicate a ring.
  for (final key in const [
    'object',
    'data',
    'content',
    'target',
    'ring',
    'ring_info',
    'ringInfo',
  ]) {
    entity.remove(key);
  }
  return <String, dynamic>{
    ...entity,
    'type': 'ring',
    if (id.isNotEmpty) 'id': id,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    if (avatar.isNotEmpty) 'avatar_url': avatar,
    if (route.isNotEmpty) 'url': route,
    '_search_container_type': 'ring_box',
  };
}

List<Map<String, dynamic>> normalizeRingBoxSearchRow(
  Map<String, dynamic> source,
) {
  final results = <Map<String, dynamic>>[];
  final seenMaps = <int>{};
  final seenResults = <String>{};

  void visit(Object? raw, int depth) {
    if (depth > 7 || raw == null) return;
    if (raw is List) {
      for (final item in raw.take(100)) {
        visit(item, depth + 1);
      }
      return;
    }
    final map = stringMap(raw);
    if (map == null || !seenMaps.add(identityHashCode(raw))) return;
    final normalized = _normalizeRingSearchEntity(map);
    if (normalized != null) {
      final identity =
          '${idOf(normalized)}\u0000${plainText(normalized['url'])}'
          '\u0000${titleOf(normalized)}';
      if (seenResults.add(identity)) results.add(normalized);
    }
    for (final key in const [
      'data_list',
      'dataList',
      'items',
      'rings',
      'data',
      'result',
      'list',
      'object',
      'ring',
      'ring_info',
      'ringInfo',
      'target',
    ]) {
      visit(map[key], depth + 1);
    }
  }

  visit(source, 0);
  return List.unmodifiable(results);
}

Map<String, dynamic>? normalizeKnowledgeMarketCard(
  Map<String, dynamic> source, {
  required bool includeNovelMarketCards,
  required bool includePublicationMarketCards,
}) {
  if (plainText(source['type']).toLowerCase() != 'knowledge_ad') return null;
  final object = stringMap(source['object']);
  final body = object == null
      ? null
      : stringMap(object['body']) ??
            stringMap(object['content']) ??
            stringMap(object['data']) ??
            stringMap(object['payload']) ??
            object;
  if (object == null || body == null) return null;
  final commodityType = plainText(
    object['commodity_type'] ??
        object['business_type'] ??
        object['property_type'] ??
        object['product_type'] ??
        body['commodity_type'] ??
        body['business_type'] ??
        body['property_type'] ??
        body['product_type'],
  ).toLowerCase();
  final routeMarkers = [
    commodityType,
    plainText(object['url']),
    plainText(object['slave_url']),
    plainText(body['url']),
    plainText(body['deep_link']),
    plainText(body['route']),
  ].join(' ').toLowerCase();
  final isNovel =
      object['is_story'] == true ||
      object['is_long'] == true ||
      object['is_mid_long'] == true ||
      body['is_story'] == true ||
      body['is_long'] == true ||
      body['is_mid_long'] == true ||
      routeMarkers.contains('paid_column') ||
      routeMarkers.contains('paidcolumn') ||
      routeMarkers.contains('novel') ||
      routeMarkers.contains('manuscript') ||
      routeMarkers.contains('long_story') ||
      routeMarkers.contains('mid_long');
  final isPublication =
      commodityType == 'book' ||
      commodityType.contains('ebook') ||
      commodityType.contains('publication') ||
      commodityType.contains('electronic_book');
  final includeNovel = includeNovelMarketCards && isNovel;
  final includePublication = includePublicationMarketCards && isPublication;
  if (!includeNovel && !includePublication) {
    return null;
  }

  Map<String, dynamic>? firstAuthor;
  final authorNames = <String>[];
  final rawAuthors = body['authors'];
  if (rawAuthors is List) {
    for (final raw in rawAuthors) {
      final author = stringMap(raw);
      if (author != null) {
        final name = plainText(
          author['name'] ?? author['title'] ?? author['text'],
        );
        if (name.isNotEmpty) {
          firstAuthor ??= <String, dynamic>{...author, 'name': name};
          authorNames.add(name);
        }
        continue;
      }
      final name = plainText(raw);
      if (name.isNotEmpty) {
        firstAuthor ??= {'name': name};
        authorNames.add(name);
      }
    }
  }
  final routes = [
    object['url'],
    object['slave_url'],
    body['url'],
  ].map(plainText).where((value) => value.isNotEmpty).toList(growable: false);
  final route = routes.firstWhere((value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'www.zhihu.com' || uri.host.endsWith('.zhihu.com'));
  }, orElse: () => routes.isEmpty ? '' : routes.first);
  final businessId = plainText(
    object['business_id'] ??
        object['well_id'] ??
        object['book_list_id'] ??
        object['work_id'] ??
        object['book_id'] ??
        object['sku_id'] ??
        body['business_id'] ??
        body['well_id'] ??
        body['book_list_id'] ??
        body['work_id'] ??
        body['book_id'] ??
        body['sku_id'],
  );
  final normalized = <String, dynamic>{...source}
    ..remove('object')
    ..addAll(object)
    ..['type'] = 'publication'
    ..['title'] = body['title'] ?? body['name'] ?? object['title']
    ..['description'] =
        body['description'] ?? body['summary'] ?? object['description']
    ..['images'] =
        body['images'] ??
        body['image_list'] ??
        body['artwork'] ??
        object['images']
    ..['business_id'] = businessId
    ..['id'] = object['commodity_id'] ?? source['id']
    ..['_search_container_type'] = 'knowledge_ad';
  if (includeNovel) normalized['_search_novel_card'] = true;
  if (firstAuthor != null) normalized['author'] = firstAuthor;
  if (authorNames.isNotEmpty) normalized['authors'] = authorNames;
  if (body['publish_at'] != null) {
    normalized['publish_time'] = body['publish_at'];
  }
  if (route.isNotEmpty) normalized['url'] = route;
  return normalized;
}

bool isSearchSectionRow(Map<String, dynamic> source) =>
    plainText(source['type']).toLowerCase() == 'search_section';

List<Map<String, dynamic>> searchSectionItemsOf(Map<String, dynamic> source) {
  final raw = source['data_list'] ?? source['dataList'];
  if (raw is! List) return const [];
  final items = <Map<String, dynamic>>[];
  for (final entry in raw.whereType<Map>()) {
    final item = entry.map((key, value) => MapEntry(key.toString(), value));
    if (isSearchAdvertisementRow(item)) continue;
    final object = stringMap(item['object']);
    if (object == null || isSearchAdvertisementRow(object)) continue;
    final normalized = <String, dynamic>{...object};
    final highlight = stringMap(item['highlight']);
    final rawHighlightedTitle = highlight?['title'];
    final highlightedTitle = plainText(
      rawHighlightedTitle is String
          ? rawHighlightedTitle.replaceAll(
              RegExp(r'</?em\b[^>]*>', caseSensitive: false),
              '',
            )
          : rawHighlightedTitle,
    );
    if (highlightedTitle.isNotEmpty) normalized['title'] = highlightedTitle;
    items.add(normalized);
  }
  return repairIncompleteSearchRows(items);
}

String searchSectionTargetTypeOf(Map<String, dynamic> source) {
  final type = plainText(
    source['section_type'] ?? source['sectionType'],
  ).toLowerCase();
  return switch (type) {
    'people' || 'member' => 'people',
    'topic' => 'topic',
    'column' => 'column',
    'publication' || 'ebook' || 'km_ebook' => 'publication',
    'live' || 'search_course' || 'search_special' => 'live',
    _ => type,
  };
}

String searchSectionTitleOf(Map<String, dynamic> source) {
  final explicit = plainText(source['title'] ?? source['name']);
  if (explicit.isNotEmpty) return explicit;
  return switch (searchSectionTargetTypeOf(source)) {
    'people' => '相关用户',
    'topic' => '相关话题',
    'column' => '相关专栏',
    'publication' => '相关电子书',
    'live' => '相关直播',
    _ => '相关内容',
  };
}

bool searchSectionHasMore(Map<String, dynamic> source) =>
    source['has_more'] == true || source['hasMore'] == true;

Map<String, dynamic>? normalizeKnowledgeSearchResult(
  Map<String, dynamic> source,
) {
  final object = stringMap(source['object']) ?? stringMap(source['answer_obj']);
  if (object == null) return null;
  final objectType = _canonicalSearchObjectType(object);
  if (objectType.isEmpty) return null;

  final normalized = <String, dynamic>{...source}
    ..remove('object')
    ..remove('answer_obj')
    ..addAll(object)
    ..['type'] = objectType
    ..['_search_container_type'] = 'knowledge_result';
  final highlight = stringMap(source['highlight']);
  final rawHighlightedTitle = highlight?['title'];
  final highlightedTitle = plainText(
    rawHighlightedTitle is String
        ? rawHighlightedTitle.replaceAll(
            RegExp(r'</?em\b[^>]*>', caseSensitive: false),
            '',
          )
        : rawHighlightedTitle,
  );
  final question = stringMap(object['question']);
  final questionTitle = plainText(question?['title'] ?? question?['name']);
  if (highlightedTitle.isNotEmpty) {
    normalized['title'] = highlightedTitle;
  } else if (plainText(normalized['title']).isEmpty &&
      questionTitle.isNotEmpty) {
    normalized['title'] = questionTitle;
  }
  final identity = contentIdentityFromUrl(plainText(object['url']));
  if (plainText(normalized['id']).isEmpty && identity.$2.isNotEmpty) {
    normalized['id'] = identity.$2;
  }
  if (objectType == 'zvideo' && plainText(normalized['id']).isEmpty) {
    // Some video-search containers carry the content identity separately
    // from video.id (the latter is a Lens playback ID). Only promote fields
    // that the original VideoEntity/short-content models define as the outer
    // ZVideo identity.
    final video = stringMap(object['video']);
    final entityId = plainText(
      object['zvideo_id'] ??
          object['content_id'] ??
          video?['zvideo_id'] ??
          video?['parent_video_id'],
    );
    if (entityId.isNotEmpty) normalized['id'] = entityId;
  }
  return normalized;
}

bool isNovelSearchObject(Map<String, dynamic> source) {
  final object = stringMap(source['object']) ?? source;
  final body =
      stringMap(object['body']) ??
      stringMap(object['content']) ??
      stringMap(object['data']);
  final markers = <String>[
    for (final map in [source, object, ?body])
      for (final key in const [
        'commodity_type',
        'business_type',
        'property_type',
        'product_type',
        'card_type',
        'object_type',
        'resource_type',
        'type',
        'url',
        'redirect_url',
        'target_url',
        'deep_link',
      ])
        plainText(map[key]),
  ].join(' ').toLowerCase();
  return source['_search_novel_card'] == true ||
      object['is_story'] == true ||
      object['is_long'] == true ||
      object['is_mid_long'] == true ||
      body?['is_story'] == true ||
      body?['is_long'] == true ||
      body?['is_mid_long'] == true ||
      markers.contains('paid_column') ||
      markers.contains('paidcolumn') ||
      markers.contains('novel') ||
      markers.contains('manuscript') ||
      markers.contains('long_story') ||
      markers.contains('mid_long');
}

bool isSearchHotTimingRow(Map<String, dynamic> source) =>
    plainText(source['type']).toLowerCase() == 'hot_timing';

String searchHotTimingTitleOf(Map<String, dynamic> source) {
  return plainText(source['icon_title'] ?? source['iconTitle']);
}

bool searchHotTimingHasMore(Map<String, dynamic> source) =>
    source['has_more'] == true || source['hasMore'] == true;

List<Map<String, dynamic>> searchHotTimingItemsOf(Map<String, dynamic> source) {
  final raw = source['content_items'] ?? source['contentItems'];
  if (raw is! List) return const [];
  final items = <Map<String, dynamic>>[];
  for (final entry in raw.whereType<Map>()) {
    final item = entry.map((key, value) => MapEntry(key.toString(), value));
    final subContents = item['sub_contents'] ?? item['subContents'];
    final candidates = subContents is List
        ? subContents.whereType<Map>()
        : [entry];
    for (final candidate in candidates) {
      final row = candidate.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final object = stringMap(row['object']);
      if (object == null) continue;
      final type = _canonicalSearchObjectType(object);
      // The supplied client renders answer/article children in this block.
      if (type != 'answer' && type != 'article') continue;
      final normalized = normalizeKnowledgeSearchResult({
        ...row,
        'type': 'knowledge_result',
      });
      if (normalized != null) items.add(normalized);
    }
  }
  return List.unmodifiable(items);
}
