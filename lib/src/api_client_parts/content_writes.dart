import 'dart:async';
import 'dart:convert';

import '../api_client.dart';

extension ZhihuApiClientContentWrites on ZhihuApiClient {
  Uri commentLikeUri(String commentId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/reaction/comments/'
    '${ZhihuApiClient.numericIdentifier(commentId, '评论 ID')}/like',
  );

  /// The 11.4.0 comment-v7 service uses the same reaction endpoint for root
  /// comments and child replies. A second tap removes the reaction with
  /// DELETE; it is not a separate legacy voter request.
  Future<ApiResponse> setCommentLiked(String commentId, {required bool liked}) {
    requireWriteSession();
    return send(
      liked ? 'POST' : 'DELETE',
      commentLikeUri(commentId),
      headers: const {},
    );
  }

  Uri contentVoteUri({required String contentType, required String contentId}) {
    final path = switch (contentType.trim()) {
      'answer' => 'answers',
      'article' => 'articles',
      _ => throw const ApiTransportException('该内容类型不支持赞同或反对'),
    };
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/$path/'
      '${ZhihuApiClient.numericIdentifier(contentId, '内容 ID')}/voters',
    );
  }

  Uri answerVoteUri(String answerId) =>
      contentVoteUri(contentType: 'answer', contentId: answerId);

  /// Exact target and Retrofit form order declared by the 11.4.0 answer
  /// interaction services: `voting` first, then the currently displayed
  /// `voteup_count`. A guest session is never allowed to perform this write.
  Future<ApiResponse> voteAnswer({
    required String answerId,
    required int voting,
    required int voteupCount,
  }) {
    return voteContent(
      contentType: 'answer',
      contentId: answerId,
      voting: voting,
      voteupCount: voteupCount,
    );
  }

  Future<ApiResponse> voteContent({
    required String contentType,
    required String contentId,
    required int voting,
    required int voteupCount,
  }) {
    requireWriteSession();
    if (voting < -1 || voting > 1 || voteupCount < 0) {
      throw const ApiTransportException('内容投票参数无效');
    }
    final body = utf8.encode('voting=$voting&voteup_count=$voteupCount');
    return send(
      'POST',
      contentVoteUri(contentType: contentType, contentId: contentId),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  Uri pinReactionUri(String pinId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/pins/'
    '${ZhihuApiClient.numericIdentifier(pinId, '想法 ID')}/reactions',
  );

  Future<ApiResponse> setPinLiked(String pinId, {required bool liked}) {
    requireWriteSession();
    return send(
      liked ? 'POST' : 'DELETE',
      pinReactionUri(pinId),
      headers: liked
          ? const {
              'content-type':
                  'application/x-www-form-urlencoded; charset=utf-8',
            }
          : const {},
      body: liked ? utf8.encode('type=like') : null,
    );
  }

  Uri answerCollectionsUri(String answerId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/answers/${ZhihuApiClient.numericIdentifier(answerId, '回答 ID')}/collections_v2',
  );

  /// Adds an answer to the official default collection (`0`). Removing an
  /// existing favorite needs the concrete collection id returned by the GET
  /// route and is therefore deliberately not guessed here.
  Future<ApiResponse> favoriteAnswer(String answerId) {
    return favoriteContent(contentType: 'answer', contentId: answerId);
  }

  Uri contentCollectionsUri({
    required String contentType,
    required String contentId,
  }) {
    final id = ZhihuApiClient.numericIdentifier(contentId, '内容 ID');
    return switch (contentType.trim()) {
      'answer' => Uri.parse(
        'https://${ZhihuApiClient.apiHost}/answers/$id/collections_v2',
      ),
      'article' => Uri.parse(
        'https://${ZhihuApiClient.apiHost}/articles/$id/collections?offset=0',
      ),
      _ => Uri.parse(
        'https://${ZhihuApiClient.apiHost}/collections/contents/'
        '${Uri.encodeComponent(contentType.trim())}/$id',
      ),
    };
  }

  Future<ApiResponse> favoriteContent({
    required String contentType,
    required String contentId,
  }) {
    requireWriteSession();
    final body = utf8.encode('add_collections=0&remove_collections=');
    return send(
      'PUT',
      contentCollectionsUri(
        contentType: contentType,
        contentId: contentId,
      ).replace(query: ''),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  Future<ApiResponse> unfavoriteContent({
    required String contentType,
    required String contentId,
  }) async {
    requireWriteSession();
    final collections = await getUri(
      contentCollectionsUri(contentType: contentType, contentId: contentId),
    );
    if (!collections.isSuccess) return collections;
    final data = collections.jsonMap?['data'];
    final first = data is List && data.isNotEmpty ? data.first : null;
    final collectionId = first is Map ? first['id']?.toString().trim() : null;
    if (collectionId == null || !RegExp(r'^\d+$').hasMatch(collectionId)) {
      throw const ApiTransportException('没有找到该内容所在的收藏夹');
    }
    final body = utf8.encode(
      'add_collections=&remove_collections=$collectionId',
    );
    return send(
      'PUT',
      contentCollectionsUri(
        contentType: contentType,
        contentId: contentId,
      ).replace(query: ''),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  Uri answerDraftUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/content/drafts');

  Uri answerPublishUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/content/publish');

  Uri answerDeleteUri(String answerId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/answers/${ZhihuApiClient.numericIdentifier(answerId, '回答 ID')}',
  );

  Future<ApiResponse> publishAnswer({
    required String questionId,
    required String questionTitle,
    required String content,
    String? extraTag,
  }) async {
    requireWriteSession();
    final body = ZhihuApiClient.buildAnswerEditorBody(
      questionId: questionId,
      questionTitle: questionTitle,
      content: content,
      extraTag: extraTag,
    );
    final draft = await postJsonUri(answerDraftUri(), jsonBody: body);
    if (!draft.isSuccess) return draft;
    return postJsonUri(answerPublishUri(), jsonBody: body);
  }

  Future<ApiResponse> deleteAnswer(String answerId) {
    requireWriteSession();
    return send('DELETE', answerDeleteUri(answerId), headers: const {});
  }

  Uri questionFollowUri(String questionId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/questions/'
    '${ZhihuApiClient.numericIdentifier(questionId, '问题 ID')}/followers',
  );

  Uri questionUnfollowUri(String questionId, String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/questions/'
    '${ZhihuApiClient.numericIdentifier(questionId, '问题 ID')}/followers/'
    '${userIdentifier(memberId)}',
  );

  /// Follows or unfollows a question using the same native contract as the
  /// official answer-list header button.
  Future<ApiResponse> setQuestionFollowing(
    String questionId, {
    required bool following,
  }) {
    requireWriteSession();
    final currentMemberId = currentMemberIdentifier;
    if (!following && currentMemberId.isEmpty) {
      throw const ApiTransportException('当前账号缺少用户 ID');
    }
    return send(
      following ? 'POST' : 'DELETE',
      following
          ? questionFollowUri(questionId)
          : questionUnfollowUri(questionId, currentMemberId),
      headers: const {},
    );
  }

  Uri questionInviteCandidatesInitialUri(String questionId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/questions/'
    '${ZhihuApiClient.numericIdentifier(questionId, '问题 ID')}/recommendation_invitees',
  );

  Uri questionInviteeUri(String questionId, [String memberId = '']) {
    final question = ZhihuApiClient.numericIdentifier(questionId, '问题 ID');
    final suffix = memberId.isEmpty ? '' : '/${userIdentifier(memberId)}';
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/questions/$question/invitees$suffix',
    );
  }

  Future<ApiResponse> setQuestionInvitee({
    required String questionId,
    required String memberId,
    required bool invited,
    String source = 'recommendation',
  }) {
    requireWriteSession();
    if (!invited) {
      return send(
        'DELETE',
        questionInviteeUri(questionId, memberId),
        headers: const {},
      );
    }
    final body = utf8.encode(
      'people_ids=${Uri.encodeQueryComponent(userIdentifier(memberId))}'
      '&src=${Uri.encodeQueryComponent(source.trim().isEmpty ? 'recommendation' : source.trim())}',
    );
    return send(
      'POST',
      questionInviteeUri(questionId),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  void requireWriteSession() {
    if (!canWrite) {
      throw const ApiTransportException('请先登录');
    }
  }

  String userIdentifier(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 256 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(normalized)) {
      throw const ApiTransportException('用户 hash ID / url token 无效');
    }
    return Uri.encodeComponent(normalized);
  }

  /// Profile target for the anonymous recommendation surface. Both v4 and
  /// recommend switches are enabled for this request.
  Uri userProfileInitialUri(String memberId) {
    final id = userIdentifier(memberId);
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/people/$id/profile?profile_new_version=1'
      '&profile_v4=1&has_contacts_permission=false&recommend_ab=1&scene=0',
    );
  }

  /// Extended object used by the official native personal-details surface.
  Uri userProfileDetailUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/profile/detail'
    '?profile_new_version=1',
  );

  /// Server-defined profile tabs used by the native profile surface.  Their
  /// labels, counts, nested categories and request URLs can vary by member.
  Uri userProfileTabsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/profile/tab',
  );

  Uri userFollowUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/followers',
  );

  Uri userUnfollowUri(String memberId, String currentMemberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/followers/'
    '${userIdentifier(currentMemberId)}',
  );

  /// Exact relationship writes declared by the native profile service.
  Future<ApiResponse> setUserFollowing(
    String memberId, {
    required bool following,
  }) {
    requireWriteSession();
    final currentMemberId = currentMemberIdentifier;
    if (!following && currentMemberId.isEmpty) {
      throw const ApiTransportException('当前账号缺少用户 ID');
    }
    return send(
      following ? 'POST' : 'DELETE',
      following
          ? userFollowUri(memberId)
          : userUnfollowUri(memberId, currentMemberId),
      headers: const {},
    );
  }

  /// Older persisted sessions may have the profile UID only in `user_id`
  /// while newer login responses expose it as `uid`.  Both identify the
  /// current member for the native DELETE follower route.
  String get currentMemberIdentifier {
    final uid = session.accountUid.trim();
    if (uid.isNotEmpty) return uid;
    return session.accountUserId.trim();
  }

  /// Initial profile targets for anonymous profile lists. Callers can follow
  /// the returned paging URL for subsequent pages.
  Uri userFollowersInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/followers?offset=0',
  );

  Uri userFolloweesInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/followees?offset=0',
  );

  /// Profile content targets retained for hosts that expose these surfaces
  /// after their own access check.
  Uri userAnswersInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/answers'
    '?order_by=created&offset=0&limit=20',
  );

  Uri userArticlesInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/articles'
    '?offset=0&limit=20',
  );

  Uri userIncludedArticlesInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/included-articles'
    '?sort_by=created&offset=0&limit=20',
  );

  Uri userColumnsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/columns'
    '?offset=0&limit=20',
  );

  Uri userFollowingColumnsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/following_columns'
    '?offset=0&limit=20',
  );

  Uri userFollowingQuestionsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/following_questions'
    '?offset=0',
  );

  Uri userFollowingTopicsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/following_topics'
    '?offset=0',
  );

  Uri userFollowingCollectionsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/following_collections'
    '?with_deleted=1&offset=0&sort=followed_at',
  );

  /// The signed-in member's own collection list, including update and
  /// deletion state.
  Uri userCollectionsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/collections_v2'
    '?with_update=1&with_deleted=1&offset=0&limit=20',
  );

  Uri collectionContentsInitialUri(String collectionId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/collections/'
    '${ZhihuApiClient.numericIdentifier(collectionId, '收藏集 ID')}/contents?with_deleted=1',
  );

  Uri userCreatedArticleFeedInitialUri(String urlToken) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(urlToken)}/profile/creations/feed'
    '?type=article&limit=10&offset=0',
  );

  /// Profile content targets declared by the 11.4.0 profile repository.
  Uri userCreatedAnswersInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/unify-consumption/tabs/'
    '${userIdentifier(memberId)}/answers?limit=20&order_by=created',
  );

  Uri userCreatedArticlesInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/unify-consumption/tabs/'
    '${userIdentifier(memberId)}/articles?limit=20',
  );

  Uri userCreatedPinsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/unify-consumption/tabs/'
    '${userIdentifier(memberId)}/pins',
  );

  Uri userCreatedAllInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/moments/${userIdentifier(memberId)}/origin'
    '?limit=20&sort=created',
  );

  Uri userCreatedColumnsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/columns'
    '?offset=0&limit=20',
  );

  Uri userCreatedQuestionsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/people/${userIdentifier(memberId)}/questions?limit=20',
  );

  Uri userCreatedVideosInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/unify-consumption/tabs/'
    '${userIdentifier(memberId)}/zvideos',
  );

  Uri userMarkedAnswersInitialUri(String urlToken) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/members/${userIdentifier(urlToken)}/marked-answers'
    '?limit=20',
  );

  Uri userActivitiesInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/moments/${userIdentifier(memberId)}/activities?limit=20',
  );

  Uri userVoteupsInitialUri(String memberId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/moments/${userIdentifier(memberId)}/vote?limit=20',
  );

  String notificationEntryName(String value) {
    final normalized = value.trim();
    if (!ZhihuApiClient.notificationEntryNames.contains(normalized)) {
      throw const ApiTransportException('通知分类无效');
    }
    return normalized;
  }

  /// Main message surface used by the notification page.
  Uri notificationsMessageInitialUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/notifications/v3/message/v3'
    '?limit=30&invite_style_ab=1',
  );

  Uri notificationsUnreadUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/notifications/v3/count/v3');

  Uri notificationEntryInitialUri(String entryName) {
    final entry = notificationEntryName(entryName);
    if (entry == 'invite') return notificationInviteInitialUri();
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/notifications/v3/timeline/entry/$entry'
      '?limit=20&adr_com=5',
    );
  }

  Uri notificationInviteInitialUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/notifications/v3/timeline/entry/invite'
    '?invite_with_time_slice=1&limit=20',
  );

  Uri messagesInitialUri(String senderId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/messages?limit=20'
    '&sender_id=${userIdentifier(senderId)}',
  );

  /// Plain-text private message contract used by the native chat service.
  Future<ApiResponse> sendTextMessage(String receiverId, String content) {
    requireWriteSession();
    final normalized = content.trim();
    if (normalized.isEmpty || normalized.length > 10000) {
      throw const ApiTransportException('私信内容为空或过长');
    }
    final body = utf8.encode(
      'receiver_id=${Uri.encodeQueryComponent(userIdentifier(receiverId))}'
      '&content=${Uri.encodeQueryComponent(normalized)}'
      '&content_type=0&image=&sticker=&source_type=&source_id=&reply_source=',
    );
    return send(
      'POST',
      apiUri('/messages'),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  Uri notificationSettingsUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/settings/new/notification');

  Future<ApiResponse> markAllNotificationsRead() {
    requireWriteSession();
    return send(
      'POST',
      apiUri('/notifications/v3/message/readall'),
      headers: const {},
    );
  }

  Future<ApiResponse> markNotificationEntryRead(String entryName) {
    requireWriteSession();
    final entry = notificationEntryName(entryName);
    return send(
      'POST',
      apiUri('/notifications/v3/timeline/entry/$entry/actions/readall'),
      headers: const {},
    );
  }

  /// Retrofit serializes every NotificationSetting as one form field whose
  /// value is JSON. Preserve that contract instead of sending a JSON object.
  Future<ApiResponse> updateNotificationSettings(
    Map<String, dynamic> settings,
  ) {
    requireWriteSession();
    final fields = <String, String>{};
    for (final entry in settings.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(entry.key) ||
          entry.value is! Map) {
        throw const ApiTransportException('通知设置字段无效');
      }
      final raw = (entry.value as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final setting = <String, Object?>{
        if (raw['switch'] is bool) 'switch': raw['switch'],
        if (raw['scope'] is String) 'scope': raw['scope'],
        if (raw['title'] is String) 'title': raw['title'],
      };
      if (setting.isNotEmpty) fields[entry.key] = jsonEncode(setting);
    }
    if (fields.isEmpty) {
      throw const ApiTransportException('通知设置为空');
    }
    final body = utf8.encode(MobileLoginBodyEncoder.formEncode(fields));
    return send(
      'PUT',
      notificationSettingsUri(),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }
}
