import 'content_helpers.dart';
import 'rich_and_feed.dart';
import 'unwrap_and_component.dart';

// ordinary library module

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(plainText(value));
}

String titleOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final key in const [
    'title',
    'name',
    'excerpt_title',
    'headline',
    'display_query',
    'query_correction',
    'real_query',
    'query',
  ]) {
    final raw = object[key];
    final map = stringMap(raw);
    final text = plainText(
      map?['plain_text'] ?? map?['text'] ?? map?['name'] ?? raw,
    );
    if (text.isNotEmpty) return text;
  }
  final question = object['question'];
  if (question is Map<String, dynamic>) {
    final text = plainText(question['title']);
    if (text.isNotEmpty) return text;
  }
  final author = object['author'];
  if (author is Map<String, dynamic>) {
    final text = plainText(author['name']);
    if (text.isNotEmpty) return text;
  }
  final type = typeOf(source);
  final id = idOf(source);
  return [if (type.isNotEmpty) type, if (id.isNotEmpty) '#$id'].join(' ');
}

String subtitleOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final key in const [
    'excerpt',
    'description',
    'content',
    'headline',
    'reason',
  ]) {
    final text = plainText(object[key]);
    if (text.isNotEmpty) {
      return text.length > 180 ? '${text.substring(0, 180)}…' : text;
    }
  }
  return '';
}

String authorNameOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  final author = stringMap(object['author']);
  if (author == null) return '';
  for (final key in const ['name', 'user_name', 'userName', 'nickname']) {
    final text = plainText(author[key]);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String authorHeadlineOf(Map<String, dynamic> source) {
  final author = stringMap(unwrapObject(source)['author']);
  if (author == null) return '';
  for (final key in const ['headline', 'description', 'bio']) {
    final text = plainText(author[key]);
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> authorBadgeLabelsOf(Map<String, dynamic> source) {
  final author = stringMap(unwrapObject(source)['author']);
  if (author == null) return const [];
  final labels = <String>[];

  void add(Object? value) {
    if (labels.length >= 3 || value == null) return;
    if (value is List) {
      for (final item in value) {
        add(item);
        if (labels.length >= 3) break;
      }
      return;
    }
    final map = stringMap(value);
    if (map != null) {
      for (final key in const ['title', 'name', 'description', 'text']) {
        final label = plainText(map[key]);
        if (label.isNotEmpty && !labels.contains(label)) {
          labels.add(label);
          return;
        }
      }
      add(map['detail_badges']);
      add(map['merged_badges']);
      return;
    }
    final label = plainText(value);
    if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
  }

  add(author['badge_v2']);
  add(author['badge']);
  add(author['badges']);
  return List.unmodifiable(labels);
}

class AnswerRelationship {
  const AnswerRelationship({
    required this.voting,
    required this.isThanked,
    required this.isFavorited,
    required this.isAuthor,
    required this.isFollowingAuthor,
  });

  factory AnswerRelationship.from(Map<String, dynamic> source) {
    final candidates = _contentStateCandidates(source);

    Object? firstValue(Iterable<String> keys) {
      for (final object in candidates) {
        final relationship = stringMap(object['relationship']) ?? const {};
        final reaction = stringMap(object['reaction']) ?? const {};
        final reactionRelation =
            stringMap(reaction['relation']) ??
            stringMap(reaction['relationship']) ??
            const {};
        for (final key in keys) {
          for (final map in [object, relationship, reactionRelation]) {
            if (map.containsKey(key) && map[key] != null) return map[key];
          }
        }
      }
      return null;
    }

    bool? firstBool(Iterable<String> keys) {
      final value = firstValue(keys);
      return value is bool ? value : null;
    }

    final rawVoting = plainText(firstValue(const ['voting', 'vote']));
    final isLiked =
        firstBool(const [
          'is_like',
          'is_liked',
          'liked',
          'like',
          'has_voteup',
        ]) ==
        true;
    bool? followingAuthor;
    for (final object in candidates) {
      final value = stringMap(object['author'])?['is_following'];
      if (value is bool) {
        followingAuthor = value;
        break;
      }
    }
    return AnswerRelationship(
      voting: rawVoting.isEmpty && isLiked ? 'up' : rawVoting,
      isThanked: firstBool(const ['is_thanked']),
      isFavorited: firstBool(const ['is_favorited', 'is_collected']),
      isAuthor: firstBool(const ['is_author']),
      isFollowingAuthor: followingAuthor ?? firstBool(const ['is_following']),
    );
  }

  final String voting;
  final bool? isThanked;
  final bool? isFavorited;
  final bool? isAuthor;
  final bool? isFollowingAuthor;

  bool get isUpvoted =>
      const {'up', 'upvote', '1'}.contains(voting.trim().toLowerCase());

  bool get isDownvoted =>
      const {'down', 'downvote', '-1'}.contains(voting.trim().toLowerCase());

  bool get hasState =>
      voting.isNotEmpty ||
      isThanked == true ||
      isFavorited == true ||
      isAuthor == true ||
      isFollowingAuthor == true;
}

String authorAvatarOf(Map<String, dynamic> source) {
  final author = stringMap(unwrapObject(source)['author']);
  if (author == null) return '';
  for (final key in const [
    'avatar_url',
    'avatarUrl',
    'avatar',
    'avatar_url_template',
  ]) {
    var value = author[key]?.toString() ?? '';
    if (value.contains('{size}')) value = value.replaceAll('{size}', 's');
    if (Uri.tryParse(value)?.scheme == 'https') return value;
  }
  return '';
}

String authorIdOf(Map<String, dynamic> source) {
  final author = stringMap(unwrapObject(source)['author']);
  if (author == null) return '';
  for (final key in const [
    'url_token',
    'urlToken',
    'member_id',
    'memberId',
    'uid',
    'id',
  ]) {
    final value = plainText(author[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Returns the stable member identifier used by relationship routes.
///
/// Search/profile/comment payloads are not consistent about whether the
/// canonical value is called `id`, `member_id`, `uid`, or `url_token`.
/// Relationship write endpoints follow the native Android contract and
/// expect the member object's canonical `id`; `url_token` is the public
/// profile route token and must not be preferred for
/// `/people/{id}/followers` (the server returns 404, which the UI used to
/// mislabel as “内容已被删除”).
String personMemberIdOf(Object? value, [String fallback = '']) {
  final person = stringMap(value);
  if (person != null) {
    String direct(Map<String, dynamic> candidate) {
      for (final key in const [
        'id',
        'member_id',
        'memberId',
        'uid',
        'url_token',
        'urlToken',
      ]) {
        final identity = plainText(candidate[key]);
        if (identity.isNotEmpty) return identity;
      }
      return '';
    }

    final directIdentity = direct(person);
    if (directIdentity.isNotEmpty) return directIdentity;
    // Relationship rows can wrap the person in `author`, `member`, or
    // `user`. Inspect only these identity-bearing aliases so a surrounding
    // content/question id is never mistaken for the member id.
    for (final key in const [
      'person',
      'author',
      'member',
      'user',
      'creator',
      'owner',
    ]) {
      final nested = stringMap(person[key]);
      if (nested == null) continue;
      final identity = direct(nested);
      if (identity.isNotEmpty) return identity;
    }
  }
  return fallback.trim();
}

/// Returns every stable identifier exposed for a member instead of choosing a
/// single alias. Comment payloads do not consistently use the same one of
/// `id` and `url_token` as their parent content payload.
Set<String> personIdentityKeys(Object? value) {
  final person = stringMap(value);
  if (person == null) return const <String>{};
  final keys = <String>{};
  for (final key in const [
    'id',
    'url_token',
    'urlToken',
    'uid',
    'member_id',
    'memberId',
  ]) {
    final identity = plainText(person[key]);
    if (identity.isNotEmpty) keys.add(identity);
  }
  return Set.unmodifiable(keys);
}

String commentContentOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final key in const ['content', 'text', 'excerpt', 'description']) {
    final raw = object[key];
    // Media comments are represented by anchors whose inner text is only a
    // fallback label (`[图片]`, `[表情]`, ...). Once the media is rendered
    // natively, repeating that label as comment text is noisy and unlike the
    // intended content.
    final displayValue = raw is String
        ? raw.replaceAll(
            RegExp(
              r'''<a\b(?=[^>]*\bclass=["'][^"']*\bcomment_(?:sticker|img|image|gif|inline_image)\b[^"']*["'])[^>]*>[\s\S]*?</a>''',
              caseSensitive: false,
            ),
            '',
          )
        : raw;
    final text = plainText(displayValue);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// Returns the original comment markup when the endpoint provides it.  The
/// compact [commentContentOf] helper intentionally strips HTML for metrics and
/// accessibility, but link spans and sticker anchors need the raw value so the
/// renderer can preserve their native target and display title.
String commentRawContentOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final key in const ['content', 'text', 'excerpt', 'description']) {
    final raw = object[key];
    if (raw is String && raw.trim().isNotEmpty) return raw;
  }
  return '';
}

String commentReplyTargetNameOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  final candidates = <Object?>[
    object['reply_to_author'],
    object['reply_author'],
    object['reply_to'],
    stringMap(object['replied_comment'])?['author'],
  ];
  for (final value in candidates) {
    final author = stringMap(value);
    if (author == null) continue;
    for (final key in const ['name', 'user_name', 'nickname']) {
      final text = plainText(author[key]);
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

int? _countValue(Object? value) {
  if (value is num) return value.round();
  final text = plainText(value).replaceAll(',', '');
  final match = RegExp(
    r'(\d+(?:\.\d+)?)\s*([\u4e07\u5343kK]?)',
  ).firstMatch(text);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return null;
  final multiplier = switch (match.group(2)) {
    '万' => 10000,
    '千' || 'k' || 'K' => 1000,
    _ => 1,
  };
  return (number * multiplier).round();
}

int? _metricFrom(Map<String, dynamic> source, Iterable<String> aliases) {
  final nested = <Map<String, dynamic>>[
    source,
    ?stringMap(source['statistics']),
    ?stringMap(source['counts']),
    ?stringMap(source['relate']),
    ?stringMap(source['reaction']),
    ?stringMap(stringMap(source['reaction'])?['statistics']),
  ];
  for (final map in nested) {
    for (final key in aliases) {
      final count = _countValue(map[key]);
      if (count != null) return count;
    }
  }
  return null;
}

class ContentMetrics {
  const ContentMetrics({
    this.voteupCount,
    this.favoriteCount,
    this.commentCount,
    this.thanksCount,
    this.viewCount,
    this.createdTime,
    this.updatedTime,
    this.answerCount,
    this.followerCount,
    this.authorFollowerCount,
    this.replyCount,
    this.followingCount,
    this.articleCount,
    this.itemCount,
  });

  factory ContentMetrics.from(Map<String, dynamic> source) {
    final candidates = _contentStateCandidates(source);

    Map<String, dynamic> nested(String key) {
      for (final candidate in candidates) {
        final value = stringMap(candidate[key]);
        if (value != null) return value;
      }
      return const {};
    }

    int? metric(Iterable<String> aliases) {
      for (final candidate in candidates) {
        final value = _metricFrom(candidate, aliases);
        if (value != null) return value;
      }
      return null;
    }

    final question = nested('question');
    final author = nested('author');
    return ContentMetrics(
      voteupCount: metric(const [
        'voteup_count',
        'vote_up_count',
        'up_vote_count',
        'upvote_count',
        'like_count',
        'liked_count',
      ]),
      favoriteCount: metric(const [
        'favorite_count',
        'favlists_count',
        'collect_count',
        'collection_count',
        'bookmark_count',
      ]),
      commentCount: metric(const ['comment_count', 'comments_count']),
      thanksCount: metric(const ['thanks_count', 'thank_count']),
      viewCount: metric(const [
        'visited_count',
        'visit_count',
        'read_count',
        'view_count',
        'play_count',
      ]),
      createdTime: metric(const [
        'created_time',
        'created_at',
        'publish_time',
        'publish_timestamp',
        'published_at',
      ]),
      updatedTime: metric(const [
        'updated_time',
        'updated_at',
        'edit_time',
        'edit_timestamp',
        'modified_at',
      ]),
      answerCount:
          _metricFrom(question, const ['answer_count', 'answers_count']) ??
          metric(const ['answer_count', 'answers_count']),
      followerCount:
          _metricFrom(question, const ['follower_count', 'followers_count']) ??
          metric(const ['follower_count', 'followers_count']),
      authorFollowerCount: _metricFrom(author, const [
        'followers_count',
        'follower_count',
      ]),
      replyCount: metric(const [
        'child_comment_count',
        'reply_count',
        'replies_count',
      ]),
      followingCount: metric(const ['following_count', 'followees_count']),
      articleCount: metric(const ['articles_count', 'article_count']),
      itemCount: metric(const ['item_count', 'items_count', 'content_count']),
    );
  }

  final int? voteupCount;
  final int? favoriteCount;
  final int? commentCount;
  final int? thanksCount;
  final int? viewCount;
  final int? createdTime;
  final int? updatedTime;
  final int? answerCount;
  final int? followerCount;
  final int? authorFollowerCount;
  final int? replyCount;
  final int? followingCount;
  final int? articleCount;
  final int? itemCount;

  bool get hasEngagement =>
      voteupCount != null ||
      favoriteCount != null ||
      commentCount != null ||
      replyCount != null;

  bool get hasObjectSummary =>
      answerCount != null ||
      followerCount != null ||
      followingCount != null ||
      articleCount != null ||
      itemCount != null;
}

List<Map<String, dynamic>> _contentStateCandidates(
  Map<String, dynamic> source,
) {
  final semantic = <Map<String, dynamic>>[];
  final fallback = <Map<String, dynamic>>[];
  final visited = <int>{};

  bool isInteractive(Map<String, dynamic> value) {
    final marker = plainText(
      value['content_type'] ??
          value['target_type'] ??
          value['object_type'] ??
          value['resource_type'] ??
          value['type'],
    ).toLowerCase();
    return marker.contains('answer') ||
        marker.contains('article') ||
        marker.contains('pin') ||
        marker.contains('moment');
  }

  void collect(Object? value, int depth) {
    if (depth > 5 || value is! Map) return;
    final identity = identityHashCode(value);
    if (!visited.add(identity)) return;
    final map = stringMap(value)!;
    (isInteractive(map) ? semantic : fallback).add(map);
    for (final key in const ['target', 'object', 'data', 'content']) {
      collect(map[key], depth + 1);
    }
  }

  collect(source, 0);
  final normalized = unwrapObject(source);
  (isInteractive(normalized) ? semantic : fallback).add(normalized);
  return [...semantic, ...fallback];
}

String compactCount(int value) {
  if (value >= 100000000) {
    final text = (value / 100000000).toStringAsFixed(1).replaceAll('.0', '');
    return '$text亿';
  }
  if (value >= 10000) {
    final text = (value / 10000).toStringAsFixed(1).replaceAll('.0', '');
    return '$text万';
  }
  return value.toString();
}

String contentDateLabel(ContentMetrics metrics) {
  String date(int timestamp) {
    final milliseconds = timestamp > 100000000000
        ? timestamp
        : timestamp * 1000;
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  // Search and SDUI containers sometimes encode an absent timestamp as zero.
  // Treat it as absent rather than rendering a misleading 1970-01-01 date.
  final rawCreated = metrics.createdTime;
  final rawUpdated = metrics.updatedTime;
  final created = rawCreated != null && rawCreated > 0 ? rawCreated : null;
  final updated = rawUpdated != null && rawUpdated > 0 ? rawUpdated : null;
  if (created == null && updated == null) return '';
  if (created == null) return '更新于 ${date(updated!)}';
  if (updated == null || date(created) == date(updated)) {
    return '发布于 ${date(created)}';
  }
  return '发布于 ${date(created)} · 编辑于 ${date(updated)}';
}
