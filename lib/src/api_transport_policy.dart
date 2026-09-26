import 'api_client.dart';

/// Shared host, route and request-size policy for concrete transports.
///
/// The transport itself remains platform-specific, but the set of Zhihu
/// targets it is allowed to reach belongs to the API package rather than to a
/// Flutter UI project.
abstract final class ZhihuApiTransportPolicy {
  static const saltRelayPrefixes = <String>[
    '/km-vip-zhihu-web/',
    '/km-indep-home-comm/',
    '/km-indep-home-vip-comment/',
    '/comment_v5/doc_sections/',
    '/remix-pre-web/manuscript/',
  ];

  static const browserAllowedHeaders = <String>{
    'accept',
    'x-api-version',
    'x-app-version',
    'x-app-build',
    'x-app-bundleid',
    'x-app-flavor',
    'x-network-type',
    'x-zse-93',
    'x-ad-styles',
  };

  static bool isApprovedLoginCaptureTarget(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == ZhihuApiClient.apiHost &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty;

  static bool isApprovedLoginCaptureRequest(
    String method,
    Uri uri,
    List<int>? body,
  ) =>
      isApprovedLoginCaptureTarget(uri) &&
      ((method.toUpperCase() == 'GET' && body == null) ||
          (method.toUpperCase() == 'POST' &&
              body != null &&
              body.length <= 256 * 1024));

  static bool isApprovedSaltRelayTarget(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == ZhihuApiClient.apiHost &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      saltRelayPrefixes.any(uri.path.startsWith);

  static bool isApprovedSaltRelayRequest(
    String method,
    Uri uri,
    List<int>? body,
  ) {
    if (!isApprovedSaltRelayTarget(uri)) return false;
    final normalizedMethod = method.toUpperCase();
    if (normalizedMethod == 'GET') return body == null;
    return normalizedMethod == 'POST' &&
        body != null &&
        body.length <= maxRequestBytes(uri) &&
        RegExp(
          r'^/remix-pre-web/manuscript/\d+/\d+/content$',
        ).hasMatch(uri.path);
  }

  static bool isLensVideoMetadataUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == ZhihuApiClient.lensHost &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      RegExp(r'^/api/v4/videos/[A-Za-z0-9_-]{1,128}$').hasMatch(uri.path);

  static bool isApprovedNativeHttpTarget(Uri uri) =>
      uri.scheme == 'https' &&
      {
        ZhihuApiClient.apiHost,
        ZhihuApiClient.appCloudHost,
        ZhihuApiClient.publicWebHost,
        ZhihuApiClient.lensHost,
      }.contains(uri.host) &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      (uri.host != ZhihuApiClient.publicWebHost ||
          uri.path.startsWith('/api/v4/') ||
          uri.path == '/signin' ||
          uri.path == '/udid' ||
          uri.path == '/api/v3/oauth/captcha/v2' ||
          uri.path == '/api/v3/account/api/login/qrcode' ||
          RegExp(
            r'^/api/v3/account/api/login/qrcode/[A-Za-z0-9._~-]{1,256}/scan_info$',
          ).hasMatch(uri.path)) &&
      (uri.host != ZhihuApiClient.lensHost || isLensVideoMetadataUri(uri));

  static int maxRequestBytes(Uri uri) =>
      uri.host == ZhihuApiClient.apiHost && uri.path == '/upload_image'
      ? 20 * 1024 * 1024
      : 4 * 1024 * 1024;

  static bool isApprovedNativeHttpRequest(
    String method,
    Uri uri,
    List<int>? body,
  ) {
    final normalizedMethod = method.toUpperCase();
    final qrPath =
        uri.host == ZhihuApiClient.publicWebHost &&
        (uri.path == '/api/v3/account/api/login/qrcode' ||
            RegExp(
              r'^/api/v3/account/api/login/qrcode/[A-Za-z0-9._~-]{1,256}/scan_info$',
            ).hasMatch(uri.path));
    final qrMethodAllowed =
        (uri.path == '/api/v3/account/api/login/qrcode' &&
            normalizedMethod == 'POST') ||
        (RegExp(
              r'^/api/v3/account/api/login/qrcode/[A-Za-z0-9._~-]{1,256}/scan_info$',
            ).hasMatch(uri.path) &&
            normalizedMethod == 'GET');
    final loginPrefetchPath =
        uri.host == ZhihuApiClient.publicWebHost &&
        (uri.path == '/signin' ||
            uri.path == '/udid' ||
            uri.path == '/api/v3/oauth/captcha/v2');
    final loginPrefetchMethodAllowed =
        (uri.path == '/signin' && normalizedMethod == 'GET') ||
        (uri.path == '/udid' && normalizedMethod == 'POST') ||
        (uri.path == '/api/v3/oauth/captcha/v2' && normalizedMethod == 'GET');
    return isApprovedNativeHttpTarget(uri) &&
        const {
          'GET',
          'POST',
          'PUT',
          'PATCH',
          'DELETE',
        }.contains(normalizedMethod) &&
        ((!qrPath && !loginPrefetchPath) ||
            qrMethodAllowed ||
            loginPrefetchMethodAllowed) &&
        (uri.host != ZhihuApiClient.lensHost || normalizedMethod == 'GET') &&
        !(normalizedMethod == 'GET' && body != null) &&
        (body?.length ?? 0) <= maxRequestBytes(uri);
  }

  static Uri browserBridgeUri(Uri uri) {
    if (uri.scheme != 'https' ||
        (uri.host != ZhihuApiClient.apiHost &&
            uri.host != ZhihuApiClient.publicWebHost) ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host == ZhihuApiClient.publicWebHost &&
            !uri.path.startsWith('/api/v4/')) {
      throw const ApiTransportException('浏览器预览只允许已审核的知乎 HTTPS API');
    }
    final bridgePrefix = uri.host == ZhihuApiClient.publicWebHost
        ? '/web-api'
        : '/api';
    return Uri(
      path: '$bridgePrefix${uri.path}',
      query: uri.hasQuery ? uri.query : null,
    );
  }
}
