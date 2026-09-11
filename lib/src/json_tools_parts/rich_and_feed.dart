import '../content_interaction_models.dart';
import 'unwrap_and_component.dart';

// ordinary library module

final _scriptTagPattern = RegExp(
  r'<script\b[^>]*>[\s\S]*?</script>',
  caseSensitive: false,
);
final _styleTagPattern = RegExp(
  r'<style\b[^>]*>[\s\S]*?</style>',
  caseSensitive: false,
);
final _htmlTagPattern = RegExp(r'<[^>]+>');
final _collapsedWhitespacePattern = RegExp(r'\s+');

String plainText(Object? value) {
  if (value == null) return '';
  final source = value.toString();
  return source
      .replaceAll(_scriptTagPattern, '')
      .replaceAll(_styleTagPattern, '')
      .replaceAll(_htmlTagPattern, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(_collapsedWhitespacePattern, ' ')
      .trim();
}

class RichContentVideo {
  RichContentVideo({
    this.videoId = '',
    this.title = '',
    this.posterUrl = '',
    Iterable<String> sourceUrls = const [],
    Map<String, String> sourceFormats = const {},
    this.durationSeconds,
    this.width,
    this.height,
    this.isPaid = false,
    this.isTrial = false,
    this.isDisabledPlay = false,
    this.isPaidSpecified = false,
    this.isTrialSpecified = false,
    this.isDisabledPlaySpecified = false,
    this.isStandalone = false,
  }) : sourceUrls = List.unmodifiable(sourceUrls),
       sourceFormats = Map.unmodifiable(sourceFormats);

  final String videoId;
  final String title;
  final String posterUrl;
  final List<String> sourceUrls;
  final Map<String, String> sourceFormats;
  final int? durationSeconds;
  final int? width;
  final int? height;
  final bool isPaid;
  final bool isTrial;
  final bool isDisabledPlay;
  final bool isPaidSpecified;
  final bool isTrialSpecified;
  final bool isDisabledPlaySpecified;
  final bool isStandalone;

  /// Keeps this video's higher-priority display metadata while filling gaps
  /// from [other]. Restrictive playback flags are never lost during a merge.
  RichContentVideo mergedWith(RichContentVideo other) {
    final sources = <String>[];
    for (final source in [...sourceUrls, ...other.sourceUrls]) {
      if (!sources.contains(source)) sources.add(source);
    }
    final mergedPaid = isPaid || other.isPaid;
    final mergedTrial = isTrialSpecified ? isTrial : other.isTrial;
    return RichContentVideo(
      videoId: videoId.isNotEmpty ? videoId : other.videoId,
      title: title.isNotEmpty ? title : other.title,
      posterUrl: posterUrl.isNotEmpty ? posterUrl : other.posterUrl,
      sourceUrls: sources,
      sourceFormats: {...other.sourceFormats, ...sourceFormats},
      durationSeconds: durationSeconds ?? other.durationSeconds,
      width: width ?? other.width,
      height: height ?? other.height,
      isPaid: mergedPaid,
      isTrial: mergedTrial,
      isDisabledPlay: isDisabledPlay || other.isDisabledPlay,
      isPaidSpecified: isPaidSpecified || other.isPaidSpecified,
      isTrialSpecified: isTrialSpecified || other.isTrialSpecified,
      isDisabledPlaySpecified:
          isDisabledPlaySpecified || other.isDisabledPlaySpecified,
      isStandalone: isStandalone || other.isStandalone,
    );
  }
}

class RichContentBlock {
  RichContentBlock.text(this.text, {this.linkUrl = '', this.nodeId = ''})
    : imageUrl = '',
      video = null,
      node = linkUrl.isEmpty
          ? ContentNode.text(text, id: nodeId)
          : ContentNode.link(text, url: linkUrl, id: nodeId);
  RichContentBlock.image(this.imageUrl, {this.nodeId = ''})
    : text = '',
      linkUrl = '',
      video = null,
      node = ContentNode.image(imageUrl, id: nodeId);
  RichContentBlock.video(RichContentVideo value, {this.nodeId = ''})
    : text = '',
      imageUrl = '',
      linkUrl = '',
      video = value,
      node = ContentNode.video(value.posterUrl, id: nodeId, title: value.title);

  final String text;
  final String imageUrl;
  final String linkUrl;
  final RichContentVideo? video;
  final String nodeId;
  final ContentNode node;

  bool get isImage => imageUrl.isNotEmpty;
  bool get isVideo => video != null;
  bool get isLink => linkUrl.isNotEmpty;
}

/// Extracts the finite set of answer-video shapes used by the original
/// client. URLs are accepted only when they resolve to HTTPS without embedded
/// credentials and without a non-standard port.
List<RichContentVideo> contentVideosOf(Object? value) {
  final rawSource = stringMap(value);
  if (rawSource == null) return const [];
  // Search results wrap their semantic object, while /zvideos/{id} and Lens
  // return it directly. Normalizing here lets all three official contracts
  // share the same player without teaching widgets about wire containers.
  final source = unwrapObject(rawSource);
  final result = <RichContentVideo>[];

  void add(RichContentVideo? video) {
    if (video == null ||
        (video.videoId.isEmpty &&
            video.posterUrl.isEmpty &&
            video.sourceUrls.isEmpty)) {
      return;
    }
    final index = result.indexWhere((existing) {
      if (video.videoId.isNotEmpty && existing.videoId.isNotEmpty) {
        return existing.videoId == video.videoId;
      }
      if (video.sourceUrls.any(existing.sourceUrls.contains)) return true;
      if (video.posterUrl.isNotEmpty && video.posterUrl == existing.posterUrl) {
        return true;
      }
      return false;
    });
    if (index < 0) {
      result.add(video);
    } else {
      result[index] = result[index].mergedWith(video);
    }
  }

  void addThumbnailInfo(Object? raw, {bool standalone = false}) {
    if (raw is List) {
      for (final item in raw) {
        addThumbnailInfo(item, standalone: standalone);
      }
      return;
    }
    final info = stringMap(raw);
    if (info != null) {
      add(
        _richVideoFromJson(info, thumbnailInfo: true, standalone: standalone),
      );
    }
  }

  // ThumbnailInfo is what the original answer renderer asks for first.
  addThumbnailInfo(source['thumbnail_extra_info']);
  // Question detail uses the plural v2 field for prompt-level videos. These
  // are standalone media even when the question body itself is plain text.
  addThumbnailInfo(source['thumbnails_v2'], standalone: true);

  final attachment = stringMap(source['attachment']);
  final attachmentVideo = stringMap(attachment?['video']);
  final attachmentVideoInfo = stringMap(attachmentVideo?['video_info']);
  if (attachmentVideoInfo != null) {
    add(
      _richVideoFromJson(
        attachmentVideoInfo,
        fallbackId: plainText(attachmentVideo?['sub_video_id']),
        fallbackTitle: plainText(attachmentVideo?['title']),
        standalone: true,
      ),
    );
  }
  final legacyInfo = stringMap(source['video_info']);
  final legacyVideos = legacyInfo?['videos'];
  if (legacyVideos is List) {
    for (final raw in legacyVideos) {
      final video = stringMap(raw);
      if (video != null) add(_richVideoFromJson(video));
    }
  } else if (legacyInfo != null &&
      (legacyInfo.containsKey('video_id') ||
          legacyInfo.containsKey('sub_video_id') ||
          legacyInfo.containsKey('playlist') ||
          legacyInfo.containsKey('playlist_v2'))) {
    // Short-content/pin responses use video_info as the video object itself,
    // unlike Answer.video_info which is a {videos:[...]} catalog.
    add(
      _richVideoFromJson(
        legacyInfo,
        fallbackTitle: _videoTitleText(source['title']),
        standalone: true,
      ),
    );
  }

  final simpleZVideo = stringMap(attachment?['zvideo']);
  if (simpleZVideo != null) {
    add(
      _richVideoFromJson(
        simpleZVideo,
        fallbackTitle: _videoTitleText(source['title']),
        standalone: true,
      ),
    );
  }

  final modernVideo = stringMap(source['video']);
  final modernInfo = stringMap(modernVideo?['video_info']);
  if (modernInfo != null) {
    add(
      _richVideoFromJson(
        modernInfo,
        fallbackId: plainText(modernVideo?['sub_video_id']),
        fallbackTitle: plainText(modernVideo?['title']),
        standalone: true,
      ),
    );
  }
  if (modernVideo != null) {
    // VideoEntity (the object returned by /zvideos/{id}) stores ThumbnailInfo
    // directly under `video`; the video search tab uses the same node with a
    // nested thumbnail object and `duration_in_seconds`. Neither has the
    // answer-only `video.video_info` wrapper handled above.
    final direct = <String, dynamic>{...modernVideo};
    final parentTitle = _videoTitleText(source['title']);
    final paidInfo = stringMap(source['paid_info']);
    if (direct['title'] == null && parentTitle.isNotEmpty) {
      direct['title'] = parentTitle;
    }
    if (direct['thumbnail'] == null) {
      direct['thumbnail'] =
          source['cover_image'] ?? source['image_url'] ?? source['cover_url'];
    }
    if (direct['duration'] == null) {
      direct['duration'] = direct['duration_in_seconds'] ?? source['duration'];
    }
    if (paidInfo != null && direct['is_paid'] == null) {
      direct['is_paid'] = true;
      direct['is_trial'] ??= paidInfo['is_trial'];
    }
    add(
      _richVideoFromJson(direct, fallbackTitle: parentTitle, standalone: true),
    );
  }

  // Some search and profile feeds expose the video fields at the semantic
  // object root rather than under `video`.
  final semanticType = plainText(source['type']).toLowerCase();
  final rootHasPlaylist =
      source['playlist'] is Map ||
      source['playlist'] is List ||
      source['playlist_v2'] is Map ||
      source['playlist_v2'] is List;
  if ((semanticType == 'zvideo' || semanticType == 'video') &&
      (rootHasPlaylist ||
          source.containsKey('video_id') ||
          source.containsKey('cover_image'))) {
    add(
      _richVideoFromJson(
        source,
        fallbackTitle: _videoTitleText(source['title']),
        standalone: true,
      ),
    );
  }

  // The /lens/.../v4 response is itself a video object rather than an answer.
  if ((source['playlist'] is Map ||
          source['playlist'] is List ||
          source['playlist_v2'] is Map ||
          source['playlist_v2'] is List) &&
      (source.containsKey('id') ||
          source.containsKey('cover_url') ||
          source.containsKey('thumbnail'))) {
    add(_richVideoFromJson(source));
  }

  return List.unmodifiable(result);
}

RichContentVideo _richVideoFromJson(
  Map<String, dynamic> source, {
  String fallbackId = '',
  String fallbackTitle = '',
  bool thumbnailInfo = false,
  bool standalone = false,
}) {
  final sources = <String>[];
  final sourceFormats = <String, String>{};
  void addSources(Object? playlist) {
    for (final source in _orderedVideoSources(playlist)) {
      if (!sources.contains(source.url)) sources.add(source.url);
      if (source.format.isNotEmpty) {
        sourceFormats[source.url] = source.format;
      }
    }
  }

  // playlist is H.264 in the original contract. playlist_v2 is considered
  // only after all of its qualities, preserving the player's compatibility
  // preference.
  addSources(source['playlist']);
  addSources(source['playlist_v2']);

  String firstHttps(Iterable<Object?> values) {
    for (final value in values) {
      final url = _strictHttpsUrl(value);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  final beginFrame = stringMap(source['begin_frame']);
  final coverInfo = stringMap(source['cover_info']);
  final thumbnail = stringMap(source['thumbnail']);
  final disabledPlay = _videoBool(source['is_disabled_play']);
  final cover = thumbnailInfo
      ? firstHttps([
          coverInfo?['thumbnail'],
          thumbnail?['image_url'],
          thumbnail?['url'],
          source['url'],
          source['thumbnail'],
          source['cover_url'],
          source['cover_image'],
          source['image_url'],
          if (!disabledPlay) beginFrame?['fhd'],
          if (!disabledPlay) beginFrame?['hd'],
          if (!disabledPlay) beginFrame?['sd'],
          if (!disabledPlay) beginFrame?['ld'],
        ])
      : firstHttps([
          source['cover_url'],
          source['cover_image'],
          source['image_url'],
          source['thumbnail'],
          thumbnail?['image_url'],
          thumbnail?['url'],
          coverInfo?['thumbnail'],
          if (!disabledPlay) beginFrame?['fhd'],
          if (!disabledPlay) beginFrame?['hd'],
          if (!disabledPlay) beginFrame?['sd'],
          if (!disabledPlay) beginFrame?['ld'],
        ]);
  final id = fallbackId.isNotEmpty
      ? fallbackId
      : plainText(source['video_id'] ?? source['sub_video_id'] ?? source['id']);
  final title = fallbackTitle.isNotEmpty
      ? fallbackTitle
      : _videoTitleText(source['title']);
  return RichContentVideo(
    videoId: id,
    title: title,
    posterUrl: cover,
    sourceUrls: sources,
    sourceFormats: sourceFormats,
    durationSeconds: _positiveVideoInt(
      source['duration'] ?? source['duration_in_seconds'],
    ),
    width: _positiveVideoInt(source['width'] ?? thumbnail?['width']),
    height: _positiveVideoInt(source['height'] ?? thumbnail?['height']),
    isPaid: _videoBool(source['is_paid']),
    isTrial: _videoBool(source['is_trial']),
    isDisabledPlay: disabledPlay,
    isPaidSpecified: source.containsKey('is_paid'),
    isTrialSpecified: source.containsKey('is_trial'),
    isDisabledPlaySpecified: source.containsKey('is_disabled_play'),
    isStandalone: standalone,
  );
}

String _videoTitleText(Object? value) {
  final map = stringMap(value);
  return plainText(map?['plain_text'] ?? map?['text'] ?? map?['name'] ?? value);
}

class _RichVideoSource {
  const _RichVideoSource(this.url, this.format);

  final String url;
  final String format;
}

List<_RichVideoSource> _orderedVideoSources(Object? value) {
  final result = <_RichVideoSource>[];
  void add(Object? raw) {
    final source = stringMap(raw);
    final candidates = source == null
        ? <Object?>[raw]
        : <Object?>[source['url'], source['play_url']];
    for (final candidate in candidates) {
      final url = _strictHttpsUrl(candidate);
      if (url.isNotEmpty) {
        if (!result.any((existing) => existing.url == url)) {
          result.add(
            _RichVideoSource(url, plainText(source?['format']).toLowerCase()),
          );
        }
        return;
      }
    }
  }

  final map = stringMap(value);
  if (map != null) {
    for (final quality in const ['hd', 'sd', 'fhd', 'ld']) {
      add(map[quality]);
    }
    return result;
  }
  if (value is List) {
    for (final quality in const ['hd', 'sd', 'fhd', 'ld']) {
      for (final raw in value) {
        final item = stringMap(raw);
        if (item != null &&
            plainText(item['quality']).toLowerCase() == quality) {
          add(item);
        }
      }
    }
  }
  return result;
}

int? _positiveVideoInt(Object? value) {
  final parsed = value is num
      ? value.round()
      : double.tryParse(plainText(value))?.round();
  return parsed != null && parsed > 0 ? parsed : null;
}

bool _videoBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(plainText(value).toLowerCase());
}

String _strictHttpsUrl(Object? value) {
  var raw = value?.toString().trim() ?? '';
  if (raw.startsWith('//')) raw = 'https:$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return '';
  }
  return uri.toString();
}

/// Converts answer/article HTML into ordered text, image and video blocks for
/// native Flutter rendering. Scripts, styles and embedded frames are removed.
List<RichContentBlock> richContentBlocks(
  String html, {
  List<RichContentVideo> videos = const [],
}) {
  final safe = html
      .replaceAll(
        RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<iframe\b[^>]*>[\s\S]*?</iframe>', caseSensitive: false),
        '',
      );
  final mediaPattern = RegExp(
    r'<a\b[^>]*>[\s\S]*?</a\s*>|<video\b[^>]*(?:/>|>[\s\S]*?</video\s*>)|<img\b[^>]*>',
    caseSensitive: false,
  );
  final blocks = <RichContentBlock>[];
  final matchedCatalogIndexes = <int>{};

  void addText(String fragment) {
    final separated = fragment
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</(?:p|div|h[1-6]|li|blockquote|pre)>',
            caseSensitive: false,
          ),
          '\n\n',
        )
        .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    for (final paragraph in separated.split(RegExp(r'\n\s*\n+'))) {
      final text = paragraph.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').trim();
      if (text.isNotEmpty) {
        blocks.add(
          RichContentBlock.text(text, nodeId: 'html-text-${blocks.length}'),
        );
      }
    }
  }

  int catalogIndexFor(String videoId) {
    if (videoId.isEmpty) return -1;
    return videos.indexWhere((video) => video.videoId == videoId);
  }

  RichContentVideo htmlMetadata(
    String tag, {
    String videoId = '',
    Iterable<String> sources = const [],
    Map<String, String> sourceFormats = const {},
  }) {
    final duration =
        _positiveVideoInt(_htmlAttribute(tag, 'data-duration')) ??
        _positiveVideoInt(_htmlAttribute(tag, 'duration'));
    return RichContentVideo(
      videoId: videoId,
      title: _decodeRichHtml(
        _htmlAttribute(tag, 'data-name').isNotEmpty
            ? _htmlAttribute(tag, 'data-name')
            : _htmlAttribute(tag, 'title'),
      ),
      posterUrl: _strictHttpsHtmlUrl(
        _htmlAttribute(tag, 'data-poster').isNotEmpty
            ? _htmlAttribute(tag, 'data-poster')
            : _htmlAttribute(tag, 'poster'),
      ),
      sourceUrls: sources,
      sourceFormats: sourceFormats,
      durationSeconds: duration,
    );
  }

  var cursor = 0;
  for (final match in mediaPattern.allMatches(safe)) {
    addText(safe.substring(cursor, match.start));
    final token = match.group(0) ?? '';
    final lower = token.toLowerCase();
    if (lower.startsWith('<img')) {
      var imageUrl = '';
      for (final attribute in const [
        'data-original',
        'data-actualsrc',
        'src',
      ]) {
        imageUrl = _strictHttpsHtmlUrl(_htmlAttribute(token, attribute));
        if (imageUrl.isNotEmpty) break;
      }
      if (imageUrl.isNotEmpty) {
        blocks.add(
          RichContentBlock.image(
            imageUrl,
            nodeId: 'html-image-${blocks.length}',
          ),
        );
      }
    } else if (lower.startsWith('<a')) {
      final openingEnd = token.indexOf('>');
      final openingTag = openingEnd < 0
          ? token
          : token.substring(0, openingEnd + 1);
      final classes = _htmlAttribute(
        openingTag,
        'class',
      ).toLowerCase().split(RegExp(r'\s+'));
      final videoId = _htmlAttribute(openingTag, 'data-lens-id').trim();
      final isOfficialVideo =
          videoId.isNotEmpty &&
          (classes.contains('video-box') || classes.contains('video-link'));
      if (isOfficialVideo) {
        final catalogIndex = catalogIndexFor(videoId);
        var video = htmlMetadata(openingTag, videoId: videoId);
        if (catalogIndex >= 0) {
          matchedCatalogIndexes.add(catalogIndex);
          video = video.mergedWith(videos[catalogIndex]);
        }
        blocks.add(
          RichContentBlock.video(
            video,
            nodeId:
                'html-video-${video.videoId.isNotEmpty ? video.videoId : blocks.length}',
          ),
        );
      } else {
        // An arbitrary external link styled as a video card must never become
        // an implicit media request. Preserve its visible text and images.
        final inner = openingEnd < 0
            ? token
            : token
                  .substring(openingEnd + 1)
                  .replaceFirst(RegExp(r'</a\s*>$', caseSensitive: false), '');
        final href = _decodeRichHtml(_htmlAttribute(openingTag, 'href'));
        for (final child in richContentBlocks(inner)) {
          if (child.isImage) {
            blocks.add(child);
          } else if (!child.isVideo && child.text.isNotEmpty) {
            blocks.add(
              RichContentBlock.text(
                child.text,
                linkUrl: href,
                nodeId: 'html-link-${blocks.length}',
              ),
            );
          }
        }
      }
    } else if (lower.startsWith('<video')) {
      final openingEnd = token.indexOf('>');
      final openingTag = openingEnd < 0
          ? token
          : token.substring(0, openingEnd + 1);
      final videoId = _htmlAttribute(openingTag, 'data-lens-id').trim();
      final directSources = <String>[];
      final directSourceFormats = <String, String>{};
      void addDirect(Object? value, {String format = ''}) {
        final url = _strictHttpsHtmlUrl(value);
        if (url.isNotEmpty && !directSources.contains(url)) {
          directSources.add(url);
          if (format.isNotEmpty) directSourceFormats[url] = format;
        }
      }

      addDirect(
        _htmlAttribute(openingTag, 'src'),
        format: _htmlAttribute(openingTag, 'type'),
      );
      final sourceTags = RegExp(
        r'<source\b[^>]*>',
        caseSensitive: false,
      ).allMatches(token);
      for (final sourceTag in sourceTags) {
        final tag = sourceTag.group(0) ?? '';
        addDirect(
          _htmlAttribute(tag, 'src'),
          format: _htmlAttribute(tag, 'type'),
        );
      }
      final catalogIndex = catalogIndexFor(videoId);
      var video = htmlMetadata(
        openingTag,
        videoId: videoId,
        sources: directSources,
        sourceFormats: directSourceFormats,
      );
      if (catalogIndex >= 0) {
        matchedCatalogIndexes.add(catalogIndex);
        video = video.mergedWith(videos[catalogIndex]);
      }
      if (video.videoId.isNotEmpty ||
          video.posterUrl.isNotEmpty ||
          video.sourceUrls.isNotEmpty) {
        blocks.add(
          RichContentBlock.video(
            video,
            nodeId:
                'html-video-${video.videoId.isNotEmpty ? video.videoId : blocks.length}',
          ),
        );
      }
    }
    cursor = match.end;
  }
  addText(safe.substring(cursor));
  final fallbackVideos = <RichContentBlock>[];
  final bodyHasMediaOrText = blocks.isNotEmpty;
  for (var index = 0; index < videos.length; index++) {
    if (!matchedCatalogIndexes.contains(index) &&
        (videos[index].isStandalone ||
            (!bodyHasMediaOrText && videos.length == 1))) {
      fallbackVideos.add(
        RichContentBlock.video(
          videos[index],
          nodeId:
              'catalog-video-${videos[index].videoId.isNotEmpty ? videos[index].videoId : index}',
        ),
      );
    }
  }
  return List.unmodifiable([...fallbackVideos, ...blocks]);
}

String _htmlAttribute(String tag, String name) {
  final pattern = RegExp(
    '''\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))''',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(tag);
  return match?.group(1) ?? match?.group(2) ?? match?.group(3) ?? '';
}

String _decodeRichHtml(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}

String _strictHttpsHtmlUrl(Object? value) {
  return _strictHttpsUrl(_decodeRichHtml(value?.toString() ?? ''));
}
