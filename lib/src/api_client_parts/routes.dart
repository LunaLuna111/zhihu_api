import 'dart:async';

import '../api_client.dart';

extension ZhihuApiClientRoutes on ZhihuApiClient {
  /// Write operations are deliberately unavailable to an anonymous guest.
  /// A session imported by the user is accepted alongside a session created
  /// by the in-app login flow; both still need a complete Bearer/UDID context.
  bool get canWrite =>
      session.hasCompleteMobileContext &&
      (session.sessionKind == 'account' ||
          session.sessionKind == 'imported' ||
          session.sessionKind == 'qr') &&
      !(session.sessionKind == 'account' && session.isAccessTokenExpired);

  Map<String, String> get baseHeaders => {
    'accept': 'application/json',
    'user-agent': ZhihuApiClient.appUserAgent,
    'x-api-version': MobileLoginContract.apiVersion,
    'x-app-version': '11.4.0',
    'x-app-build': 'release',
    'x-app-bundleid': 'com.zhihu.android',
    'x-app-flavor': 'zhihuwap64',
    'x-network-type': 'WIFI',
    // The official client creates a fresh lowercase 128-bit trace ID for
    // normal API calls. It is request telemetry, not a persisted device ID.
    'x-b3-traceid': ZhihuApiClient.randomHex(32),
    'X-Zse-93': MobileLoginContract.encryptVersion,
  };

  /// Headers fixed by each route's transport profile. Keeping these rules
  /// here also preserves them when a generic list follows a server-provided
  /// `paging.next` URL.
  Map<String, String> officialRouteHeaders(Uri uri) {
    if (uri.host != ZhihuApiClient.apiHost) return const {};
    final path = uri.path;
    if (path == '/topstory/recommend') {
      return const {
        'x-api-version': '3.1.8',
        'x-close-recommend': '0',
        'x-ad-styles': '',
        'x-feed-prefetch': '0',
      };
    }
    if (path == '/topstory/hot-lists/total') {
      return const {
        'x-api-version': '3.1.8',
        'x-ad-styles': '',
        'isPreload': 'false',
      };
    }
    if (path == '/search_v3') {
      // The current search protocol sends 3.0.91 for this route.
      return const {'x-api-version': '3.0.91'};
    }
    if (RegExp(r'^/(?:v4/)?questions/\d+/(?:feeds|answers)$').hasMatch(path)) {
      return const {'x-api-version': '3.0.89', 'x-ad-styles': ''};
    }
    if (RegExp(r'^/people/[^/]+/following_collections$').hasMatch(path)) {
      return const {'x-api-version': '3.0.94'};
    }
    if (RegExp(r'^/v4/answers/\d+$').hasMatch(path)) {
      return const {'x-api-version': '3.0.89'};
    }
    if (path == '/moments_v3') {
      // X-Moments-Ab-Param is intentionally conditional: the official App
      // supplies an active experiment value, not a universal fixed string.
      return const {'x-api-version': '3.0.93', 'need_debug': '0'};
    }
    return const {};
  }

  Uri apiUri(String path, {Map<String, Object?> query = const {}}) {
    return uriForHost(ZhihuApiClient.apiHost, path, query: query);
  }

  /// Follow feed exposed as `GET /moments_v3?feed_type=...`. The client supplies
  /// its experiment value through `X-Moments-Ab-Param`; the route itself is
  /// account-scoped, so a guest rejection is surfaced without relabeling it
  /// as a network failure.
  Uri followingFeedInitialUri({String feedType = 'all'}) {
    final normalized = feedType.trim();
    // The current FollowSubFragment sends the visible module name as the
    // `feed_type` value (精选/最新/想法). Keep the legacy ASCII values
    // accepted as well because older cached paging links still use `all`.
    if (!RegExp(r'^[A-Za-z0-9_\-\u3400-\u9fff]{1,32}$').hasMatch(normalized)) {
      throw const ApiTransportException('关注流 feed_type 无效');
    }
    return apiUri('/moments_v3', query: {'feed_type': normalized});
  }

  /// The official Follow tab loads its horizontal “most visited / special
  /// attention” avatar rail independently from the feed pages.
  ///
  /// This is `/moments/recent?type=raw`, not the public recommendation
  /// endpoint. Its `data` entries contain an `actor` object plus unread and
  /// target metadata, which is what the native `MostVisitView` renders.
  Uri followingMostVisitedInitialUri() =>
      apiUri('/moments/recent', query: const {'type': 'raw'});

  /// The small avatar rail shown above the official following feed. It is a
  /// separate request from `/moments_v3`; keeping it independent means a
  /// slow recommendation response cannot block the feed itself.
  Uri followingPeopleRecommendationsUri({
    String recType = 'follow_tab',
    String itemId = '',
  }) {
    final normalizedType = recType.trim();
    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(normalizedType)) {
      throw const ApiTransportException('关注用户推荐类型无效');
    }
    final query = <String>['rec_type=${Uri.encodeComponent(normalizedType)}'];
    if (itemId.trim().isNotEmpty) {
      final normalizedId = itemId.trim();
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(normalizedId)) {
        throw const ApiTransportException('关注用户推荐 item_id 无效');
      }
      query.add('item_id=${Uri.encodeComponent(normalizedId)}');
    }
    return Uri.parse(
      'https://${ZhihuApiClient.publicWebHost}/api/v4/moments/recommend_follow_people?${query.join('&')}',
    );
  }

  /// Recent activity opened from an avatar in the following-user rail. The
  /// route is intentionally kept separate from a profile tab so the tap lands
  /// directly on the same recent-content list used by the official client.
  Uri userRecentActivitiesInitialUri(
    String memberId, {
    String type = 'people',
  }) {
    final normalizedType = type.trim();
    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(normalizedType)) {
      throw const ApiTransportException('最近动态类型无效');
    }
    final id = userIdentifier(memberId);
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/moments/recent/$normalizedType/$id/activities',
    );
  }

  /// Initial query tuple for the rank feed. The values are `limit=10`,
  /// `is_browse_model=0`, and `new_hot_list=false`; this is not `/hot/topics`.
  Uri hotListInitialUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/topstory/hot-lists/total'
    '?limit=10&is_browse_model=0&new_hot_list=false',
  );

  /// Full current home recommendation request.
  /// This is distinct from its parameter-free bootstrap service. Empty values
  /// and query order are retained because the complete target is X-Zse signed.
  Uri recommendationFeedInitialUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/topstory/recommend'
    '?tsp_ad_cardredesign=0&feed_card_exp=card_corner|1&v_serial=1'
    '&isDoubleFlow=0&action=down&refresh_scene=0&scroll=&limit=10'
    '&start_type=cold&device=android&short_container_setting_value=0'
    '&include_guide_relation=false&interest_tags=&is_feed_first_request=1',
  );

  /// Initial AnswerListV2 target for a question.
  /// Keep the include commas unescaped: X-Zse signs OkHttp's encoded target,
  /// so an equivalent but re-encoded query would no longer be byte-identical.
  Uri questionFeedsInitialUri(String questionId, {String order = 'default'}) {
    final normalized = questionId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const ApiTransportException('问题 ID 必须是数字');
    }
    final normalizedOrder = order.trim().toLowerCase() == 'latest'
        ? 'created'
        : 'default';
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/questions/$normalized/feeds?include='
      '${ZhihuApiClient.questionFeedsInitialInclude}&order=$normalizedOrder&show_detail=1',
    );
  }

  /// Full question metadata used by the answer-list header. Keep this request
  /// independent from the answer feed so a compact embedded `question` object
  /// cannot permanently hide the prompt body or its media.
  Uri questionDetailUri(String questionId) {
    final normalized = questionId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const ApiTransportException('问题 ID 必须是数字');
    }
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/questions/$normalized'
      '?include=detail,description,topics,author,answer_count,comment_count,'
      'follower_count,read_count,query_info,voteup_count,voting,can_vote',
    );
  }

  /// Original 11.4.0 non-AnswerListV2 route. Unlike the personalized feeds
  /// endpoint, this answer collection is suitable for a signed-out reader.
  Uri anonymousQuestionAnswersInitialUri(
    String questionId, {
    String sortBy = 'default',
  }) {
    final normalized = questionId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const ApiTransportException('问题 ID 必须是数字');
    }
    final normalizedSort = sortBy.trim().toLowerCase() == 'latest'
        ? 'created'
        : 'default';
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/v4/questions/$normalized/answers'
      '?sort_by=$normalizedSort&show_detail=1',
    );
  }

  Uri questionAnswersInitialUri(String questionId, {String order = 'default'}) {
    final signedIn =
        session.hasCompleteMobileContext &&
        (session.sessionKind == 'account' ||
            session.sessionKind == 'imported' ||
            session.sessionKind == 'qr');
    return signedIn
        ? questionFeedsInitialUri(questionId, order: order)
        : anonymousQuestionAnswersInitialUri(questionId, sortBy: order);
  }

  /// Initial general-search query. The request uses x-api-version 3.0.91;
  /// empty restriction/ad fields
  /// are intentionally retained because they are present in the signed target.
  Uri searchInitialUri({
    required String keyword,
    required String type,
    Map<String, String> filters = const {},
  }) {
    final normalizedKeyword = keyword.trim();
    final normalizedType = type.trim();
    if (normalizedKeyword.isEmpty || normalizedKeyword.length > 512) {
      throw const ApiTransportException('搜索关键词不能为空且不能超过 512 字符');
    }
    if (!RegExp(r'^[a-z_]+$').hasMatch(normalizedType)) {
      throw const ApiTransportException('搜索类型无效');
    }
    // Retrofit/OkHttp uses RFC 3986 percent encoding in the request target;
    // Uri.encodeQueryComponent would turn spaces into form-style `+`.
    final q = Uri.encodeComponent(normalizedKeyword);
    final isRealTime = normalizedType == 'recent' ? 1 : 0;
    // The visible "recent" tab is a presentation mode of general search in
    // the current App protocol. Sending `t=recent` succeeds with an empty
    // payload; the working wire tuple is `t=general&is_real_time=1`.
    final wireType = normalizedType == 'recent' ? 'general' : normalizedType;
    final t = Uri.encodeComponent(wireType);
    const groups = ['vertical', 'sort', 'time_interval'];
    final custom = <String>[];
    for (final group in groups) {
      final value = filters[group]?.trim() ?? '';
      if (value.isEmpty) continue;
      if (!RegExp(r'^[a-z_]+$').hasMatch(value)) {
        throw const ApiTransportException('搜索筛选值无效');
      }
      custom.add('$group=${Uri.encodeComponent(value)}');
    }
    final searchSource = custom.isEmpty ? 'Normal' : 'Filter';
    final base =
        'https://${ZhihuApiClient.apiHost}/search_v3?gk_version=gz-gaokao&q=$q&t=$t'
        '&search_source=$searchSource&is_real_time=$isRealTime&correction=1&advert_count='
        '&show_all_topics=0&pin_flow=false&restricted_scene='
        '&restricted_field=&restricted_value=&entry=main&offset=0&limit=20'
        '&lc_idx=0';
    // Selecting a filter changes search_source from Normal to Filter and
    // appends each non-empty group in this stable order immediately before
    // zhida_source. Keeping Normal makes the endpoint ignore empty groups.
    final filterSuffix = custom.isEmpty ? '' : '&${custom.join('&')}';
    return Uri.parse('$base$filterSuffix&zhida_source=ai_search_general');
  }

  Uri searchCustomizeUri() => apiUri('/search/customize');

  /// Search launched from an official profile toolbar. The restriction keeps
  /// every result scoped to one member instead of performing a global search.
  Uri profileContentSearchInitialUri({
    required String keyword,
    required String memberHashId,
  }) {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty || normalizedKeyword.length > 512) {
      throw const ApiTransportException('搜索关键词不能为空且不能超过 512 字符');
    }
    final member = userIdentifier(memberHashId);
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/search_v3?correction=1&t=general'
      '&q=${Uri.encodeComponent(normalizedKeyword)}&restricted_scene=profile'
      '&restricted_field=member_hash_id&restricted_value=$member',
    );
  }

  /// Initial root-comment target. `offset` is present but empty on the first
  /// page and remains part of the signed request target.
  Uri commentsInitialUri({
    required String contentType,
    required String contentId,
    String orderBy = 'score',
    String type = '',
  }) {
    final plural = commentObjectPlural(contentType);
    final normalizedId = contentId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalizedId)) {
      throw const ApiTransportException('评论对象 ID 必须是数字');
    }
    final requestedOrder = orderBy.trim().toLowerCase();
    final normalizedOrder = requestedOrder == 'time' ? 'ts' : requestedOrder;
    if (!const {'score', 'ts'}.contains(normalizedOrder)) {
      throw const ApiTransportException('评论排序无效');
    }
    final normalizedType = type.trim().toLowerCase();
    if (normalizedType.isNotEmpty &&
        !RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(normalizedType)) {
      throw const ApiTransportException('评论分类无效');
    }
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$plural/$normalizedId/root_comment'
      '?order_by=$normalizedOrder&limit=20&offset='
      '${normalizedType.isEmpty ? '' : '&type=$normalizedType'}',
    );
  }

  /// Side request used with the anonymous comment list. It supplies the
  /// content author and continuous-
  /// consumption header independently from the paged root-comment response.
  Uri commentListHeadersUri({
    required String contentType,
    required String contentId,
  }) {
    final plural = commentObjectPlural(contentType);
    final normalizedId = contentId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalizedId)) {
      throw const ApiTransportException('评论对象 ID 必须是数字');
    }
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$plural/$normalizedId/list-headers',
    );
  }

  String commentObjectPlural(String contentType) =>
      switch (contentType.trim().toLowerCase()) {
        'answer' || 'answers' => 'answers',
        'article' || 'articles' => 'articles',
        'pin' || 'pins' => 'pins',
        'zvideo' || 'zvideos' || 'video' || 'videos' => 'zvideos',
        _ => throw const ApiTransportException('不支持的评论对象类型'),
      };

  Uri commentRepliesInitialUri(String commentId) {
    final normalizedId = commentId.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalizedId)) {
      throw const ApiTransportException('评论 ID 必须是数字');
    }
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/comment/$normalizedId/child_comment',
    );
  }

  Uri commentEmoticonGroupsUri({bool legacy = false}) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/self/sticker-groups'
    '${legacy ? '' : '/v2'}',
  );

  Uri commentEmoticonGroupUri(String groupId, {bool legacy = false}) {
    final normalized = groupId.trim();
    if (normalized.isEmpty || normalized.length > 160) {
      throw const ApiTransportException('表情组 ID 无效');
    }
    final path = legacy
        ? '/sticker/list/${Uri.encodeComponent(normalized)}'
        : '/sticker-groups/${Uri.encodeComponent(normalized)}';
    return Uri.parse('https://${ZhihuApiClient.apiHost}$path?business=message');
  }

  /// Resolves URLs embedded in comment text to the same title/card metadata
  /// used by the official editor and comment renderer.  The native client
  /// calls `/content/publish/parse_url` before replacing a bare URL with its
  /// human-readable title.
  Uri commentLinkParseUri({required String url, String scene = 'editor'}) {
    final normalized = url.trim();
    final normalizedScene = scene.trim().isEmpty ? 'editor' : scene.trim();
    if (normalized.isEmpty || normalized.length > 8192) {
      throw const ApiTransportException('评论链接无效');
    }
    if (RegExp(r'[\x00-\x1F]').hasMatch(normalized)) {
      throw const ApiTransportException('评论链接格式无效');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(normalizedScene)) {
      throw const ApiTransportException('评论链接场景无效');
    }
    return apiUri(
      '/content/publish/parse_url',
      query: <String, Object?>{'url': normalized, 'scene': normalizedScene},
    );
  }

  /// Loads the account's complete official catalog. Group detail requests
  /// start together, matching the editor's requirement that opening the sheet
  /// must not wait on each category serially.
  Future<List<CommentEmoticonGroup>> loadCommentEmoticonGroups() async {
    var response = await getUri(commentEmoticonGroupsUri());
    if (!response.isSuccess || response.jsonMap == null) {
      response = await getUri(commentEmoticonGroupsUri(legacy: true));
    }
    if (!response.isSuccess || response.jsonMap == null) {
      throw response.failure;
    }
    final groups = CommentEmoticonGroup.parseList(response.jsonMap!);
    if (groups.isEmpty) return const [];
    return Future.wait(
      groups.map((group) async {
        if (group.emoticons.isNotEmpty) return group;
        try {
          var detail = await getUri(commentEmoticonGroupUri(group.id));
          if (!detail.isSuccess || detail.jsonMap == null) {
            detail = await getUri(
              commentEmoticonGroupUri(group.id, legacy: true),
            );
          }
          final json = detail.jsonMap;
          return detail.isSuccess && json != null
              ? group.withDetail(json)
              : group;
        } catch (_) {
          return group;
        }
      }),
    );
  }

  Uri commentCreateUri({
    required String contentType,
    required String contentId,
  }) {
    final plural = commentObjectPlural(contentType);
    final normalizedId = ZhihuApiClient.numericIdentifier(contentId, '评论对象 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$plural/$normalizedId/comment',
    );
  }

  /// Sentence comments use a separate route in the native v7 client. The
  /// body still carries the ordinary comment fields, with `segment` filled by
  /// the selected paragraph/range payload.
  Uri commentSegmentCreateUri({
    required String contentType,
    required String contentId,
  }) {
    final plural = commentObjectPlural(contentType);
    final normalizedId = ZhihuApiClient.numericIdentifier(contentId, '评论对象 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$plural/$normalizedId/segment/comment',
    );
  }

  Uri commentDeleteUri(String commentId) {
    final normalizedId = ZhihuApiClient.numericIdentifier(commentId, '评论 ID');
    // Deletion uses the www /api/v4 route while creation and listing use
    // api.zhihu.com.
    return Uri.parse(
      'https://${ZhihuApiClient.publicWebHost}/api/v4/comment_v5/comment/$normalizedId',
    );
  }

  Future<ApiResponse> createComment({
    required String contentType,
    required String contentId,
    required String content,
    String replyCommentId = '',
    String zaSpm = '',
    CommentEmoticon? sticker,
    ContentSelection? selection,
  }) {
    requireWriteSession();
    return postJsonUri(
      commentCreateUri(contentType: contentType, contentId: contentId),
      jsonBody: ZhihuApiClient.buildCommentBody(
        content: content,
        replyCommentId: replyCommentId,
        sticker: sticker,
        selection: selection,
      ),
      headers: {if (zaSpm.trim().isNotEmpty) 'za-spm': zaSpm.trim()},
    );
  }

  Future<ApiResponse> createSegmentComment({
    required String contentType,
    required String contentId,
    required String content,
    required ContentSelection selection,
    String replyCommentId = '',
    String zaSpm = '',
    CommentEmoticon? sticker,
  }) {
    requireWriteSession();
    if (!selection.hasSegmentTarget) {
      throw const ApiTransportException('选区缺少句子评论定位信息');
    }
    return postJsonUri(
      commentSegmentCreateUri(contentType: contentType, contentId: contentId),
      jsonBody: ZhihuApiClient.buildCommentBody(
        content: content,
        replyCommentId: replyCommentId,
        sticker: sticker,
        selection: selection,
      ),
      headers: {if (zaSpm.trim().isNotEmpty) 'za-spm': zaSpm.trim()},
    );
  }

  Future<ApiResponse> createSaltComment({
    required String objectType,
    required String objectId,
    required String content,
    String replyCommentId = '',
    String zaSpm = '',
    CommentEmoticon? sticker,
  }) {
    requireWriteSession();
    return postJsonUri(
      saltCommentCreateUri(objectType: objectType, objectId: objectId),
      jsonBody: ZhihuApiClient.buildCommentBody(
        content: content,
        replyCommentId: replyCommentId,
        sticker: sticker,
      ),
      headers: {if (zaSpm.trim().isNotEmpty) 'za-spm': zaSpm.trim()},
    );
  }

  Future<ApiResponse> deleteComment(String commentId) {
    requireWriteSession();
    return send('DELETE', commentDeleteUri(commentId), headers: const {});
  }

  Uri activityDeleteUri(String itemBrief) {
    final brief = itemBrief.trim();
    if (brief.isEmpty || brief.length > 20000) {
      throw const ApiTransportException('动态删除参数无效');
    }
    return Uri.https(ZhihuApiClient.apiHost, '/moments/activity', {
      'item_brief': brief,
    });
  }

  /// Deletes a profile activity by its opaque `moments_biz_data.brief`, not
  /// by the displayed content id.
  Future<ApiResponse> deleteActivity(String itemBrief) {
    requireWriteSession();
    return send('DELETE', activityDeleteUri(itemBrief), headers: const {});
  }
}
