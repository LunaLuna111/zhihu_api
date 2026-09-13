import 'dart:async';

import '../api_client.dart';

extension ZhihuApiClientMobileLogin on ZhihuApiClient {
  Future<ApiResponse> postSaltJsonUri(Uri uri, {required Object jsonBody}) =>
      postJsonUri(
        uri,
        jsonBody: jsonBody,
        headers: ZhihuApiClient.debugSaltAuthorizationRelay
            ? const {'x-zh-debug-auth-relay': 'salt'}
            : const {},
      );

  /// Runs the preflight and encrypted form request required before an SMS
  /// code is sent.
  Future<MobileDigitsResult> requestLoginDigits({
    required String username,
    String smsType = 'text',
  }) async {
    if (!session.hasCompleteMobileContext) {
      await ensureGuestContext();
    }
    final captchaResponse = await send(
      'GET',
      apiUri(MobileLoginContract.captchaPath),
      headers: const {},
    );
    rememberLoginCookie(captchaResponse);
    final captcha = captchaResponse.jsonMap;
    final showCaptcha = captcha?['show_captcha'] == true;
    if (!captchaResponse.isSuccess) {
      return MobileDigitsResult(
        response: captchaResponse,
        sent: false,
        requiresCaptcha: false,
        message: '验证码预检查失败：${captchaResponse.failure.userMessage}',
      );
    }
    if (showCaptcha) {
      return MobileDigitsResult(
        response: captchaResponse,
        sent: false,
        requiresCaptcha: true,
        message: '服务端要求先完成人机验证',
        captchaImageBase64: captcha?['img_base64']?.toString(),
      );
    }
    final fields = MobileLoginContract.buildRequestDigitsFields(
      username: username,
      clientId: MobileLoginContract.clientId,
      smsType: smsType,
    );
    final body = await mobileLoginBodyEncoder.encode(fields);
    final response = await sendEncryptedLoginForm(
      MobileLoginContract.requestDigitsPath,
      body,
    );
    final success = response.isSuccess && response.jsonMap?['success'] == true;
    return MobileDigitsResult(
      response: response,
      sent: success,
      requiresCaptcha: false,
      message: success ? '验证码已发送' : '验证码发送失败：${response.failure.userMessage}',
    );
  }

  /// Submits the `grant_type=digits` contract. A failed response never
  /// replaces an existing guest/account session.
  Future<MobileSignInResult> signInWithDigits({
    required String username,
    required String digits,
    DateTime? now,
  }) async {
    if (!session.hasCompleteMobileContext) {
      await ensureGuestContext();
    }
    final epochSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final fields = MobileLoginContract.buildSignInFields(
      grant: MobileLoginGrant.digits,
      username: username,
      credential: digits,
      clientId: MobileLoginContract.clientId,
      clientSecret: MobileLoginContract.clientSecret,
      epochSeconds: epochSeconds,
    );
    final body = await mobileLoginBodyEncoder.encode(fields);
    final response = await sendEncryptedLoginForm(
      MobileLoginContract.signInPath,
      body,
    );
    return consumeAccountTokenResponse(
      response,
      successMessage: '登录成功',
      failurePrefix: '登录失败',
      verifyAccountProfile: true,
    );
  }

  /// Submits the official `grant_type=password` exchange used by the account
  /// form. It shares the same encrypted body, token validation and safe session
  /// commit path as the SMS flow.
  Future<MobileSignInResult> signInWithPassword({
    required String username,
    required String password,
    DateTime? now,
  }) async {
    if (!session.hasCompleteMobileContext) {
      await ensureGuestContext();
    }
    final epochSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final fields = MobileLoginContract.buildSignInFields(
      grant: MobileLoginGrant.password,
      username: username,
      credential: password,
      clientId: MobileLoginContract.clientId,
      clientSecret: MobileLoginContract.clientSecret,
      epochSeconds: epochSeconds,
    );
    final body = await mobileLoginBodyEncoder.encode(fields);
    final response = await sendEncryptedLoginForm(
      MobileLoginContract.signInPath,
      body,
    );
    return consumeAccountTokenResponse(
      response,
      successMessage: '登录成功',
      failurePrefix: '登录失败',
      verifyAccountProfile: true,
    );
  }

  /// Refreshes an account token with the same `grant_type=refresh_token`
  /// Token refresh exchange. Failure never clears or replaces the last stored
  /// account material.
  Future<MobileSignInResult> refreshAccountSession({DateTime? now}) async {
    final credentialRevisionAtStart = session.credentialRevision;
    final refreshTokenAtStart = session.refreshToken;
    final epochSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final fields = MobileLoginContract.buildSignInFields(
      grant: MobileLoginGrant.refreshToken,
      username: '',
      credential: refreshTokenAtStart,
      clientId: MobileLoginContract.clientId,
      clientSecret: MobileLoginContract.clientSecret,
      epochSeconds: epochSeconds,
    );
    final body = await mobileLoginBodyEncoder.encode(fields);
    final response = await sendEncryptedLoginForm(
      MobileLoginContract.signInPath,
      body,
    );
    return consumeAccountTokenResponse(
      response,
      successMessage: '登录已更新',
      failurePrefix: '登录状态更新失败',
      verifyAccountProfile: false,
      expectedCredentialRevision: credentialRevisionAtStart,
    );
  }

  Future<MobileSignInResult> consumeAccountTokenResponse(
    ApiResponse response, {
    required String successMessage,
    required String failurePrefix,
    required bool verifyAccountProfile,
    int? expectedCredentialRevision,
  }) async {
    final root = response.jsonMap;
    final error = response.error;
    if (!response.isSuccess || root == null) {
      return MobileSignInResult(
        response: response,
        signedIn: false,
        requiresVerification: error?['verification'] != null,
        message: '$failurePrefix：${response.failure.userMessage}',
        errorCode: response.businessCode,
        errorName: response.errorName.isEmpty ? null : response.errorName,
      );
    }
    final accessToken = root['access_token']?.toString().trim() ?? '';
    final refreshToken = root['refresh_token']?.toString().trim() ?? '';
    final tokenType = root['token_type']?.toString().trim() ?? 'Bearer';
    final expiresIn = ZhihuApiClient.positiveInt(root['expires_in']);
    if (accessToken.isEmpty || refreshToken.isEmpty || expiresIn == null) {
      return MobileSignInResult(
        response: response,
        signedIn: false,
        requiresVerification: false,
        message: '登录响应缺少 access_token、refresh_token 或 expires_in',
      );
    }
    final zCookie = zCookieFromTokenResponse(response);
    final accountUid = root['uid']?.toString().trim() ?? '';
    final accountUserId = root['user_id']?.toString().trim() ?? '';
    final verification = root['verification'];
    if (verifyAccountProfile) {
      final profileResponse = await verifyNewAccountToken(
        accessToken: accessToken,
        tokenType: tokenType,
        zCookie: zCookie,
      );
      final profile = profileResponse.jsonMap;
      if (!profileResponse.isSuccess || profile == null) {
        return MobileSignInResult(
          response: profileResponse,
          signedIn: false,
          requiresVerification: verification != null,
          message:
              '登录 Token 已返回，但账号资料验证失败：'
              '${profileResponse.failure.userMessage}',
          errorCode: profileResponse.businessCode,
          errorName: profileResponse.errorName.isEmpty
              ? null
              : profileResponse.errorName,
        );
      }
      final profileId = profile['id']?.toString().trim() ?? '';
      final profileUid = profile['uid']?.toString().trim() ?? '';
      if ((accountUid.isNotEmpty &&
              profileId.isNotEmpty &&
              accountUid != profileId) ||
          (accountUserId.isNotEmpty &&
              profileUid.isNotEmpty &&
              accountUserId != profileUid)) {
        return MobileSignInResult(
          response: profileResponse,
          signedIn: false,
          requiresVerification: verification != null,
          message: '登录 Token 与 /people/self 返回的账号身份不一致，已拒绝保存',
        );
      }
    }
    final committed = await session.saveAccountSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      udid: session.udid,
      expiresIn: Duration(seconds: expiresIn),
      tokenType: tokenType,
      zCookie: zCookie,
      uid: verifyAccountProfile ? accountUid : null,
      userId: verifyAccountProfile ? accountUserId : null,
      scope: verifyAccountProfile
          ? root['scope']?.toString().trim() ?? ''
          : null,
      unlockTicket: verifyAccountProfile
          ? root['unlock_ticket']?.toString().trim() ?? ''
          : null,
      lockInSeconds: verifyAccountProfile
          ? ZhihuApiClient.nonNegativeInt(root['lock_in']) ?? 0
          : null,
      expectedCredentialRevision: expectedCredentialRevision,
    );
    if (!committed) {
      // A logout, imported session, guest replacement, or newer account won
      // while this refresh was in flight. Do not let the stale response leak
      // its Set-Cookie value into a later login request either.
      loginCookie = '';
      return MobileSignInResult(
        response: response,
        signedIn: false,
        requiresVerification: false,
        message: '登录状态已发生变化，已忽略过期的刷新结果',
      );
    }
    loginCookie = '';
    return MobileSignInResult(
      response: response,
      signedIn: true,
      requiresVerification: verification != null,
      message: verification == null
          ? successMessage
          : '$successMessage；服务端同时要求完成账号安全验证',
    );
  }

  Future<ApiResponse> verifyNewAccountToken({
    required String accessToken,
    required String tokenType,
    required String zCookie,
  }) {
    final cookie = ZhihuApiClient.mergeCookieHeaders(
      session.cookie,
      loginCookie,
      zCookie.isEmpty ? '' : 'z_c0=$zCookie',
    );
    return sendMobileRaw(
      'GET',
      apiUri('/people/self'),
      headers: {
        'Authorization': '${tokenType.trim()} ${accessToken.trim()}',
        if (session.udid.isNotEmpty) 'x-udid': session.udid,
        if (cookie.isNotEmpty) 'Cookie': cookie,
      },
      body: null,
      debugProfile: 'login-account-profile-validation',
    );
  }

  String zCookieFromTokenResponse(ApiResponse response) {
    final cookie = response.jsonMap?['cookie'];
    if (cookie is Map) {
      final value = cookie['z_c0']?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final merged = ZhihuApiClient.mergeCookieHeaders(
      loginCookie,
      ZhihuApiClient.cookiePairsOnly(response.headers['set-cookie'] ?? ''),
    );
    for (final part in merged.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      if (part.substring(0, separator).trim() == 'z_c0') {
        return part.substring(separator + 1).trim();
      }
    }
    return '';
  }

  Future<ApiResponse> sendEncryptedLoginForm(
    String path,
    List<int> body,
  ) async {
    final uri = apiUri(path);
    final appInfo = await resolveAppInfo();
    final cookie = ZhihuApiClient.mergeCookieHeaders(
      session.cookie,
      loginCookie,
    );
    final sessionHeaders = session.requestHeaders(method: 'POST', uri: uri);
    var headers = <String, String>{
      ...baseHeaders,
      if (appInfo.isNotEmpty) 'x-app-za': appInfo,
      ...sessionHeaders,
      if (cookie.isNotEmpty) 'Cookie': cookie,
      'content-type': 'application/x-www-form-urlencoded',
      'x-b3-traceid': ZhihuApiClient.randomHex(32),
      'x-client-ri': ZhihuApiClient.epochSeconds(),
    };
    ZhihuApiClient.removeHeader(headers, 'accept');
    // Dart maps are case-sensitive while HTTP header names are not. Remove
    // every runtime spelling first so exactly one official protocol version
    // reaches the wire.
    ZhihuApiClient.removeHeader(headers, 'X-Zse-93');
    headers['X-Zse-93'] = MobileLoginContract.encryptVersion;
    // The encrypted form adds X-Zse-93 after encrypting the whole body and
    // deliberately skips X-Zse-96 for this request.
    ZhihuApiClient.removeHeader(headers, 'X-Zse-96');
    debugLogRequest('POST', uri, headers, body, profile: 'login-laes-body');
    for (final entry in headers.entries) {
      if (entry.value.contains('\n') || entry.value.contains('\r')) {
        throw ApiTransportException('${entry.key} 含非法换行');
      }
    }
    final stopwatch = Stopwatch()..start();
    final response = await transport.send(
      method: 'POST',
      uri: uri,
      headers: headers,
      body: body,
      maxResponseBytes: ZhihuApiClient.maxResponseBytes,
    );
    stopwatch.stop();
    debugLogResponse('POST', uri, response);
    unawaited(
      apiLogger.recordNetwork(
        method: 'POST',
        uri: uri,
        profile: 'login-laes-body',
        statusCode: response.statusCode,
        statusLabel: response.statusLabel,
        businessCode: response.businessCode,
        bodyBytes: response.bodyBytes,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
    await debugSink.recordExchange(
      method: 'POST',
      uri: uri,
      requestHeaders: headers,
      requestBody: body,
      response: response,
    );
    rememberLoginCookie(response);
    return response;
  }

  void rememberLoginCookie(ApiResponse response) {
    final rawCookie = response.jsonMap?['cookie'];
    final responseCookie = rawCookie is Map
        ? rawCookie.entries
              .where((entry) => entry.value != null)
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; ')
        : rawCookie?.toString() ?? '';
    final candidates = <String>[
      responseCookie,
      response.headers['set-cookie'] ?? '',
    ];
    loginCookie = ZhihuApiClient.mergeCookieHeaders(
      loginCookie,
      ZhihuApiClient.cookiePairsOnly(candidates[0]),
      ZhihuApiClient.cookiePairsOnly(candidates[1]),
    );
  }

  Future<void> refreshAccountSessionIfDue() async {
    if (!session.shouldRefreshAccountToken) return;
    final authorizationAtStart = session.authorization;
    final credentialRevisionAtStart = session.credentialRevision;
    final result = await refreshAccountSessionOnce();
    if (!result.signedIn) {
      if (result.response.businessCode == '100008') {
        if (await clearAccountSessionIfUnchanged(
          authorizationAtStart,
          credentialRevisionAtStart,
          reason: '账号 Token 刷新返回终止性失效码',
          source: 'proactive_account_refresh',
          statusCode: result.response.statusCode,
          businessCode: result.response.businessCode,
        )) {
          debugPrint(
            'account token refresh terminal code=100008; cleanup awaits user confirmation',
          );
        }
      } else {
        debugPrint('account token refresh retained previous session');
      }
    }
  }

  Future<MobileSignInResult> refreshAccountSessionOnce() async {
    final existing = accountRefresh;
    if (existing != null) return existing;
    final future = refreshAccountSession();
    accountRefresh = future;
    try {
      return await future;
    } finally {
      if (identical(accountRefresh, future)) accountRefresh = null;
    }
  }
}
