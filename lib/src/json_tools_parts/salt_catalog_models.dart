import 'components_and_images.dart';
import 'content_helpers.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'salt_manuscript_envelope.dart';
import 'salt_models.dart';
import 'unwrap_and_component.dart';

// ordinary library module

class SaltAnnotationExtraObject {
  const SaltAnnotationExtraObject({
    required this.objectType,
    required this.objectId,
  });

  static SaltAnnotationExtraObject? fromJson(Object? value) {
    final object = stringMap(value);
    final objectType = plainText(object?['object_type']).trim();
    final objectId = plainText(object?['object_id']).trim();
    if (!RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(objectType) ||
        !RegExp(r'^\d+$').hasMatch(objectId)) {
      return null;
    }
    return SaltAnnotationExtraObject(
      objectType: objectType,
      objectId: objectId,
    );
  }

  final String objectType;
  final String objectId;
}

class SaltParagraphAnnotation {
  const SaltParagraphAnnotation({
    required this.paragraphIndex,
    required this.commentId,
    required this.commentCount,
    required this.hasOwnComment,
  });

  final int paragraphIndex;
  final String commentId;
  final int commentCount;
  final bool hasOwnComment;
}

class SaltCatalogSectionInfo {
  const SaltCatalogSectionInfo({
    required this.id,
    required this.title,
    required this.index,
  });

  final String id;
  final String title;
  final int index;
}

class SaltCatalogNavigation {
  const SaltCatalogNavigation({
    required this.sections,
    required this.total,
    required this.currentIndex,
    required this.previous,
    required this.next,
  });

  final List<SaltCatalogSectionInfo> sections;
  final int? total;
  final int? currentIndex;
  final SaltCatalogSectionInfo? previous;
  final SaltCatalogSectionInfo? next;
}

/// Merges the forward/backward catalog windows used by `NovelCatalogVM` and
/// derives chapter navigation from the server's zero-based `global_idx`.
SaltCatalogNavigation saltCatalogNavigationOf(
  Iterable<Object?> responses, {
  required String currentSectionId,
  int? fallbackIndex,
}) {
  final byId = <String, SaltCatalogSectionInfo>{};
  int? total;
  for (final response in responses) {
    final root = stringMap(response);
    final paging = stringMap(root?['paging']);
    final candidateTotal = jsonInt(paging?['total'] ?? paging?['totals']);
    if (candidateTotal != null && candidateTotal > 0) {
      total = total == null || candidateTotal > total ? candidateTotal : total;
    }
    for (final row in extractRows(response)) {
      final id = numericIdentifier(row['section_id'] ?? row['id']);
      final index = jsonInt(row['global_idx'] ?? row['idx']);
      if (id == null || id == '0' || index == null || index < 0) continue;
      byId[id] = SaltCatalogSectionInfo(
        id: id,
        title: plainText(row['title']),
        index: index,
      );
    }
  }
  final sections = byId.values.toList()
    ..sort((left, right) {
      final byIndex = left.index.compareTo(right.index);
      return byIndex != 0 ? byIndex : left.id.compareTo(right.id);
    });
  final current = byId[currentSectionId];
  final currentIndex = current?.index ?? fallbackIndex;
  SaltCatalogSectionInfo? previous;
  SaltCatalogSectionInfo? next;
  if (currentIndex != null) {
    for (final section in sections) {
      if (section.index < currentIndex) previous = section;
      if (section.index > currentIndex) {
        next = section;
        break;
      }
    }
  }
  return SaltCatalogNavigation(
    sections: List.unmodifiable(sections),
    total: total,
    currentIndex: currentIndex,
    previous: previous,
    next: next,
  );
}

/// Parses the dedicated SIP annotation response and also accepts the same
/// `public_notes` object when it is embedded in a manuscript envelope.
List<SaltParagraphAnnotation> saltParagraphAnnotationsOf(Object? value) {
  final root = stringMap(value);
  if (root == null) return const [];
  final data = stringMap(root['data']);
  final sum = stringMap(root['manuscript_sum']);
  final dataSum = stringMap(data?['manuscript_sum']);
  final publicNotes =
      stringMap(root['public_notes']) ??
      stringMap(data?['public_notes']) ??
      stringMap(sum?['public_notes']) ??
      stringMap(dataSum?['public_notes']);
  final rawNotes = publicNotes?['doc_section_list'];
  if (rawNotes is! List) return const [];

  final result = <SaltParagraphAnnotation>[];
  for (final value in rawNotes) {
    final note = stringMap(value);
    final paragraphIndex = jsonInt(note?['paragraph_index']);
    final commentId = plainText(note?['doc_section_id']);
    final commentCount = jsonInt(note?['comment_count']) ?? 0;
    if (paragraphIndex == null ||
        paragraphIndex < 0 ||
        !RegExp(r'^\d+$').hasMatch(commentId) ||
        commentCount <= 0) {
      continue;
    }
    result.add(
      SaltParagraphAnnotation(
        paragraphIndex: paragraphIndex,
        commentId: commentId,
        commentCount: commentCount,
        hasOwnComment: note?['has_not_empty_comment'] == true,
      ),
    );
  }
  result.sort(
    (left, right) => left.paragraphIndex.compareTo(right.paragraphIndex),
  );
  return List.unmodifiable(result);
}

class SaltArticleCodeEnvelope {
  const SaltArticleCodeEnvelope({
    required this.random,
    required this.articleCode,
    required this.log,
  });

  factory SaltArticleCodeEnvelope.fromResponseJson(Object? value) {
    final root = stringMap(value) ?? const <String, dynamic>{};
    final data = stringMap(root['data']);
    final dataCode = stringMap(data?['code']);
    final rootCode = stringMap(root['code']);
    return SaltArticleCodeEnvelope.fromJson(
      dataCode ?? rootCode ?? const <String, dynamic>{},
    );
  }

  factory SaltArticleCodeEnvelope.fromJson(Object? value) {
    final object = stringMap(value) ?? const <String, dynamic>{};
    return SaltArticleCodeEnvelope(
      // `random` is populated locally by the official request chain after the
      // `/article/code` response: it assigns the raw request `tk` to
      // `CodeResult.random` before invoking the reader. The endpoint itself
      // normally serializes only `article_code` and `log`; still preserve this
      // field when decoding an already-hydrated client-side model.
      random: object['random'] is String ? object['random'] as String : '',
      articleCode: object['article_code'] is String
          ? object['article_code'] as String
          : '',
      // `log` is an opaque strategy selector, not display copy. In live
      // responses it may contain whitespace; normalizing or trimming it
      // changes its byte length and therefore selects the wrong native key
      // derivation branch.
      log: object['log'] is String ? object['log'] as String : '',
    );
  }

  final String random;
  final String articleCode;
  final String log;
}

class SaltChapterFetchStatus {
  const SaltChapterFetchStatus({
    required this.hasMetadata,
    required this.hasBoundPayload,
    required this.hasReadableContent,
    required this.requiresNativeRenderer,
    required this.isAuthorized,
    required this.isLocked,
    required this.hasDecodeError,
    required this.scriptType,
    required this.scriptChars,
    required this.articleCodeChars,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  factory SaltChapterFetchStatus.fromJson(
    Object? value, {
    String? decodedContent,
    String? decodeError,
    SaltArticleCodeEnvelope? codeEnvelope,
  }) {
    final manuscript = SaltManuscriptEnvelope.fromJson(value);
    final responseCode =
        codeEnvelope ?? SaltArticleCodeEnvelope.fromResponseJson(value);
    final articleCodeChars = responseCode.articleCode.isNotEmpty
        ? responseCode.articleCode.length
        : manuscript.articleCode.length;
    final fallbackHtml = htmlContent(value);
    final hasReadableContent =
        decodedContent?.trim().isNotEmpty == true ||
        manuscript.directHtml?.trim().isNotEmpty == true ||
        fallbackHtml?.trim().isNotEmpty == true;
    final hasBoundPayload = manuscript.hasScript && articleCodeChars > 0;
    final hasMetadata =
        manuscript.title.isNotEmpty ||
        manuscript.parentTitle.isNotEmpty ||
        manuscript.authorName.isNotEmpty ||
        manuscript.authenticationResult != null ||
        manuscript.isLocked != null ||
        manuscript.sectionIndex != null;
    final isAuthorized = manuscript.authenticationResult == true;
    final isLocked = manuscript.isLocked == true;
    final hasDecodeError = decodeError?.trim().isNotEmpty == true;
    final requiresNativeRenderer =
        manuscript.requiresNativeRenderer && hasBoundPayload;

    late final String primaryLabel;
    late final String secondaryLabel;
    if (hasReadableContent) {
      primaryLabel = '章节正文已加载';
      secondaryLabel = '当前响应包含可直接展示的章节内容。';
    } else if (requiresNativeRenderer) {
      primaryLabel = '章节载荷已获取';
      secondaryLabel = '账号权益与请求绑定通过，正在等待正文解析。';
    } else if (hasBoundPayload) {
      primaryLabel = '章节载荷已获取';
      secondaryLabel = '已取得脚本与文章密钥绑定信息。';
    } else if (isLocked || manuscript.authenticationResult == false) {
      primaryLabel = '章节未解锁';
      secondaryLabel = '当前账号暂无该章节阅读权限。';
    } else if (hasDecodeError) {
      primaryLabel = '章节解析失败';
      secondaryLabel = decodeError!.trim();
    } else if (hasMetadata) {
      primaryLabel = '章节信息已获取';
      secondaryLabel = '当前响应只包含章节资料，未包含正文载荷。';
    } else {
      primaryLabel = '章节暂不可用';
      secondaryLabel = '当前响应没有可展示的章节资料或正文载荷。';
    }

    return SaltChapterFetchStatus(
      hasMetadata: hasMetadata,
      hasBoundPayload: hasBoundPayload,
      hasReadableContent: hasReadableContent,
      requiresNativeRenderer: requiresNativeRenderer,
      isAuthorized: isAuthorized,
      isLocked: isLocked,
      hasDecodeError: hasDecodeError,
      scriptType: manuscript.scriptType,
      scriptChars: manuscript.script?.length ?? 0,
      articleCodeChars: articleCodeChars,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
    );
  }

  final bool hasMetadata;
  final bool hasBoundPayload;
  final bool hasReadableContent;
  final bool requiresNativeRenderer;
  final bool isAuthorized;
  final bool isLocked;
  final bool hasDecodeError;
  final int? scriptType;
  final int scriptChars;
  final int articleCodeChars;
  final String primaryLabel;
  final String secondaryLabel;

  bool get fetched =>
      hasReadableContent || hasBoundPayload || hasMetadata || isAuthorized;
}
