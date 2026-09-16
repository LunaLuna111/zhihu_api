import '../privacy_device_profile.dart';
import 'content_helpers.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'unwrap_and_component.dart';

// ordinary library module

Map<String, dynamic> normalizeComponentCard(Map<String, dynamic> source) {
  if ((source['type'] ?? '').toString().toLowerCase() != 'componentcard') {
    return source;
  }
  final extra = stringMap(source['extra']);
  final business = stringMap(extra?['business_ext_map']);
  final passthrough = stringMap(business?['passthrough_info']);
  final contentInfo = stringMap(business?['content_info']);
  final contentDetail = stringMap(contentInfo?['detail']);
  final parentContent = stringMap(business?['parent_content_data']);
  final content =
      stringMap(passthrough?['content']) ?? contentDetail ?? contentInfo;
  final author =
      stringMap(passthrough?['author']) ?? stringMap(business?['author']);
  final userInfo = stringMap(business?['userInfo']);
  final authorProfile = stringMap(author?['profile']);
  final authorMeta = stringMap(author?['meta']);
  final authorAvatar = stringMap(authorProfile?['avatar']);
  final statistics = stringMap(business?['statistics']);
  final detected = componentIdentity(source);

  var contentType =
      (extra?['content_type'] ??
              business?['contentType'] ??
              contentInfo?['content_type'] ??
              '')
          .toString()
          .toLowerCase();
  if (!const {'answer', 'article', 'question', 'pin'}.contains(contentType)) {
    contentType = detected.$1;
  }
  var contentId =
      (extra?['content_id'] ??
              business?['contentId'] ??
              contentInfo?['content_id'] ??
              '')
          .toString();
  if (contentId.isEmpty || contentId == source['id']?.toString()) {
    contentId = detected.$2;
  }

  var title = plainText(content?['title']);
  title = title.isNotEmpty
      ? title
      : plainText(firstNestedAlias(parentContent, const ['title', 'name']));
  title = title.isNotEmpty
      ? title
      : componentTextByMarker(source, const [
          'text_recommend_title',
          '.title',
          'headline',
        ]);
  var summary = plainText(content?['summary']);
  summary = summary.isNotEmpty
      ? summary
      : plainText(content?['plain_content'] ?? content?['content']);
  summary = summary.isNotEmpty
      ? summary
      : componentTextByMarker(source, const [
          'text_recommend_content',
          'excerpt',
          'summary',
          'description',
        ]);
  final image = componentImage(source, author, userInfo);

  final normalized = <String, dynamic>{
    ...source,
    if (contentType.isNotEmpty) 'type': contentType,
    if (contentId.isNotEmpty) 'id': contentId,
    if (title.isNotEmpty) 'title': title,
    if (summary.isNotEmpty) 'excerpt': summary,
    if (image.isNotEmpty) 'image_url': image,
    if (contentInfo?['media_detail'] != null)
      'media_detail': contentInfo?['media_detail'],
    if (business?['ori_content'] != null)
      'ori_content': business?['ori_content'],
    'component_card': true,
  };
  final normalizedAuthor = <String, dynamic>{
    ...?userInfo,
    ...?author,
    ...?authorMeta,
    ...?authorProfile,
  };
  if (plainText(normalizedAuthor['name']).isEmpty) {
    normalizedAuthor['name'] =
        normalizedAuthor['full_name'] ??
        normalizedAuthor['userName'] ??
        normalizedAuthor['nickname'];
  }
  if (plainText(normalizedAuthor['avatar_url']).isEmpty) {
    normalizedAuthor['avatar_url'] =
        authorAvatar?['url'] ??
        authorAvatar?['url_template'] ??
        normalizedAuthor['avatarUrl'] ??
        normalizedAuthor['avatar'];
  }
  if (normalizedAuthor['followers_count'] == null) {
    normalizedAuthor['followers_count'] =
        normalizedAuthor['followersCount'] ??
        normalizedAuthor['follower_count'];
  }
  if (normalizedAuthor.isNotEmpty) normalized['author'] = normalizedAuthor;

  final metricSources = [
    statistics,
    content,
    contentInfo,
    passthrough,
    business,
    extra,
  ];
  void preserveMetric(
    String target,
    List<String> aliases,
    List<String> markers,
  ) {
    Object? value;
    for (final candidate in metricSources) {
      if (candidate == null) continue;
      for (final key in aliases) {
        if (candidate[key] != null && plainText(candidate[key]).isNotEmpty) {
          value = candidate[key];
          break;
        }
      }
      if (value != null) break;
    }
    value ??= firstNestedAlias(source['children'], aliases);
    value ??= componentMetricByMarker(source, markers);
    if (plainText(value).isNotEmpty) {
      normalized[target] = value;
    }
  }

  preserveMetric(
    'voteup_count',
    const [
      'voteup_count',
      'vote_up_count',
      'up_vote_count',
      'upvote_count',
      'like_count',
    ],
    const ['.vote', '_vote', 'voteup', 'upvote', 'like_count', 'reaction_up'],
  );
  preserveMetric(
    'favorite_count',
    const [
      'favorite_count',
      'favlists_count',
      'collect_count',
      'collection_count',
      'bookmark_count',
    ],
    const ['favorite', 'favlist', 'collect', 'bookmark'],
  );
  preserveMetric(
    'comment_count',
    const ['comment_count', 'comments_count'],
    const ['comment_count', '.comment', 'comment_action'],
  );
  preserveMetric(
    'created_time',
    const ['created_time', 'created_at', 'publish_time', 'publish_timestamp'],
    const ['created_time', 'publish_time'],
  );
  preserveMetric(
    'updated_time',
    const ['updated_time', 'updated_at', 'edit_time', 'edit_timestamp'],
    const ['updated_time', 'edit_time'],
  );
  return normalized;
}

List<String> contentImageUrlsOf(Map<String, dynamic> source, {int limit = 3}) {
  final object = unwrapObject(source);
  final authorAvatar = authorAvatarOf(object);
  final images = <String>[];
  final imageKeys = <String>{};

  String dedupeKey(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    // Official SDUI payloads can repeat the same image with different resize
    // query parameters.  Those variants are one visual asset and should only
    // occupy one slot in the compact card gallery.
    return uri.replace(query: '', fragment: '').toString();
  }

  void add(Object? value) {
    if (images.length >= limit) return;
    if (value is List) {
      for (final item in value) {
        add(item);
        if (images.length >= limit) return;
      }
      return;
    }
    if (value is Map) {
      for (final key in const [
        'images',
        'image_list',
        'content',
        'content_data',
        'body',
        'items',
        'blocks',
        'nodes',
        'children',
        'elements',
        'paragraphs',
        'rich_text',
        'richText',
        'urls',
        'variants',
        'thumbnails',
        'source',
        'original',
        'thumbnail',
        'image',
        'image_content',
        'imageContent',
        'sticker_content',
        'stickerContent',
        'media_infos',
        'mediaInfos',
        'media_info',
        'mediaInfo',
      ]) {
        if (value[key] is List || value[key] is Map) {
          add(value[key]);
          if (images.length >= limit) return;
        }
      }
    }
    final candidate = httpsImageUrl(value);
    if (candidate == null || candidate == authorAvatar) return;
    if (imageKeys.add(dedupeKey(candidate))) images.add(candidate);
  }

  if (object['component_card'] == true) {
    final extra = stringMap(object['extra']);
    final business = stringMap(extra?['business_ext_map']);
    final contentInfo = stringMap(business?['content_info']);
    // The official recommendation SDUI keeps answer body pictures in this
    // business field. Generic child traversal also sees tail_element close
    // buttons and leading badge icons, so it is only a fallback.
    add(business?['images']);
    add(contentInfo?['media_detail']);
    add(object['media_detail']);
  } else {
    for (final key in const [
      'thumbnail',
      'thumbnail_info',
      'thumbnails',
      'thumbnails_v2',
      'thumbnail_url',
      'title_image',
      'cover_url',
      'cover',
      'cover_image',
      'artwork',
      'images',
      'image_list',
      'content',
      'blocks',
      'nodes',
      'children',
      'elements',
      'paragraphs',
      'rich_text',
      'richText',
      'media',
      'media_detail',
      'image',
      'image_url',
      'image_infos',
      'image_content',
      'imageContent',
      'sticker_content',
      'stickerContent',
      'media_infos',
      'mediaInfos',
      'media_info',
      'mediaInfo',
      'sticker',
      'sticker_info',
      'resource',
    ]) {
      add(object[key]);
    }
    for (final segment in structuredContentSegments(object)) {
      add(segment['image']);
      final video = stringMap(segment['video']);
      add(video?['cover_info']);
      add(video?['thumbnail']);
      add(video?['cover_url']);
    }
  }

  if (object['component_card'] == true && images.isEmpty) {
    for (final node in walkVisibleMaps(object['children'])) {
      final marker = [
        node['id'],
        node['style'],
        node['test_id'],
        node['type'],
      ].whereType<Object>().join(' ').toLowerCase();
      if (marker.trim().isEmpty) continue;
      if (const [
        'avatar',
        'author',
        'user',
        'badge',
        'icon',
        'tail',
      ].any(marker.contains)) {
        continue;
      }
      add(node['images']);
      final isContentImageNode = const [
        'content',
        'cover',
        'recommend_image',
        'thumbnail',
      ].any(marker.contains);
      if (isContentImageNode) {
        for (final key in const ['image_url', 'imageUrl', 'image', 'source']) {
          add(node[key]);
        }
      }
      if (images.length >= limit) break;
    }
  }

  // Comments commonly keep their only image inside HTML (`<img>` or a
  // media anchor). Scan this representation even when another
  // structured thumbnail was found so an avatar/preview cannot crowd out the
  // actual body media.
  if (images.length < limit) {
    final html = [
      htmlContent(object) ?? '',
      if (object['ori_content'] is String) object['ori_content'] as String,
      if (object['content'] is String) object['content'] as String,
    ].join('\n').replaceAll('&quot;', '"');
    final imagePattern = RegExp(
      r'''<img\b[^>]*?\b(?:data-original|data-original-src|data-original-url|data-actualsrc|data-src|src)=["']((?:https?:)?//[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in imagePattern.allMatches(html)) {
      final candidate = (match.group(1) ?? '').replaceAll('&amp;', '&');
      add(candidate.startsWith('//') ? 'https:$candidate' : candidate);
      if (images.length >= limit) break;
    }
    // Comment images/stickers are returned as passive anchors rather than
    // <img> nodes by several API versions. A normal link in comment text must
    // never become an image request.
    final anchorPattern = RegExp(
      r'<a\b([^>]*)>([\s\S]*?)</a\s*>',
      caseSensitive: false,
    );
    final classPattern = RegExp(
      r'''\bclass=["']([^"']*)["']''',
      caseSensitive: false,
    );
    final hrefPattern = RegExp(
      r'''\bhref=["']((?:https?:)?//[^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in anchorPattern.allMatches(html)) {
      final tag = match.group(1) ?? '';
      final classes = classPattern.firstMatch(tag)?.group(1) ?? '';
      final raw = hrefPattern.firstMatch(tag)?.group(1);
      if (raw == null) continue;
      final decoded = raw.replaceAll('&amp;', '&');
      final label = plainText(
        match.group(2) ?? '',
      ).replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final uri = Uri.tryParse(
        decoded.startsWith('//') ? 'https:$decoded' : decoded,
      );
      final path = uri?.path.toLowerCase() ?? '';
      final imageTarget =
          uri != null &&
          (path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png') ||
              path.endsWith('.webp') ||
              path.endsWith('.gif') ||
              uri.host.contains('zhimg.com'));
      final mediaClass = RegExp(
        r'(^|\s)comment_(?:sticker|img|image|gif|inline_image)(\s|$)',
        caseSensitive: false,
      ).hasMatch(classes);
      if (!mediaClass &&
          !(imageTarget && const {'[图片]', '图片', '[照片]'}.contains(label))) {
        continue;
      }
      add(decoded.startsWith('//') ? 'https:$decoded' : decoded);
      if (images.length >= limit) break;
    }
  }
  return images;
}

/// Zhihu's image CDN can reject a cold request without the same lightweight
/// origin context used by the Android client. These headers contain no user or
/// session data and are safe to reuse for public answer, avatar and cover URLs.
const zhihuImageRequestHeaders = <String, String>{
  'User-Agent': PrivacyDeviceProfile.appUserAgent,
  'Referer': 'https://www.zhihu.com/',
};

List<Map<String, dynamic>> extractRows(Object? value) {
  Object? cursor = value;
  if (cursor is Map<String, dynamic>) {
    final root = cursor;
    for (final key in const [
      'data',
      'items',
      'feeds',
      'results',
      'sections',
      'section_list',
      'sectionList',
      'chapter_list',
      'chapterList',
      'topic_list',
    ]) {
      final nested = root[key];
      if (nested is List) {
        cursor = nested;
        break;
      }
      if (nested is Map<String, dynamic>) {
        for (final child in const [
          'data',
          'items',
          'list',
          'sections',
          'section_list',
          'sectionList',
          'chapter_list',
          'chapterList',
          'topic_list',
        ]) {
          if (nested[child] is List) {
            cursor = nested[child];
            break;
          }
        }
      }
      if (cursor is List) {
        break;
      }
    }
  }
  if (cursor is! List) return const [];
  return cursor
      .whereType<Map>()
      .map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      })
      .toList(growable: false);
}
