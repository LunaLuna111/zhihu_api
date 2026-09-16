import 'dart:convert';

import 'components_and_images.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'salt_manuscript_envelope.dart';
import 'unwrap_and_component.dart';

// ordinary library module

Map<String, dynamic> mergeListMetadata(
  Map<String, dynamic> candidate,
  Map<String, dynamic>? fallback,
) {
  final normalized = Map<String, dynamic>.from(unwrapObject(candidate));
  if (fallback == null) return normalized;
  final listObject = unwrapObject(fallback);
  if (titleOf(normalized).startsWith('${typeOf(normalized)} #')) {
    final title = titleOf(listObject);
    if (title.isNotEmpty) normalized['title'] = title;
  }
  if (authorNameOf(normalized).isEmpty && authorNameOf(listObject).isNotEmpty) {
    normalized['author'] = listObject['author'];
  }
  final normalizedAuthor = stringMap(normalized['author']);
  final listAuthor = stringMap(listObject['author']);
  if (normalizedAuthor != null && listAuthor != null) {
    for (final key in const [
      'name',
      'headline',
      'avatar_url',
      'followers_count',
      'is_following',
      'is_followed',
    ]) {
      if ((normalizedAuthor[key] == null ||
              plainText(normalizedAuthor[key]).isEmpty) &&
          listAuthor[key] != null) {
        normalizedAuthor[key] = listAuthor[key];
      }
    }
    normalized['author'] = normalizedAuthor;
  }
  for (final key in const [
    'voteup_count',
    'liked_count',
    'like_count',
    'favorite_count',
    'favlists_count',
    'collection_count',
    'comment_count',
    'thanks_count',
    'visited_count',
    'visit_count',
    'play_count',
    'created_time',
    'created_at',
    'updated_time',
    'updated_at',
  ]) {
    if (normalized[key] == null && listObject[key] != null) {
      normalized[key] = listObject[key];
    }
  }
  for (final key in const ['description', 'excerpt', 'brief']) {
    if (plainText(normalized[key]).isEmpty &&
        plainText(listObject[key]).isNotEmpty) {
      normalized[key] = listObject[key];
    }
  }
  // A fuller answer body and its verified metadata can arrive from different
  // official routes. Preserve the audited video contracts just like counters
  // and dates so a long HTML response does not discard its native playlist.
  for (final key in const [
    'thumbnail_extra_info',
    'attachment',
    'video_info',
    'video',
  ]) {
    if (normalized[key] == null && listObject[key] != null) {
      normalized[key] = listObject[key];
    }
  }
  final normalizedQuestion = stringMap(normalized['question']);
  final listQuestion = stringMap(listObject['question']);
  if (normalizedQuestion != null && listQuestion != null) {
    normalized['question'] = {...listQuestion, ...normalizedQuestion};
  } else if (normalizedQuestion == null && listQuestion != null) {
    normalized['question'] = listQuestion;
  }
  final currentImage = plainText(normalized['image_url']);
  final listImage = plainText(listObject['image_url']);
  if (currentImage.isEmpty && listImage.isNotEmpty) {
    normalized['image_url'] = listImage;
  }
  // Recommendation SDUI stores body pictures in
  // extra.business_ext_map.images. A dedicated v2 detail response can carry a
  // longer HTML body while omitting that compact media list. Preserve the
  // identity-verified recommendation pictures as a native gallery fallback;
  // _InlineRichContent removes duplicates when the same URLs occur in HTML.
  if (contentImageUrlsOf(normalized, limit: 20).isEmpty) {
    final fallbackImages = contentImageUrlsOf(listObject, limit: 20);
    if (fallbackImages.isNotEmpty) {
      normalized['images'] = [
        for (final url in fallbackImages) {'url': url},
      ];
    }
  }
  return normalized;
}

String typeOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  final explicit = (object['type'] ?? source['type'] ?? '')
      .toString()
      .toLowerCase();
  if (explicit.isNotEmpty) return explicit;
  if (object['token'] != null &&
      (object['router'] != null ||
          object['matrix_text'] != null ||
          object['avatars'] is List)) {
    return 'topic';
  }
  return '';
}

/// Human-facing content kind for dense feed cards. Paid reading objects often
/// arrive inside a generic answer-like wrapper, so story/novel markers are
/// evaluated before the outer `type` field.
String contentKindLabelOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  var isStory = false;
  var isLongStory = false;
  final markers = <String>[];
  for (final node in walkVisibleMaps(source)) {
    if (node['is_story'] == true) isStory = true;
    if (node['is_long'] == true || node['is_mid_long'] == true) {
      isLongStory = true;
    }
    for (final key in const [
      'type',
      'card_type',
      'business_type',
      'property_type',
      'content_type',
      'url',
      'router',
    ]) {
      final marker = plainText(node[key]).toLowerCase();
      if (marker.isNotEmpty) markers.add(marker);
    }
  }
  final marker = markers.join(' ');
  if (isLongStory ||
      marker.contains('novel') ||
      marker.contains('manuscript') ||
      marker.contains('mid_long')) {
    return '小说';
  }
  if (isStory ||
      marker.contains('paid_column') ||
      marker.contains('paidcolumn') ||
      marker.contains('km_story') ||
      marker.contains('salt_story')) {
    return '盐选故事';
  }
  final type = typeOf(object).replaceAll('search_', '');
  if (object['_hot_rank'] == true || type == 'hot_list_feed') return '热榜';
  return switch (type) {
    'answer' => '回答',
    'article' => '文章',
    'pin' => '想法',
    'question' => '问题',
    'column' => '专栏',
    'topic' => '话题',
    'people' || 'member' => '用户',
    'publication' || 'ebook' || 'km_ebook' => '电子书',
    'live' => '直播',
    'course' || 'search_course' => '课程',
    'special' || 'search_special' => '专题',
    'zvideo' || 'video' || 'videoanswer' => '视频',
    'scholar' || 'paper' => '论文',
    'roundtable' => '圆桌',
    'favlist' || 'collection' => '收藏夹',
    'ring' => '圈子',
    'podcast' => '播客',
    'relevant_query' => '相关搜索',
    'search_query_correction' => '搜索建议',
    _ => '',
  };
}

String idOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final key in const ['id', 'token', 'business_id', 'url_token']) {
    final value = object[key];
    if (value != null && value.toString().isNotEmpty) return value.toString();
  }
  return '';
}

String? pagingNext(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  Object? paging = value['paging'];
  if (paging is! Map<String, dynamic> &&
      value['data'] is Map<String, dynamic>) {
    paging = (value['data'] as Map<String, dynamic>)['paging'];
  }
  if (paging is! Map<String, dynamic> || paging['is_end'] == true) return null;
  final next = paging['next']?.toString();
  return next == null || next.isEmpty ? null : next;
}

String? _contentMarkup(Object? value, {int depth = 0}) {
  if (depth > 6 || value == null) return null;
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    // Some pin/detail variants serialize a rich-text object inside the
    // `content` string. Decode only JSON-looking strings so ordinary HTML and
    // user text are returned byte-for-byte.
    final decoded = _decodedStructuredValue(text);
    if (!identical(decoded, text)) {
      final nested = _contentMarkup(decoded, depth: depth + 1);
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return value;
  }
  if (value is List) {
    final parts = <String>[];
    for (final item in value) {
      final part = _contentMarkup(item, depth: depth + 1);
      if (part != null && part.trim().isNotEmpty) parts.add(part.trim());
    }
    return parts.isEmpty ? null : parts.join('\n\n');
  }
  final map = stringMap(value);
  if (map == null) return null;
  for (final key in const [
    'html',
    'content_html',
    'html_content',
    'script',
    'text',
    'plain_text',
    'plain_content',
    'body',
    'content',
    'value',
    // Newer pin/detail responses use a document tree instead of the legacy
    // PinContent list. Keep the traversal generic so the client does not
    // need a second renderer just for these wire aliases.
    'blocks',
    'nodes',
    'children',
    'elements',
    'paragraphs',
    'items',
    'rich_text',
    'richText',
    'data',
  ]) {
    final nested = _contentMarkup(map[key], depth: depth + 1);
    if (nested != null && nested.trim().isNotEmpty) return nested;
  }
  return null;
}

Iterable<Map<String, dynamic>> _contentCandidates(
  Map<String, dynamic> root,
) sync* {
  var current = root;
  final seen = <Map<String, dynamic>>{};
  for (var depth = 0; depth < 5; depth++) {
    if (!seen.add(current)) return;
    yield current;
    Map<String, dynamic>? next;
    for (final key in const ['data', 'object', 'target', 'pin', 'result']) {
      final candidate = stringMap(current[key]);
      if (candidate != null) {
        next = candidate;
        break;
      }
    }
    if (next == null) return;
    current = next;
  }
}

String? htmlContent(Object? value) {
  final root = stringMap(value);
  if (root == null) return null;
  for (final object in _contentCandidates(root)) {
    for (final key in const [
      'content',
      'content_html',
      'html_content',
      'script',
      'html',
      'plain_content',
      'body',
      'text',
      'blocks',
      'nodes',
      'children',
      'elements',
      'paragraphs',
      'items',
      'rich_text',
      'richText',
    ]) {
      final content = _contentMarkup(object[key]);
      if (content != null && content.trim().isNotEmpty) return content;
    }
    final manuscript = object['manuscript_content'];
    final manuscriptMap = stringMap(manuscript);
    final manuscriptData = stringMap(manuscriptMap?['data']);
    if (manuscriptData != null) {
      final script = manuscriptData['script'];
      final scriptType = jsonInt(manuscriptData['script_type']);
      final content = _contentMarkup(script);
      if (content != null && scriptType != 1) return content;
    }
    final salt = SaltManuscriptEnvelope.fromJson(object);
    if (salt.directHtml case final direct?) return direct;
  }
  return null;
}

Object? _decodedStructuredValue(Object? value) {
  if (value is! String || value.trim().isEmpty) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}

List<Map<String, dynamic>> _structuredSegmentsFrom(Object? value) {
  Object? cursor = _decodedStructuredValue(value);
  for (var depth = 0; depth < 4; depth++) {
    if (cursor is List) {
      return cursor
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
    }
    final map = stringMap(cursor);
    if (map == null) return const [];
    final segments = _decodedStructuredValue(
      map['segments'] ?? map['segment_infos'],
    );
    if (segments is List) {
      return segments
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
    }
    cursor = _decodedStructuredValue(map['data'] ?? segments);
  }
  return const [];
}

String _structuredSegmentText(Map<String, dynamic> segment) {
  for (final key in const ['paragraph', 'heading', 'blockquote', 'quote']) {
    final nested = stringMap(segment[key]);
    final text = plainText(nested?['text'] ?? nested?['content']);
    if (text.isNotEmpty) return text;
  }
  final type = plainText(segment['type']).toLowerCase();
  if (const {
    'paragraph',
    'heading',
    'blockquote',
    'quote',
    'text',
  }.contains(type)) {
    return plainText(segment['text'] ?? segment['content']);
  }
  final rawItems = segment['items'];
  if ((type == 'list' || type == 'ordered_list' || type == 'bullet_list') &&
      rawItems is List) {
    final items = <String>[];
    for (final item in rawItems) {
      final map = stringMap(item);
      final text = plainText(map?['text'] ?? map?['content'] ?? item);
      if (text.isNotEmpty) items.add('• $text');
    }
    return items.join('\n');
  }
  return '';
}

int _structuredSegmentsScore(List<Map<String, dynamic>> segments) {
  var score = segments.length;
  for (final segment in segments) {
    score += _structuredSegmentText(segment).length * 4;
    if (segment['image'] is Map || segment['video'] is Map) score += 12;
  }
  return score;
}

bool _structuredSegmentsHaveRenderableBody(
  Iterable<Map<String, dynamic>> segments,
) {
  for (final segment in segments) {
    if (_structuredSegmentText(segment).isNotEmpty ||
        segment['image'] is Map ||
        segment['video'] is Map) {
      return true;
    }
  }
  return false;
}

/// Returns the body segments the official v2 detail renderer would prefer.
/// A purchased Salt/VIP answer carries its entitlement-aware body in
/// `structured_content_vip`; ordinary answers use `structured_content`.
/// Both fields occasionally arrive as JSON strings, so they are decoded before
/// selecting the richest body.
List<Map<String, dynamic>> structuredContentSegments(Object? value) {
  final root = stringMap(value);
  if (root == null) return const [];
  final object = stringMap(root['data']) ?? root;
  final vip = _structuredSegmentsFrom(object['structured_content_vip']);
  if (_structuredSegmentsHaveRenderableBody(vip) &&
      !_segmentsContainPaidTruncation(vip)) {
    return List.unmodifiable(vip);
  }
  final candidates = <List<Map<String, dynamic>>>[
    _structuredSegmentsFrom(object['structured_content']),
    _structuredSegmentsFrom(object['segment_infos']),
  ];
  var selected = const <Map<String, dynamic>>[];
  var selectedScore = -1;
  for (final candidate in candidates) {
    final score = _structuredSegmentsScore(candidate);
    if (score > selectedScore) {
      selected = candidate;
      selectedScore = score;
    }
  }
  return List.unmodifiable(selected);
}

bool _segmentsContainPaidTruncation(Iterable<Map<String, dynamic>> segments) {
  for (final segment in segments) {
    final card = stringMap(segment['card']);
    final marker = plainText(
      card?['card_type'] ?? segment['card_type'] ?? segment['type'],
    ).toLowerCase();
    if (marker.contains('paid-answer-tail-truncate') ||
        marker.contains('paid_answer_tail_truncate') ||
        marker.contains('card-has-not-ownership')) {
      return true;
    }
  }
  return false;
}

bool _segmentsContainPaidMarker(Iterable<Map<String, dynamic>> segments) {
  for (final segment in segments) {
    final card = stringMap(segment['card']);
    final marker = plainText(
      card?['card_type'] ?? segment['card_type'] ?? segment['type'],
    ).toLowerCase();
    if (marker.contains('kvip-paid-answer') ||
        marker.contains('paid_answer') ||
        marker.contains('card-has-ownership')) {
      return true;
    }
  }
  return false;
}

bool hasUnlockedVipStructuredContent(Object? value) {
  final root = stringMap(value);
  if (root == null) return false;
  final object = stringMap(root['data']) ?? root;
  final vip = _structuredSegmentsFrom(object['structured_content_vip']);
  return _structuredSegmentsHaveRenderableBody(vip) &&
      !_segmentsContainPaidTruncation(vip);
}

bool isPaidStructuredContent(Object? value) {
  final root = stringMap(value);
  if (root == null) return false;
  final object = stringMap(root['data']) ?? root;
  if (object.containsKey('structured_content_vip') &&
      object['structured_content_vip'] != null) {
    return true;
  }
  if (stringMap(object['paid_info']) != null) return true;
  return _segmentsContainPaidMarker(
    _structuredSegmentsFrom(object['structured_content']),
  );
}

bool isPaidStructuredContentLocked(Object? value) {
  final root = stringMap(value);
  if (root == null || hasUnlockedVipStructuredContent(root)) return false;
  final object = stringMap(root['data']) ?? root;
  final paidInfo = stringMap(object['paid_info']);
  if (paidInfo != null) return true;
  return _segmentsContainPaidTruncation(
    _structuredSegmentsFrom(object['structured_content']),
  );
}

Map<String, String> contentDetailRequestParameters(Object? value) {
  final result = <String, String>{'single_content': '1'};
  if (value == null) return Map.unmodifiable(result);
  for (final node in walkVisibleMaps(value)) {
    for (final key in const [
      'dynamic_title_info',
      'utm_id',
      'bizEncodedParams',
    ]) {
      if (result.containsKey(key)) continue;
      final text = plainText(node[key]);
      if (text.isNotEmpty && text.length <= 20000) result[key] = text;
    }
  }
  return Map.unmodifiable(result);
}

String structuredContentText(Object? value) {
  final paragraphs = <String>[];
  for (final segment in structuredContentSegments(value)) {
    final text = _structuredSegmentText(segment);
    if (text.isNotEmpty) paragraphs.add(text);
  }
  return paragraphs.join('\n\n');
}

String jsonShapeSummary(Object? value) {
  String typeOfValue(Object? item, {required bool expandMap}) {
    if (item == null) return 'null';
    if (item is String) return 'string(${item.length})';
    if (item is num) return 'number';
    if (item is bool) return 'bool';
    if (item is List) return 'list(${item.length})';
    if (item is Map) {
      if (!expandMap) return 'object(${item.length})';
      final keys = item.keys.take(24).map((key) => key.toString()).join(',');
      final suffix = item.length > 24 ? ',…' : '';
      return 'object{$keys$suffix}';
    }
    return item.runtimeType.toString();
  }

  if (value is! Map) return typeOfValue(value, expandMap: false);
  final parts = <String>[];
  for (final entry in value.entries.take(32)) {
    parts.add('${entry.key}:${typeOfValue(entry.value, expandMap: true)}');
  }
  if (value.length > 32) parts.add('…');
  return parts.join(' · ');
}

String aggregateRoutingSummary(Map<String, dynamic> source) {
  String uriShape(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return 'empty';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty) return 'unparsed(${raw.length})';
    const publicRouteWords = {
      'answer',
      'answers',
      'article',
      'articles',
      'column',
      'columns',
      'content',
      'market',
      'member',
      'p',
      'people',
      'pin',
      'pins',
      'question',
      'questions',
      'read',
      'reader',
      'zhuanlan',
    };
    String segmentShape(String segment) {
      final lower = segment.toLowerCase();
      if (publicRouteWords.contains(lower)) return lower;
      if (RegExp(r'^\d+$').hasMatch(segment)) return '{id}';
      return '{token}';
    }

    final host = uri.host.isEmpty ? '' : segmentShape(uri.host);
    final path = uri.pathSegments.map(segmentShape).join('/');
    final query = uri.queryParameters.keys.toList()..sort();
    return [
      '${uri.scheme.toLowerCase()}://$host/$path',
      if (query.isNotEmpty) '?${query.join(',')}',
    ].join();
  }

  final content = stringMap(source['content']);
  final targetSource = stringMap(source['target_source']);
  final objectId = plainText(
    targetSource?['object_id'] ?? content?['object_id'],
  );
  return [
    'notiType=${plainText(source['noti_type']).toLowerCase()}',
    'notiSubtype=${plainText(source['noti_subtype']).toLowerCase()}',
    'objectIdLen=${objectId.length}',
    'target=${uriShape(targetSource?['target_link'])}',
    'content=${uriShape(content?['target_link'])}',
    'sub=${uriShape(content?['sub_target_link'])}',
  ].join(' ');
}
