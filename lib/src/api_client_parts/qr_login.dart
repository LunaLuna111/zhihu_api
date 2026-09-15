import 'dart:async';
import 'dart:convert';

import '../api_client.dart';

class QrLoginCode {
  const QrLoginCode({
    required this.response,
    required this.link,
    required this.token,
    required this.cookie,
    required this.expiresAt,
  });

  final ApiResponse response;
  final String link;
  final String token;
  final String cookie;
  final int? expiresAt;

  bool get isUsable =>
      response.isSuccess && link.isNotEmpty && token.isNotEmpty;
}

class QrLoginPoll {
  const QrLoginPoll({
    required this.response,
    required this.status,
    required this.cookie,
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.loginStatus,
    required this.success,
    required this.loggedIn,
    required this.authCookieUpdated,
    required this.message,
  });

  final ApiResponse response;
  final int? status;
  final String cookie;
  final String userId;
  final String accessToken;
  final String refreshToken;
  final int? expiresIn;
  final String loginStatus;
  final bool success;
  final bool loggedIn;
  final bool authCookieUpdated;
  final String message;

  bool get scanned => status == 1;
  bool get expired =>
      status == 2 ||
      const {
        'EXPIRED',
        'QR_CODE_EXPIRED',
        'LOGIN_EXPIRED',
      }.contains(loginStatus.toUpperCase());
  bool get succeeded =>
      success ||
      loggedIn ||
      userId.isNotEmpty ||
      accessToken.isNotEmpty ||
      loginStatus.toUpperCase() == 'CONFIRMED' ||
      loginStatus.toUpperCase() == 'LOGIN_SUCCESS' ||
      loginStatus.toUpperCase() == 'SUCCESS' ||
      loginStatus.toUpperCase() == 'OK' ||
      loginStatus.toUpperCase() == 'LOGGED_IN' ||
      authCookieUpdated;

  bool get needsRiskControl =>
      response.statusCode == 403 ||
      message.toLowerCase().contains('risk') ||
      message.contains('风险');
}

extension ZhihuApiClientQrLogin on ZhihuApiClient {
  static const qrPath = '/api/v3/account/api/login/qrcode';
  static const desktopHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
    'sec-ch-ua':
        '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'Origin': 'https://www.zhihu.com',
    'x-requested-with': 'fetch',
  };

  Future<QrLoginCode> requestQrLoginCode({String cookie = ''}) async {
    if (!session.hasCompleteMobileContext) await ensureGuestContext();
    final prefetchCookie = await prefetchQrLoginContext(seedCookie: cookie);
    final initialCookie = mergeQrCookies(cookie, prefetchCookie, '');
    final response = await qrRequest(
      'POST',
      Uri.https(ZhihuApiClient.publicWebHost, qrPath),
      cookie: initialCookie,
      body: utf8.encode('{}'),
      headers: const {'Content-Type': 'application/json;charset=UTF-8'},
    );
    final object = qrMap(response.json);
    final link = qrText(object, const ['link', 'url', 'qrcode_url', 'qr_url']);
    final token = qrText(object, const [
      'token',
      'qrcode_token',
      'qrcodeToken',
      'qr_token',
    ]);
    final expiresAt = qrInt(object, const ['expires_at', 'expiresAt', 'ttl']);
    final bodyCookie = qrCookieString(object['cookie'] ?? object['cookies']);
    return QrLoginCode(
      response: response,
      link: link,
      token: token,
      cookie: mergeQrCookies(
        initialCookie,
        bodyCookie,
        response.headers['set-cookie'] ?? '',
      ),
      expiresAt: expiresAt,
    );
  }

  Future<String> prefetchQrLoginContext({required String seedCookie}) {
    final now = DateTime.now();
    final cachedAt = qrLoginPrefetchedAt;
    final existing = qrLoginPrefetch;
    if (existing != null) return existing;
    if (cachedAt != null &&
        now.difference(cachedAt) < const Duration(seconds: 90)) {
      return Future<String>.value(
        mergeQrCookies(seedCookie, qrLoginPrefetchedCookie, ''),
      );
    }
    final future = runQrLoginPrefetch(seedCookie);
    qrLoginPrefetch = future;
    return future
        .then((cookie) {
          qrLoginPrefetchedCookie = cookie;
          qrLoginPrefetchedAt = DateTime.now();
          return mergeQrCookies(seedCookie, cookie, '');
        })
        .whenComplete(() {
          if (identical(qrLoginPrefetch, future)) qrLoginPrefetch = null;
        });
  }

  Future<String> runQrLoginPrefetch(String seedCookie) async {
    var cookie = ZhihuApiClient.cookiePairsOnly(seedCookie);
    try {
      final home = await qrRequest(
        'GET',
        Uri.https(ZhihuApiClient.publicWebHost, '/signin', const {'next': '/'}),
        cookie: cookie,
        headers: const {},
      );
      cookie = mergeQrCookies(cookie, home.headers['set-cookie'] ?? '', '');
    } on Object catch (error) {
      debugPrint('qr prefetch signin failed=$error');
    }
    try {
      final udid = await qrRequest(
        'POST',
        Uri.https(ZhihuApiClient.publicWebHost, '/udid'),
        cookie: cookie,
        headers: const {'Content-Type': 'application/json;charset=UTF-8'},
        body: utf8.encode('{}'),
      );
      cookie = mergeQrCookies(cookie, udid.headers['set-cookie'] ?? '', '');
    } on Object catch (error) {
      debugPrint('qr prefetch udid failed=$error');
    }
    try {
      final xsrf = qrValue(cookie, 'xsrf');
      final captcha = await qrRequest(
        'GET',
        Uri.https(
          ZhihuApiClient.publicWebHost,
          '/api/v3/oauth/captcha/v2',
          const {'type': 'captcha_sign_in'},
        ),
        cookie: cookie,
        headers: {'Accept': '*/*', if (xsrf.isNotEmpty) 'x-xsrftoken': xsrf},
      );
      cookie = mergeQrCookies(cookie, captcha.headers['set-cookie'] ?? '', '');
    } on Object catch (error) {
      debugPrint('qr prefetch captcha failed=$error');
    }
    return cookie;
  }

  Future<QrLoginPoll> pollQrLogin({
    required String token,
    String cookie = '',
  }) async {
    final normalized = token.trim();
    if (!RegExp(r'^[A-Za-z0-9._~-]{1,256}$').hasMatch(normalized)) {
      throw const ApiTransportException('二维码 token 无效');
    }
    final response = await qrRequest(
      'GET',
      Uri.https(ZhihuApiClient.publicWebHost, '$qrPath/$normalized/scan_info'),
      cookie: cookie,
      headers: const {
        'Referer': 'https://www.zhihu.com/signin',
        'Accept': '*/*',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'x-zse-93': '101_3_3.0',
      },
    );
    final object = qrMap(response.json);
    final bodyCookie = qrCookieString(
      object['cookie'] ?? object['cookies'] ?? object['zC0'] ?? object['z_c0'],
    );
    final mergedCookie = mergeQrCookies(
      cookie,
      bodyCookie,
      response.headers['set-cookie'] ?? '',
    );
    final oldAuthCookie = qrValue(cookie, 'z_c0');
    final newAuthCookie = qrValue(mergedCookie, 'z_c0');
    final status = qrInt(object, const ['status', 'scan_status']);
    final loginStatus = qrText(object, const [
      'login_status',
      'loginStatus',
      'state',
    ]);
    final error = object['error'];
    return QrLoginPoll(
      response: response,
      status: status,
      cookie: mergedCookie,
      userId: qrText(object, const ['user_id', 'userId', 'uid']),
      accessToken: qrText(object, const ['access_token', 'accessToken']),
      refreshToken: qrText(object, const ['refresh_token', 'refreshToken']),
      expiresIn: qrInt(object, const ['expires_in', 'expiresIn']),
      loginStatus: loginStatus,
      success: qrBool(object, const ['success']),
      loggedIn: qrBool(object, const ['logged_in', 'loggedIn']),
      authCookieUpdated:
          newAuthCookie.isNotEmpty && newAuthCookie != oldAuthCookie,
      message: error is Map
          ? qrText(
              error.map((key, value) => MapEntry(key.toString(), value)),
              const ['message'],
            )
          : qrText(object, const ['message', 'msg']),
    );
  }

  /// Verifies the cookie returned by the QR flow before replacing the active
  /// session. Cookie-only QR responses are intentionally stored as `qr`, so a
  /// later 401 cannot trigger the mobile refresh-token logout path.
  Future<MobileSignInResult> completeQrLogin(QrLoginPoll poll) async {
    if (!poll.succeeded) {
      return MobileSignInResult(
        response: poll.response,
        signedIn: false,
        requiresVerification: false,
        message: '二维码登录尚未确认或缺少登录 Cookie',
      );
    }
    if (poll.accessToken.isNotEmpty &&
        poll.refreshToken.isNotEmpty &&
        poll.expiresIn != null &&
        poll.expiresIn! > 0) {
      final saved = await session.saveAccountSession(
        accessToken: poll.accessToken,
        refreshToken: poll.refreshToken,
        udid: session.udid,
        expiresIn: Duration(seconds: poll.expiresIn!),
        // Token-bearing QR responses can refresh more than z_c0. Preserve the
        // complete mobile cookie context just like the cookie-only branch.
        zCookie: poll.cookie,
        uid: poll.userId,
      );
      return MobileSignInResult(
        response: poll.response,
        signedIn: saved,
        requiresVerification: false,
        message: saved ? '扫码登录成功' : '扫码登录结果已过期',
      );
    }
    if (poll.cookie.trim().isEmpty) {
      return MobileSignInResult(
        response: poll.response,
        signedIn: false,
        requiresVerification: false,
        message: '二维码已确认，但响应缺少登录 Cookie',
      );
    }
    final profile = await sendMobileRaw(
      'GET',
      accountSelfProfileUri(),
      headers: {
        'Accept': 'application/json',
        'User-Agent': ZhihuApiClient.appUserAgent,
        'Authorization': ZhihuCloudProtocol.oauthAuthorization,
        if (session.udid.isNotEmpty) 'x-udid': session.udid,
        'Cookie': poll.cookie,
      },
      body: null,
      includeBaseHeaders: false,
      debugProfile: 'qr-login-profile-validation',
    );
    final profileObject = qrMap(profile.json);
    if (!profile.isSuccess || profileObject.isEmpty) {
      return MobileSignInResult(
        response: profile,
        signedIn: false,
        requiresVerification: profile.statusCode == 403,
        message: '二维码已确认，但账号资料验证失败：${profile.failure.userMessage}',
      );
    }
    final uid = qrText(profileObject, const ['id', 'user_id', 'uid']);
    final userId = qrText(profileObject, const ['uid', 'user_id']);
    final saved = await session.saveQrSession(
      cookie: poll.cookie,
      udid: session.udid,
      uid: uid.isEmpty ? poll.userId : uid,
      userId: userId.isEmpty ? null : userId,
    );
    return MobileSignInResult(
      response: profile,
      signedIn: saved,
      requiresVerification: false,
      message: saved ? '扫码登录成功' : '二维码登录结果未能保存',
    );
  }

  Future<ApiResponse> qrRequest(
    String method,
    Uri uri, {
    required String cookie,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final merged = <String, String>{
      ...desktopHeaders,
      'Referer': 'https://www.zhihu.com/signin',
      if (cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
      if (qrValue(cookie, 'xsrf').isNotEmpty)
        'x-xsrftoken': qrValue(cookie, 'xsrf'),
      ...headers,
    };
    final response = await transport.send(
      method: method,
      uri: uri,
      headers: merged,
      body: body,
      maxResponseBytes: ZhihuApiClient.maxResponseBytes,
    );
    debugLogResponse(method, uri, response);
    unawaited(
      apiLogger.recordNetwork(
        method: method,
        uri: uri,
        profile: 'qr-login',
        statusCode: response.statusCode,
        statusLabel: response.statusLabel,
        businessCode: response.businessCode,
        bodyBytes: response.bodyBytes,
        durationMs: 0,
      ),
    );
    return response;
  }
}

Map<String, dynamic> qrMap(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  final root = value.map((key, value) => MapEntry(key.toString(), value));
  for (final key in const ['data', 'result', 'payload']) {
    final nested = root[key];
    if (nested is Map) {
      return {
        ...root,
        ...nested.map((key, value) => MapEntry(key.toString(), value)),
      };
    }
  }
  return root;
}

String qrText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return '';
}

int? qrInt(Map<String, dynamic> source, List<String> keys) {
  final value = qrText(source, keys);
  return int.tryParse(value);
}

bool qrBool(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value == true || value == 1) return true;
    if (value is String && value.trim().toLowerCase() == 'true') return true;
  }
  return false;
}

String qrCookieString(Object? value) {
  if (value is String) return value;
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
  if (value is List) {
    return value.map((item) => item.toString()).join('; ');
  }
  return '';
}

String mergeQrCookies(String first, String second, String third) =>
    ZhihuApiClient.mergeCookieHeaders(
      ZhihuApiClient.cookiePairsOnly(first),
      ZhihuApiClient.cookiePairsOnly(second),
      ZhihuApiClient.cookiePairsOnly(third),
    );

String qrValue(String cookie, String name) {
  for (final part in cookie.split(';')) {
    final separator = part.indexOf('=');
    if (separator > 0 &&
        part.substring(0, separator).trim().toLowerCase() ==
            name.toLowerCase()) {
      return part.substring(separator + 1).trim();
    }
  }
  return '';
}
