import 'dart:async';
import 'dart:convert';

import '../api_client.dart';

extension ZhihuApiClientNegativeFeedback on ZhihuApiClient {
  Uri negativeFeedbackPanelUri({
    required String sceneCode,
    required String contentType,
    required String contentToken,
  }) {
    final scene = negativeFeedbackToken(sceneCode, '反馈场景');
    final type = negativeFeedbackToken(contentType, '内容类型');
    final token = ZhihuApiClient.numericIdentifier(contentToken, '内容 ID');
    return apiUri(
      '/negative-feedback/panel',
      query: {
        'scene_code': scene,
        'content_type': type,
        'content_token': token,
      },
    );
  }

  Future<ApiResponse> getNegativeFeedbackPanel(
    NegativeFeedbackIdentity identity,
  ) {
    if (!identity.isUsable) {
      throw const ApiTransportException('该信息流内容缺少反馈标识');
    }
    return getUri(
      negativeFeedbackPanelUri(
        sceneCode: identity.sceneCode,
        contentType: identity.contentType,
        contentToken: identity.contentToken,
      ),
    );
  }

  Future<ApiResponse> executeNegativeFeedbackAction(
    NegativeFeedbackAction action,
  ) {
    if (!action.hasBackend) {
      throw const ApiTransportException('该反馈项没有服务端动作');
    }
    final method = action.method.isEmpty ? 'GET' : action.method;
    if (!const {'GET', 'POST', 'PUT', 'DELETE'}.contains(method)) {
      throw const ApiTransportException('反馈动作使用了未审核的 HTTP 方法');
    }
    final uri = negativeFeedbackBackendUri(action.backendUrl);
    if (method == 'PUT' && action.parameters.isNotEmpty) {
      return send(
        method,
        uri,
        headers: const {
          'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: utf8.encode(MobileLoginBodyEncoder.formEncode(action.parameters)),
      );
    }
    return send(method, uri, headers: const {});
  }

  Future<ApiResponse> uninterestFeed(NegativeFeedbackIdentity identity) {
    final brief = identity.itemBrief.trim();
    if (!identity.isUsable || brief.isEmpty || brief.length > 20000) {
      throw const ApiTransportException('该信息流内容缺少不感兴趣参数');
    }
    return send(
      'POST',
      apiUri('/topstory/uninterestv2'),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
        'x-api-version': '3.1.8',
      },
      body: utf8.encode(
        MobileLoginBodyEncoder.formEncode({'item_brief': brief}),
      ),
    );
  }

  Uri blockedKeywordsUri({String sceneCode = 'recommend'}) => apiUri(
    '/feed-root/block',
    query: {'scene_code': negativeFeedbackToken(sceneCode, '反馈场景')},
  );

  Future<ApiResponse> getBlockedKeywords({String sceneCode = 'recommend'}) =>
      getUri(blockedKeywordsUri(sceneCode: sceneCode));

  Future<ApiResponse> addBlockedKeyword({
    required NegativeFeedbackIdentity identity,
    required String keyword,
  }) {
    if (!identity.isUsable) {
      throw const ApiTransportException('该信息流内容缺少反馈标识');
    }
    final normalized = blockedKeyword(keyword);
    return send(
      'POST',
      apiUri('/feed-root/block'),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: utf8.encode(
        MobileLoginBodyEncoder.formEncode({
          'scene_code': negativeFeedbackToken(identity.sceneCode, '反馈场景'),
          'keyword': normalized,
          'content_token': ZhihuApiClient.numericIdentifier(
            identity.contentToken,
            '内容 ID',
          ),
          'content_type': negativeFeedbackToken(identity.contentType, '内容类型'),
        }),
      ),
    );
  }

  Uri deleteBlockedKeywordUri(
    String keyword, {
    String sceneCode = 'recommend',
  }) {
    final normalized = blockedKeyword(keyword);
    return apiUri(
      '/feed-root/block',
      query: {
        'scene_code': negativeFeedbackToken(sceneCode, '反馈场景'),
        'keyword': normalized,
      },
    );
  }

  Future<ApiResponse> deleteBlockedKeyword(
    String keyword, {
    String sceneCode = 'recommend',
  }) => send(
    'DELETE',
    deleteBlockedKeywordUri(keyword, sceneCode: sceneCode),
    headers: const {},
  );

  Uri negativeFeedbackBackendUri(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    final uri = parsed != null && parsed.hasScheme ? parsed : apiUri(trimmed);
    if (uri.scheme != 'https' ||
        uri.host != ZhihuApiClient.apiHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443) {
      throw const ApiTransportException('反馈动作只允许 api.zhihu.com HTTPS 地址');
    }
    return uri;
  }

  String negativeFeedbackToken(String value, String label) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,31}$').hasMatch(normalized)) {
      throw ApiTransportException('$label 无效');
    }
    return normalized;
  }

  String blockedKeyword(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.runes.length > 64) {
      throw const ApiTransportException('屏蔽关键词无效');
    }
    return normalized;
  }
}
