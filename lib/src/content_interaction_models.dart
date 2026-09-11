/// Shared interaction models for content rendering and comment actions.
///
/// The native client keeps the identity of a rendered paragraph/comment node
/// separate from the text currently visible on screen.  Text is presentation
/// data and may change after HTML/emoji decoding; node IDs and selection
/// ranges are what make comment, link and media actions stable.
enum ContentNodeKind { text, image, link, sticker, video }

class ContentNode {
  const ContentNode({
    required this.id,
    required this.kind,
    this.text = '',
    this.url = '',
    this.title = '',
    this.startOffset = 0,
    this.endOffset = 0,
  });

  const ContentNode.text(
    String value, {
    String id = '',
    int startOffset = 0,
    int endOffset = 0,
  }) : this(
         id: id,
         kind: ContentNodeKind.text,
         text: value,
         startOffset: startOffset,
         endOffset: endOffset,
       );

  const ContentNode.image(String value, {String id = '', String title = ''})
    : this(id: id, kind: ContentNodeKind.image, url: value, title: title);

  const ContentNode.link(
    String value, {
    required String url,
    String id = '',
    String title = '',
    int startOffset = 0,
    int endOffset = 0,
  }) : this(
         id: id,
         kind: ContentNodeKind.link,
         text: value,
         url: url,
         title: title,
         startOffset: startOffset,
         endOffset: endOffset,
       );

  const ContentNode.sticker(
    String value, {
    required String url,
    String id = '',
    String title = '',
  }) : this(
         id: id,
         kind: ContentNodeKind.sticker,
         text: value,
         url: url,
         title: title,
       );

  const ContentNode.video(String value, {String id = '', String title = ''})
    : this(id: id, kind: ContentNodeKind.video, url: value, title: title);

  final String id;
  final ContentNodeKind kind;
  final String text;
  final String url;
  final String title;
  final int startOffset;
  final int endOffset;

  bool get isText => kind == ContentNodeKind.text;
  bool get isImage => kind == ContentNodeKind.image;
  bool get isLink => kind == ContentNodeKind.link;
  bool get isSticker => kind == ContentNodeKind.sticker;
  bool get isVideo => kind == ContentNodeKind.video;

  String get displayText => text.isNotEmpty ? text : title;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    if (text.isNotEmpty) 'text': text,
    if (url.isNotEmpty) 'url': url,
    if (title.isNotEmpty) 'title': title,
    if (startOffset > 0) 'start_offset': startOffset,
    if (endOffset > 0) 'end_offset': endOffset,
  };
}

/// The stable identity of a selection in an answer/article body.
///
/// Offsets are UTF-16 offsets, matching Flutter's [TextSelection] and
/// Zhihu's `SentenceReaction.ReactionPosition` contract.
class ContentSelectionContext {
  const ContentSelectionContext({
    this.contentType = '',
    this.contentId = '',
    this.nodeId = '',
    this.paragraphId = '',
    this.segmentIds = const <String>[],
    this.source = 'content',
  });

  final String contentType;
  final String contentId;
  final String nodeId;
  final String paragraphId;
  final List<String> segmentIds;
  final String source;

  ContentSelectionContext withSegmentIds(Iterable<String> values) {
    final ids = <String>[];
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty && !ids.contains(normalized)) {
        ids.add(normalized);
      }
    }
    return ContentSelectionContext(
      contentType: contentType,
      contentId: contentId,
      nodeId: nodeId,
      paragraphId: paragraphId,
      segmentIds: List.unmodifiable(ids),
      source: source,
    );
  }

  ContentSelection create({
    required String quote,
    required int startOffset,
    required int endOffset,
  }) => ContentSelection(
    contentType: contentType,
    contentId: contentId,
    nodeId: nodeId,
    paragraphId: paragraphId,
    segmentIds: segmentIds,
    quote: quote,
    startOffset: startOffset,
    endOffset: endOffset,
    source: source,
  );
}

class ContentSelection {
  const ContentSelection({
    required this.quote,
    required this.startOffset,
    required this.endOffset,
    this.contentType = '',
    this.contentId = '',
    this.nodeId = '',
    this.paragraphId = '',
    this.segmentIds = const <String>[],
    this.source = 'content',
  });

  final String quote;
  final int startOffset;
  final int endOffset;
  final String contentType;
  final String contentId;
  final String nodeId;
  final String paragraphId;
  final List<String> segmentIds;
  final String source;

  bool get isValid =>
      quote.trim().isNotEmpty && startOffset >= 0 && endOffset > startOffset;

  bool get hasSegmentTarget =>
      segmentIds.isNotEmpty && paragraphId.trim().isNotEmpty;

  String get segmentId => segmentIds.join(',');

  String get normalizedQuote => quote.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Payload matching the official `SentenceParams` JSON model:
  /// `segment_id`, `content`, and a paragraph-relative start/end position.
  Map<String, Object?> toSegmentJson() => {
    'segment_id': segmentId,
    'content': quote,
    'position': {
      'start': {'offset': startOffset, 'paragraph_id': paragraphId},
      'end': {'offset': endOffset, 'paragraph_id': paragraphId},
    },
  };

  Map<String, Object?> toJson() => {
    'content_type': contentType,
    'content_id': contentId,
    'node_id': nodeId,
    'paragraph_id': paragraphId,
    'segment_ids': segmentIds,
    'quote': quote,
    'start_offset': startOffset,
    'end_offset': endOffset,
    'source': source,
  };
}

/// Explicit reply target copied from the native comment editor's state.
/// Keeping root and target IDs separate prevents replying to a child comment
/// from accidentally creating a new root comment after a list refresh.
class CommentReplyTarget {
  const CommentReplyTarget({
    required this.contentType,
    required this.contentId,
    this.rootCommentId = '',
    this.replyCommentId = '',
    this.targetUserId = '',
    this.targetUserName = '',
    this.source = 'comment',
  });

  final String contentType;
  final String contentId;
  final String rootCommentId;
  final String replyCommentId;
  final String targetUserId;
  final String targetUserName;
  final String source;

  bool get isReply => replyCommentId.trim().isNotEmpty;

  String get hint => isReply && targetUserName.trim().isNotEmpty
      ? '回复 @${targetUserName.trim()}'
      : isReply
      ? '回复这条评论'
      : '理性发言，友善互动';

  Map<String, Object?> toJson() => {
    'content_type': contentType,
    'content_id': contentId,
    'root_comment_id': rootCommentId,
    'reply_comment_id': replyCommentId,
    'target_user_id': targetUserId,
    'target_user_name': targetUserName,
    'source': source,
  };
}

String contentNodeIdOf(Map<String, dynamic> value, int fallbackIndex) {
  for (final key in const [
    'paragraph_id',
    'paragraphId',
    'paragraphID',
    'pid',
    'segment_id',
    'segmentId',
    'block_id',
    'blockId',
    'uuid',
    'id',
  ]) {
    final candidate = value[key]?.toString().trim() ?? '';
    if (candidate.isNotEmpty) return candidate;
  }
  for (final key in const ['paragraph', 'heading', 'blockquote', 'quote']) {
    final nested = value[key];
    if (nested is! Map) continue;
    final map = nested.map((key, item) => MapEntry(key.toString(), item));
    for (final alias in const [
      'paragraph_id',
      'paragraphId',
      'paragraphID',
      'pid',
      'id',
      'uuid',
    ]) {
      final candidate = map[alias]?.toString().trim() ?? '';
      if (candidate.isNotEmpty) return candidate;
    }
  }
  return 'content-node-$fallbackIndex';
}

String contentParagraphIdOf(Map<String, dynamic> value) {
  for (final key in const [
    'paragraph_id',
    'paragraphId',
    'paragraphIdValue',
    'paragraphID',
    'pid',
  ]) {
    final candidate = value[key]?.toString().trim() ?? '';
    if (candidate.isNotEmpty) return candidate;
  }
  final node = value['paragraph'] ?? value['heading'] ?? value['blockquote'];
  if (node is Map) {
    final map = node.map((key, item) => MapEntry(key.toString(), item));
    for (final key in const [
      'paragraph_id',
      'paragraphId',
      'paragraphID',
      'pid',
      'id',
    ]) {
      final candidate = map[key]?.toString().trim() ?? '';
      if (candidate.isNotEmpty) return candidate;
    }
  }
  for (final key in const ['id', 'uuid']) {
    final candidate = value[key]?.toString().trim() ?? '';
    if (candidate.isNotEmpty) return candidate;
  }
  return '';
}
