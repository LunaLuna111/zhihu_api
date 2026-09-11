import 'rich_and_feed.dart';
import 'salt_catalog_models.dart';
import 'salt_manuscript_support.dart';
import 'unwrap_and_component.dart';

// ordinary library module

class SaltManuscriptEnvelope {
  const SaltManuscriptEnvelope({
    required this.invalid,
    required this.manuscriptId,
    required this.workId,
    required this.script,
    required this.scriptType,
    required this.articleCode,
    required this.strategy,
    required this.authenticationResult,
    required this.isLocked,
    required this.isVipResource,
    required this.isStory,
    required this.isLong,
    required this.propertyType,
    required this.windowWidth,
    required this.sectionIndex,
    required this.renderTypes,
    required this.title,
    required this.authorName,
    required this.authorAvatar,
    this.authorHeadline = '',
    this.authorBio = '',
    required this.artwork,
    required this.parentTitle,
    required this.parentArtwork,
    required this.sectionCount,
    required this.updatedSectionCount,
    required this.nextSectionId,
    required this.nextSectionTitle,
    required this.previousSectionId,
    required this.previousSectionTitle,
    required this.likeCount,
    required this.isLiked,
    required this.commentCount,
    required this.commentType,
    required this.commentContentId,
    required this.annotationCount,
    required this.annotationCommentType,
    required this.annotationExtraObjects,
    required this.createdAt,
    required this.labels,
    required this.hasTts,
    required this.isFinished,
    required this.isFirst,
    required this.isEnd,
    this.parentIntroduction = '',
    this.statusText = '',
    this.updateText = '',
    this.wordCount,
    this.viewCount,
    this.favoriteCount,
    this.commentScore = '',
    this.isOnShelf,
  });

  factory SaltManuscriptEnvelope.fromJson(Object? value) {
    final root = stringMap(value) ?? const <String, dynamic>{};
    final object = saltManuscriptObject(root);
    final wrapped = stringMap(root['data']);
    final code =
        saltFirstMap([object['code'], wrapped?['code'], root['code']]) ??
        const <String, dynamic>{};
    final sum = saltFirstMap([
      object['manuscript_sum'],
      object['manuscript'],
      wrapped?['manuscript_sum'],
      root['manuscript_sum'],
    ]);
    final info =
        saltFirstMap([
          sum?['manuscript_info'],
          object['manuscript_info'],
          wrapped?['manuscript_info'],
          root['manuscript_info'],
        ]) ??
        const <String, dynamic>{};
    final content = saltFirstMap([
      sum?['manuscript_content'],
      object['manuscript_content'],
      info['manuscript_content'],
    ]);
    final data = saltFirstMap([
      content?['data'],
      object['content'],
      object['payload'],
      if (object['data'] is Map && object['data'] != wrapped) object['data'],
    ]);
    final parent = stringMap(info['parent']);
    final next = stringMap(info['next_section']);
    final previous = stringMap(info['pre_section']);
    final like = saltFirstMap([info['like'], parent?['like'], object['like']]);
    final comment = saltFirstMap([
      info['comment'],
      parent?['comment'],
      object['comment'],
    ]);
    final annotation = saltFirstMap([info['annotation'], object['annotation']]);
    final annotationExtraObjects = <SaltAnnotationExtraObject>[];
    final rawAnnotationExtraObjects = annotation?['extra_objects'];
    if (rawAnnotationExtraObjects is List) {
      for (final candidate in rawAnnotationExtraObjects) {
        final extra = SaltAnnotationExtraObject.fromJson(candidate);
        if (extra != null) annotationExtraObjects.add(extra);
      }
    }
    final author = saltMergeAuthorMaps([
      info['authors'],
      info['author'],
      info['author_info'],
      stringMap(info['details'])?['author'],
      object['authors'],
      object['author'],
      root['author'],
    ]);
    final labels = <String>[];
    for (final source in [
      info['labels'],
      parent?['labels'],
      object['labels'],
    ]) {
      for (final label in saltLabelList(source)) {
        if (!labels.contains(label)) labels.add(label);
      }
    }
    final renderList = object['render_list'] ?? root['render_list'];
    final renderTypes = <String>[];
    if (renderList is List) {
      for (final item in renderList) {
        final type = plainText(stringMap(item)?['type']);
        if (type.isNotEmpty && !renderTypes.contains(type)) {
          renderTypes.add(type);
        }
      }
    }
    return SaltManuscriptEnvelope(
      invalid:
          saltFirstInt(object, ['invalid']) ?? saltFirstInt(root, ['invalid']),
      manuscriptId: saltFirstText(info, ['id', 'manuscript_id']),
      workId: saltFirstText(info, ['work_id', 'business_id', 'well_id']),
      script:
          (data?['script'] ?? content?['script'] ?? object['script']) is String
          ? (data?['script'] ?? content?['script'] ?? object['script'])
                as String
          : null,
      scriptType:
          saltFirstInt(data, ['script_type']) ??
          saltFirstInt(content, ['script_type']) ??
          saltFirstInt(object, ['script_type']),
      articleCode: saltManuscriptText(
        code['article_code'] ??
            object['article_code'] ??
            content?['article_code'] ??
            data?['article_code'] ??
            root['article_code'],
      ),
      // An empty strategy is meaningful and selects the SHA-1 branch in the
      // official reader. Preserve it verbatim instead of using plainText(),
      // which trims short whitespace strategies into a different length.
      strategy:
          (code['log'] ?? object['log'] ?? content?['log'] ?? data?['log'])
              ?.toString() ??
          '',
      authenticationResult:
          saltFirstBool(info, ['authentication_result']) ??
          saltFirstBool(object, ['authentication_result']) ??
          saltFirstBool(root, ['authentication_result']),
      isLocked:
          saltFirstBool(info, ['is_lock', 'is_locked']) ??
          saltFirstBool(object, ['is_lock', 'is_locked']),
      isVipResource:
          saltFirstBool(info, ['is_vip_resource', 'is_vip', 'vip']) ??
          saltFirstBool(object, ['is_vip_resource', 'is_vip', 'vip']),
      isStory:
          saltFirstBool(info, ['is_story']) ??
          saltFirstBool(object, ['is_story']),
      isLong:
          saltFirstBool(info, ['is_long', 'is_long_story']) ??
          saltFirstBool(object, ['is_long', 'is_long_story']),
      propertyType:
          saltFirstText(info, [
            'property_type',
            'business_type',
            'content_type',
            'type',
          ]).isNotEmpty
          ? saltFirstText(info, [
              'property_type',
              'business_type',
              'content_type',
              'type',
            ])
          : saltFirstText(parent, [
              'property_type',
              'business_type',
              'content_type',
              'type',
            ]),
      windowWidth:
          saltFirstInt(info, ['window_width']) ??
          saltFirstInt(object, ['window_width']),
      sectionIndex:
          saltFirstInt(info, ['section_index', 'index', 'idx']) ??
          saltFirstInt(object, ['section_index', 'index', 'idx']),
      renderTypes: List.unmodifiable(renderTypes),
      title: saltFirstText(info, ['title', 'name']),
      authorName: saltAuthorField(author, [
        'name',
        'nickname',
        'nick_name',
        'display_name',
        'full_name',
        'author_name',
        'authorName',
        'username',
        'user_name',
      ]),
      authorAvatar: saltArtworkUrl(
        author?['avatar_url'] ??
            author?['avatarUrl'] ??
            author?['avatar'] ??
            author?['head'] ??
            author?['image'] ??
            author?['image_url'],
      ),
      authorHeadline: saltAuthorField(author, [
        'headline',
        'headline_render',
        'signature',
        'description',
        'intro',
        'sub_title',
      ]),
      authorBio: saltAuthorField(author, [
        'bio',
        'biography',
        'profile',
        'introduction',
      ]),
      artwork: saltArtworkUrl(
        info['artwork'] ?? info['head_artwork'] ?? info['cover_url'],
      ),
      parentTitle: saltFirstText(parent, ['title', 'name']),
      parentArtwork: saltArtworkUrl(
        parent?['artwork'] ?? parent?['tab_artwork'] ?? parent?['cover_url'],
      ),
      sectionCount:
          saltFirstInt(parent, [
            'section_count',
            'chapter_count',
            'total_section_count',
            'total',
          ]) ??
          saltFirstInt(info, [
            'section_count',
            'chapter_count',
            'total_section_count',
            'total',
          ]),
      updatedSectionCount:
          saltFirstInt(parent, [
            'updated_section_count',
            'latest_section_count',
            'new_section_count',
            'update_count',
          ]) ??
          saltFirstInt(info, [
            'updated_section_count',
            'latest_section_count',
            'new_section_count',
            'update_count',
          ]),
      nextSectionId: saltFirstText(next, ['id', 'section_id']),
      nextSectionTitle: saltFirstText(next, ['title', 'name']),
      previousSectionId: saltFirstText(previous, ['id', 'section_id']),
      previousSectionTitle: saltFirstText(previous, ['title', 'name']),
      likeCount:
          saltFirstInt(like, ['like_count', 'count']) ??
          saltFirstInt(info, ['like_count']) ??
          saltFirstInt(parent, ['like_count']),
      isLiked:
          saltFirstBool(like, ['is_like', 'is_liked']) ??
          saltFirstBool(info, ['is_like', 'is_liked']),
      commentCount:
          saltFirstInt(comment, ['comment_count', 'count']) ??
          saltFirstInt(info, ['comment_count', 'comments_count']) ??
          saltFirstInt(parent, ['comment_count', 'comments_count']),
      commentType: saltFirstText(comment, ['comment_type', 'type']),
      commentContentId: saltFirstText(comment, [
        'comment_content_id',
        'content_id',
        'id',
      ]),
      annotationCount: saltFirstInt(annotation, ['count', 'comment_count']),
      annotationCommentType: saltFirstText(annotation, [
        'annotation_comment_type',
        'comment_type',
        'type',
      ]),
      annotationExtraObjects: List.unmodifiable(annotationExtraObjects),
      createdAt: saltFirstInt(info, ['created_at', 'create_time']),
      labels: List.unmodifiable(labels),
      hasTts:
          saltFirstBool(info, ['has_tts', 'has_audio', 'is_audio']) ??
          saltFirstBool(parent, ['has_tts', 'has_audio', 'is_audio']),
      isFinished:
          saltFirstBool(info, [
            'is_finished',
            'is_finish',
            'finished',
            'completed',
          ]) ??
          saltFirstBool(parent, [
            'is_finished',
            'is_finish',
            'finished',
            'completed',
          ]),
      isFirst: saltFirstBool(info, ['is_first']),
      isEnd: saltFirstBool(info, ['is_end']),
      parentIntroduction: saltFirstText(parent, [
        'introduction',
        'description',
        'summary',
        'synopsis',
        'brief',
        'excerpt',
        'description_list',
        'intro',
        'content_abstract',
      ]),
      statusText: saltTextFromMaps(
        [info, parent, object],
        [
          'completion_text',
          'finish_status_text',
          'status_text',
          'status',
          'content_status',
        ],
      ),
      updateText: saltTextFromMaps(
        [info, parent, object],
        [
          'update_text',
          'latest_update_text',
          'last_update_text',
          'online_time_text',
          'published_text',
        ],
      ),
      wordCount:
          saltFirstInt(info, ['word_count', 'words_count']) ??
          saltFirstInt(parent, ['word_count', 'words_count']),
      viewCount:
          saltFirstInt(info, [
            'view_count',
            'views_count',
            'browse_count',
            'read_count',
          ]) ??
          saltFirstInt(parent, [
            'view_count',
            'views_count',
            'browse_count',
            'read_count',
          ]),
      favoriteCount:
          saltFirstInt(info, ['favorite_count', 'favorites_count']) ??
          saltFirstInt(parent, ['favorite_count', 'favorites_count']),
      commentScore: saltTextFromMaps(
        [info, parent, object],
        ['comment_score', 'score_text'],
      ),
      isOnShelf:
          saltFirstBool(info, [
            'has_interested',
            'on_shelves',
            'on_shelf',
            'is_on_shelves',
          ]) ??
          saltFirstBool(parent, [
            'has_interested',
            'on_shelves',
            'on_shelf',
            'is_on_shelves',
          ]),
    );
  }

  final int? invalid;
  final String manuscriptId;
  final String workId;
  final String? script;
  final int? scriptType;
  final String articleCode;
  final String strategy;
  final bool? authenticationResult;
  final bool? isLocked;
  final bool? isVipResource;
  final bool? isStory;
  final bool? isLong;
  final String propertyType;
  final int? windowWidth;
  final int? sectionIndex;
  final List<String> renderTypes;
  final String title;
  final String authorName;
  final String authorAvatar;
  final String authorHeadline;
  final String authorBio;
  final String artwork;
  final String parentTitle;
  final String parentArtwork;
  final int? sectionCount;
  final int? updatedSectionCount;
  final String nextSectionId;
  final String nextSectionTitle;
  final String previousSectionId;
  final String previousSectionTitle;
  final int? likeCount;
  final bool? isLiked;
  final int? commentCount;
  final String commentType;
  final String commentContentId;
  final int? annotationCount;
  final String annotationCommentType;
  final List<SaltAnnotationExtraObject> annotationExtraObjects;
  final int? createdAt;
  final List<String> labels;
  final bool? hasTts;
  final bool? isFinished;
  final bool? isFirst;
  final bool? isEnd;
  final String parentIntroduction;
  final String statusText;
  final String updateText;
  final int? wordCount;
  final int? viewCount;
  final int? favoriteCount;
  final String commentScore;
  final bool? isOnShelf;

  bool get hasScript => script?.isNotEmpty == true;

  /// `script_type=1` is the active App 11.4.0 encrypted XHTML transport.
  bool get isTransportEncoded => hasScript && scriptType == 1;
  bool get requiresNativeRenderer => false;
  bool get canDecodeTransport => isTransportEncoded;

  /// Encoded transport must be decrypted before it is exposed as XHTML.
  String? get directHtml {
    if (!hasScript || isTransportEncoded) return null;
    return script;
  }
}
