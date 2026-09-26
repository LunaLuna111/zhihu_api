import '../api_client.dart';

/// Detail, discovery and topic/column routes shared by clients.
///
/// Keeping these targets here prevents an application UI from embedding
/// Zhihu endpoint paths or reproducing the validation rules independently.
extension ZhihuApiClientContentRoutes on ZhihuApiClient {
  /// Normalizes an API path returned by a profile/server payload.
  ///
  /// The app may receive either an absolute API URL or a path-only value. The
  /// host and scheme check stays in this package so UI code does not need to
  /// embed API-origin rules.
  Uri? apiUriFromServerValue(String value) {
    final text = value.trim();
    if (text.isEmpty || text.startsWith('//')) return null;
    final parsed = Uri.tryParse(text);
    if (parsed == null) return null;
    if (parsed.hasScheme) {
      if (parsed.scheme != 'https' ||
          parsed.host != ZhihuApiClient.apiHost ||
          parsed.hasPort && parsed.port != 443 ||
          parsed.userInfo.isNotEmpty ||
          parsed.fragment.isNotEmpty) {
        return null;
      }
      return parsed;
    }
    if (!text.startsWith('/') || parsed.fragment.isNotEmpty) return null;
    return apiUri(text);
  }

  Uri contentDetailUri({
    required String contentType,
    required String contentId,
    Map<String, Object?> query = const {},
  }) {
    final id = ZhihuApiClient.numericIdentifier(contentId, '内容 ID');
    final path = switch (contentType.trim().toLowerCase()) {
      'answer' => '/answers/v2/$id',
      'article' => '/articles/v2/$id',
      'pin' => '/pins/v2/$id',
      _ => throw const ApiTransportException('内容类型无效'),
    };
    return apiUri(path, query: query);
  }

  Uri answerMetadataUri(String answerId) {
    final id = ZhihuApiClient.numericIdentifier(answerId, '回答 ID');
    return apiUri('/v4/answers/$id');
  }

  Uri publicAnswerUri(
    String answerId, {
    Map<String, Object?> query = const {},
  }) {
    final id = ZhihuApiClient.numericIdentifier(answerId, '回答 ID');
    return publicWebUri('/api/v4/answers/$id', query: query);
  }

  Uri videoEntityUri(
    String videoId, {
    Map<String, Object?> query = const {
      'include': 'contribute,interactive_plugin,creation_relationship',
    },
  }) {
    final id = _contentRouteSegment(videoId, '视频 ID');
    return apiUri('/zvideos/$id', query: query);
  }

  Uri columnTabFeedUri() => apiUri('/column/column_tab/feed');

  Uri topicSquareCategoriesUri() => apiUri('/topic_square/categories');

  Uri topicSquareCategoryTopicsUri(String categoryId) {
    final id = _contentRouteSegment(categoryId, '话题分类 ID');
    return apiUri('/topic_square/categories/$id/topics');
  }

  Uri hotTopicsUri() => apiUri('/hot/topics');

  Uri columnArticlesUri(String columnToken, {int offset = 0, int limit = 10}) {
    final token = _contentRouteSegment(columnToken, '专栏 ID');
    _validatePaging(offset: offset, limit: limit);
    return apiUri(
      '/columns/$token/articles',
      query: {'limit': limit, 'offset': offset},
    );
  }

  Uri columnDetailUri(String columnToken) {
    final token = _contentRouteSegment(columnToken, '专栏 ID');
    return apiUri('/columns/$token');
  }

  Uri columnFollowersUri(String columnToken, {int offset = 0}) {
    final token = _contentRouteSegment(columnToken, '专栏 ID');
    if (offset < 0) throw const ApiTransportException('分页 offset 无效');
    return apiUri('/columns/$token/followers', query: {'offset': offset});
  }

  Uri topicBasicUri(String topicId) {
    final id = ZhihuApiClient.numericIdentifier(topicId, '话题 ID');
    return apiUri('/topics/$id/basic');
  }

  Uri topicFollowersUri(String topicId, {int offset = 0}) {
    final id = ZhihuApiClient.numericIdentifier(topicId, '话题 ID');
    if (offset < 0) throw const ApiTransportException('分页 offset 无效');
    return apiUri('/topics/$id/followers', query: {'offset': offset});
  }

  Uri topicUnansweredQuestionsUri(
    String topicId, {
    int offset = 0,
    int limit = 10,
  }) {
    final id = ZhihuApiClient.numericIdentifier(topicId, '话题 ID');
    _validatePaging(offset: offset, limit: limit);
    return apiUri(
      '/topics/$id/unanswered_questions',
      query: {'offset': offset, 'limit': limit},
    );
  }

  Uri topicEssenceFeedsUri(String topicId, {int offset = 0, int limit = 10}) {
    final id = ZhihuApiClient.numericIdentifier(topicId, '话题 ID');
    _validatePaging(offset: offset, limit: limit);
    return apiUri(
      '/topics/$id/essence_feeds',
      query: {'offset': offset, 'limit': limit},
    );
  }

  Map<String, String> searchRequestHeaders({String? searchId}) => {
    'x-api-version': '3.0.91',
    if (searchId != null && searchId.trim().isNotEmpty)
      'x-search-id': searchId.trim(),
  };

  Map<String, String> profileContentSearchHeaders() => const {
    'x-api-version': '3.0.65',
  };

  static String _contentRouteSegment(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 256 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(normalized)) {
      throw ApiTransportException('$label 无效');
    }
    return Uri.encodeComponent(normalized);
  }

  static void _validatePaging({required int offset, required int limit}) {
    if (offset < 0 || limit <= 0 || limit > 100) {
      throw const ApiTransportException('分页参数无效');
    }
  }
}
