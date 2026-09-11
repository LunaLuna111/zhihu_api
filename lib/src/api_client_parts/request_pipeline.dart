import 'dart:async';

import '../api_client.dart';

extension ZhihuApiClientRequestPipeline on ZhihuApiClient {
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
    bool allowAccountRecovery = true,
    bool allowGuestRecovery = true,
    bool allowOauthGuestFallback = true,
  }) async {
    final isMobileApi =
        uri.scheme == 'https' &&
        uri.host == ZhihuApiClient.apiHost &&
        (!uri.hasPort || uri.port == 443) &&
        uri.userInfo.isEmpty;
    final isPublicWeb =
        uri.scheme == 'https' &&
        uri.host == ZhihuApiClient.publicWebHost &&
        (!uri.hasPort || uri.port == 443) &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/api/v4/');
    final isPublicLensVideo =
        uri.scheme == 'https' &&
        uri.host == ZhihuApiClient.lensHost &&
        (!uri.hasPort || uri.port == 443) &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        RegExp(r'^/api/v4/videos/[A-Za-z0-9_-]{1,128}$').hasMatch(uri.path);
    final isMobileWebMutation =
        isPublicWeb &&
        method == 'DELETE' &&
        body == null &&
        RegExp(r'^/api/v4/comment_v5/comment/\d+$').hasMatch(uri.path);
    if (isMobileApi && uri.path != MobileLoginContract.signInPath) {
      await refreshAccountSessionIfDue();
    }
    if (!isMobileApi && !isPublicWeb && !isPublicLensVideo) {
      throw const ApiTransportException('只允许已审核的知乎 HTTPS API host/path');
    }
    if (isPublicWeb &&
        !isMobileWebMutation &&
        (method != 'GET' || body != null || headers.isNotEmpty)) {
      throw const ApiTransportException('公开 Web 回退仅允许无自定义 Header 的 GET');
    }
    if (isPublicLensVideo &&
        (method != 'GET' || body != null || headers.isNotEmpty)) {
      throw const ApiTransportException('Lens 视频元数据仅允许匿名 GET');
    }
    final usesMobileProfile = isMobileApi || isMobileWebMutation;
    final appInfo = usesMobileProfile ? await resolveAppInfo() : '';
    final oauthFirst = usesMobileProfile && shouldTryOauthFirst(method);
    if (usesMobileProfile && shouldAutoBootstrap(method, uri)) {
      await ensureGuestContext();
    }
    final hasAccountSessionAtSend = session.hasRefreshableAccountSession;
    final accountAuthorizationAtSend = hasAccountSessionAtSend
        ? session.authorization
        : null;
    final accountCredentialRevisionAtSend = hasAccountSessionAtSend
        ? session.credentialRevision
        : null;
    final guestAuthorizationAtSend = session.hasGuestSession
        ? session.authorization
        : null;
    final sessionHeaders = usesMobileProfile
        ? session.requestHeaders(method: method, uri: uri)
        : const <String, String>{};
    Map<String, String> merged = usesMobileProfile
        ? {
            ...baseHeaders,
            ...officialRouteHeaders(uri),
            if (appInfo.isNotEmpty) 'x-app-za': appInfo,
            'Authorization': ZhihuCloudProtocol.oauthAuthorization,
            ...sessionHeaders,
            ...headers,
          }
        : {
            'accept': 'application/json',
            'user-agent': ZhihuApiClient.appUserAgent,
          };
    if (usesMobileProfile) {
      // Dart maps compare strings case-sensitively while HTTP field names do
      // not. Collapse e.g. base `user-agent` plus a contract `User-Agent`
      // before signing and handing the request to any transport.
      merged = ZhihuApiClient.canonicalizeHeaders(merged);
      try {
        merged = await xZseSigner.signHeaders(
          uri: uri,
          headers: merged,
          body: body,
        );
      } on ApiTransportException {
        rethrow;
      } on Object catch (error) {
        // Non-Android previews and incomplete native builds keep the exact
        // manual signature fallback from SessionStore, if one matched.
        debugPrint('x-zse unavailable=${error.runtimeType}; using fallback');
      }
    }
    final requestProfile = isMobileApi
        ? (oauthFirst ? 'mobile-oauth-first' : 'mobile-base')
        : isMobileWebMutation
        ? 'mobile-www-mutation'
        : isPublicLensVideo
        ? 'public-lens-video'
        : 'public-web';
    debugLogRequest(method, uri, merged, body, profile: requestProfile);
    for (final entry in merged.entries) {
      if (entry.value.contains('\n') || entry.value.contains('\r')) {
        throw ApiTransportException('${entry.key} 含非法换行');
      }
    }
    final stopwatch = Stopwatch()..start();
    late final ApiResponse response;
    try {
      response = await transport.send(
        method: method,
        uri: uri,
        headers: merged,
        body: body,
        maxResponseBytes: ZhihuApiClient.maxResponseBytes,
      );
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      unawaited(
        apiLogger.recordNetwork(
          method: method,
          uri: uri,
          profile: requestProfile,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: error.runtimeType.toString(),
        ),
      );
      unawaited(
        apiLogger.recordError(
          error,
          stackTrace,
          message: '网络请求异常',
          category: 'network',
        ),
      );
      rethrow;
    }
    stopwatch.stop();
    debugLogResponse(method, uri, response);
    unawaited(
      apiLogger.recordNetwork(
        method: method,
        uri: uri,
        profile: requestProfile,
        statusCode: response.statusCode,
        statusLabel: response.statusLabel,
        businessCode: response.businessCode,
        bodyBytes: response.bodyBytes,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
    unawaited(
      apiLogger.record(
        category: 'performance',
        level: 'info',
        message: '接口耗时',
        details: {
          'method': method,
          'url': sanitizeUri(uri),
          'duration_ms': stopwatch.elapsedMilliseconds,
          'status_code': response.statusCode,
        },
      ),
    );
    await debugSink.recordExchange(
      method: method,
      uri: uri,
      requestHeaders: merged,
      requestBody: body,
      response: response,
    );
    if (isPublicLensVideo) {
      // An anonymous media metadata failure must never trigger account/guest
      // recovery traffic or mutate the signed-in session as a side effect.
      return response;
    }
    if (isAnonymousNetworkChallenge(uri, response)) {
      // 40352 is a server-side network verification challenge, not an
      // expired account or Guest credential. Retrying with another bearer
      // token only repeats the challenge and can erase a usable Guest state.
      return response;
    }
    if (shouldRetryFreshGuestActivation(method, response)) {
      freshGuestRetryRemaining -= 1;
      freshGuestRetryAttempt += 1;
      final delay = retryPolicy.delayForFreshGuestAttempt(
        freshGuestRetryAttempt,
      );
      debugPrint(
        'fresh-guest ${response.statusLabel}; activation retry '
        '$freshGuestRetryAttempt/${retryPolicy.freshGuestMaxAttempts} '
        'after ${delay.inMilliseconds}ms',
      );
      await Future<void>.delayed(delay);
      return send(method, uri, headers: headers, body: body);
    }
    if (oauthFirst &&
        guestAuthorizationAtSend == null &&
        allowOauthGuestFallback &&
        shouldRetryGetWithGuest(response)) {
      try {
        await ensureGuestContext();
        debugPrint(
          'oauth-first ${response.statusLabel}; retrying GET once with guest',
        );
        return send(
          method,
          uri,
          headers: headers,
          body: body,
          // Public feed reads may still reject a newly issued anonymous
          // context while the content edge propagates it. Keep one bounded
          // guest recovery pass for those routes; account-scoped reads retain
          // the historical single OAuth -> guest retry.
          allowGuestRecovery: isAnonymousFeedRead(uri),
        );
      } on ApiTransportException catch (error) {
        debugPrint('oauth-first guest retry unavailable=${error.message}');
      } on Object catch (error) {
        debugPrint('oauth-first guest retry unavailable=${error.runtimeType}');
      }
    }
    if (allowGuestRecovery && guestAuthorizationAtSend != null) {
      final recovered = await recoverGuestResponse(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        response: response,
        guestAuthorizationAtSend: guestAuthorizationAtSend,
      );
      if (recovered != null) return recovered;
    }
    if (allowAccountRecovery && accountAuthorizationAtSend != null) {
      final recovered = await recoverAccountResponse(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        response: response,
        accountAuthorizationAtSend: accountAuthorizationAtSend,
        accountCredentialRevisionAtSend: accountCredentialRevisionAtSend!,
      );
      if (recovered != null) return recovered;
    }
    return response;
  }

  Future<ApiResponse?> recoverGuestResponse({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required ApiResponse response,
    required String guestAuthorizationAtSend,
  }) async {
    if (!isRejectedGuestContext(method, uri, response)) return null;
    final retryWithOauthOnly = response.businessCode == '40350';
    if (session.authorization == guestAuthorizationAtSend) {
      try {
        await refreshRejectedGuestOnce(
          guestAuthorizationAtSend,
          bootstrapReplacement: !retryWithOauthOnly,
        );
      } on ApiTransportException catch (error) {
        debugPrint('guest recovery unavailable=${error.message}');
        return null;
      } on Object catch (error) {
        debugPrint('guest recovery unavailable=${error.runtimeType}');
        return null;
      }
    }
    if (retryWithOauthOnly) {
      if (session.hasGuestSession &&
          session.authorization == guestAuthorizationAtSend) {
        return null;
      }
      debugPrint(
        'guest channel rejected; retrying GET once with OAuth only and the '
        'same device seed',
      );
      return send(
        method,
        uri,
        headers: headers,
        body: body,
        allowGuestRecovery: false,
        allowOauthGuestFallback: false,
      );
    }
    // Another concurrent request may already have replaced the rejected
    // guest. Retry only when the active state is still anonymous and differs
    // from the exact credential that produced this response.
    if (!session.hasGuestSession ||
        session.authorization == guestAuthorizationAtSend) {
      return null;
    }
    debugPrint(
      'guest recovery succeeded; retrying GET once with the same device seed',
    );
    return send(
      method,
      uri,
      headers: headers,
      body: body,
      allowGuestRecovery: false,
    );
  }

  bool isRejectedGuestContext(String method, Uri uri, ApiResponse response) {
    if (method != 'GET') return false;
    if (isAnonymousNetworkChallenge(uri, response)) return false;
    final code = response.businessCode;
    final knownGuestRejection =
        code == '40350' ||
        code == '40353' ||
        code == '10003' ||
        (response.statusCode == 401 && code == '100');
    if (knownGuestRejection) return true;
    // The public feed endpoints can answer with a generic 401/403 (or a
    // `need_login` business flag) when the bearer guest context is stale or
    // has not propagated to the content edge. This is an anonymous-context
    // rejection, not proof that an account is required. Limit the broader
    // retry to the three known public read routes so account-only reads such
    // as following/favorites keep their real login boundary.
    return isAnonymousFeedRead(uri) &&
        (response.statusCode == 401 ||
            response.statusCode == 403 ||
            code == '101' ||
            code == '401' ||
            code == '403' ||
            response.needLogin);
  }

  Future<void> refreshRejectedGuestOnce(
    String expectedAuthorization, {
    required bool bootstrapReplacement,
  }) async {
    final existing = guestRecovery;
    if (existing != null) return existing;
    final started = replaceRejectedGuest(
      expectedAuthorization,
      bootstrapReplacement: bootstrapReplacement,
    );
    guestRecovery = started;
    try {
      await started;
    } finally {
      guestRecovery = null;
    }
  }

  Future<void> replaceRejectedGuest(
    String expectedAuthorization, {
    required bool bootstrapReplacement,
  }) async {
    if (!session.hasGuestSession ||
        session.authorization != expectedAuthorization) {
      return;
    }
    debugPrint(
      'guest context ${session.authorization.length} chars rejected; '
      'refreshing credentials without rotating the device seed',
    );
    freshGuestRetryDeadline = null;
    freshGuestRetryRemaining = 0;
    freshGuestRetryAttempt = 0;
    await session.clearGuestSession();
    if (bootstrapReplacement) await ensureGuestContext();
  }

  Future<ApiResponse?> recoverAccountResponse({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required ApiResponse response,
    required String accountAuthorizationAtSend,
    required int accountCredentialRevisionAtSend,
  }) async {
    final action = accountAuthenticationAction(response);
    if (action == AccountAuthenticationAction.none) return null;

    // A delayed response from an old account must not mutate a newer session.
    if (!session.hasRefreshableAccountSession ||
        session.authorization != accountAuthorizationAtSend ||
        session.credentialRevision != accountCredentialRevisionAtSend) {
      debugPrint(
        'account rejection ignored because the active session changed',
      );
      return null;
    }
    if (action == AccountAuthenticationAction.logout) {
      // Some optional/legacy surfaces return code 101 when that particular
      // contract is unavailable to an otherwise valid account. Only the
      // identity endpoint is authoritative enough to erase a freshly
      // verified, persisted login session.
      if (!isAuthoritativeIdentityRejection(method, uri, response)) {
        debugPrint(
          'non-authoritative account rejection retained session '
          '${uri.path} ${response.statusLabel}',
        );
        unawaited(
          apiLogger.record(
            category: 'app',
            level: 'warning',
            message: '已拦截非权威接口清除登录状态',
            details: {
              'method': method,
              'url': sanitizeUri(uri),
              'status_code': response.statusCode,
              'business_code': response.businessCode,
              'credential_revision': accountCredentialRevisionAtSend,
            },
          ),
        );
        return null;
      }
      // A single identity response can still be produced by a stale edge or
      // a partially rolled-out API contract. Confirm it with the official
      // token refresh endpoint before deleting durable credentials.
      try {
        final result = await refreshAccountSessionOnce();
        if (result.signedIn) {
          return method == 'GET'
              ? send(
                  method,
                  uri,
                  headers: headers,
                  body: body,
                  allowAccountRecovery: false,
                )
              : null;
        }
        if (result.response.businessCode != '100008') {
          unawaited(
            apiLogger.record(
              category: 'app',
              level: 'warning',
              message: '身份接口异常但刷新未确认失效，保留登录状态',
              details: {
                'identity_status': response.statusCode,
                'identity_code': response.businessCode,
                'refresh_status': result.response.statusCode,
                'refresh_code': result.response.businessCode,
              },
            ),
          );
          return null;
        }
      } on Object catch (error, stackTrace) {
        unawaited(
          apiLogger.recordError(
            error,
            stackTrace,
            message: '身份确认刷新失败，已保留登录状态',
            category: 'app',
          ),
        );
        return null;
      }
      if (await clearAccountSessionIfUnchanged(
        accountAuthorizationAtSend,
        accountCredentialRevisionAtSend,
      )) {
        debugPrint(
          'account logout confirmed by terminal refresh; credentials cleared',
        );
      }
      return null;
    }

    debugPrint(
      'account passive refresh ${response.statusLabel}; refreshing token',
    );
    try {
      final result = await refreshAccountSessionOnce();
      if (result.signedIn) {
        if (method == 'GET') {
          return send(
            method,
            uri,
            headers: headers,
            body: body,
            allowAccountRecovery: false,
          );
        }
        return null;
      }
      // The official App logs out after any HTTP refresh failure triggered by
      // a passive 401. Transport exceptions retain the session and land in the
      // catch block below, so an offline device is never mistaken for logout.
      if (authenticationPolicy.shouldClearAfterRefreshFailure(
        result.response,
      )) {
        if (await clearAccountSessionIfUnchanged(
          accountAuthorizationAtSend,
          accountCredentialRevisionAtSend,
        )) {
          debugPrint(
            'account passive refresh rejected '
            '${result.response.statusLabel}; credentials cleared',
          );
        }
      }
    } on ApiTransportException catch (error) {
      debugPrint(
        'account passive refresh transport failure retained session='
        '${error.message}',
      );
    } on Object catch (error) {
      debugPrint(
        'account passive refresh unavailable=${error.runtimeType}; '
        'retained session',
      );
    }
    return null;
  }

  bool isAuthoritativeIdentityRejection(
    String method,
    Uri uri,
    ApiResponse response,
  ) {
    return authenticationPolicy.isAuthoritativeIdentityRejection(
      method: method,
      uri: uri,
      response: response,
      apiHost: ZhihuApiClient.apiHost,
    );
  }

  Future<bool> clearAccountSessionIfUnchanged(
    String expectedAuthorization,
    int expectedCredentialRevision,
  ) async {
    if (!session.hasRefreshableAccountSession ||
        session.authorization != expectedAuthorization ||
        session.credentialRevision != expectedCredentialRevision) {
      return false;
    }
    final existing = accountLogout;
    if (existing != null) {
      await existing;
      return false;
    }
    final future = session.clear();
    accountLogout = future;
    try {
      await future;
      return true;
    } finally {
      if (identical(accountLogout, future)) accountLogout = null;
    }
  }

  bool shouldTryOauthFirst(String method) {
    if (method != 'GET' ||
        !session.supportsPersistentApiSession ||
        session.hasCompleteMobileContext) {
      return false;
    }
    final authorization = session.authorization.trim();
    return authorization.isEmpty ||
        authorization.toLowerCase().startsWith('oauth ');
  }

  bool shouldRetryGetWithGuest(ApiResponse response) =>
      retryPolicy.shouldRetryGetWithGuest(response);

  /// Routes which are readable without a Zhihu account but may still need a
  /// mobile Guest context for the Android API profile. Keeping this contract
  /// explicit prevents a generic 401/403 from turning every anonymous read
  /// into a login prompt or from retrying account-only endpoints forever.
  bool isAnonymousFeedRead(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == ZhihuApiClient.apiHost &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      const {
        '/topstory/recommend',
        '/topstory/hot-lists/total',
        '/km-vip-zhihu-web/vip_tab/svip_story',
      }.contains(uri.path);

  bool isAnonymousNetworkChallenge(Uri uri, ApiResponse response) {
    if (!isAnonymousFeedRead(uri)) return false;
    return response.businessCode == '40352' ||
        response.serverMessage.contains('网络环境存在异常');
  }

  bool shouldRetryFreshGuestActivation(String method, ApiResponse response) {
    final deadline = freshGuestRetryDeadline;
    return retryPolicy.shouldRetryFreshGuestActivation(
      method: method,
      response: response,
      session: session,
      remainingAttempts: freshGuestRetryRemaining,
      deadline: deadline,
      now: DateTime.now(),
    );
  }

  bool shouldAutoBootstrap(String method, Uri uri) {
    if (!session.supportsPersistentApiSession ||
        session.hasCompleteMobileContext) {
      return false;
    }
    final authorization = session.authorization.trim();
    if (authorization.isNotEmpty &&
        !authorization.toLowerCase().startsWith('oauth ')) {
      return false;
    }
    // Public home reads are anonymous by contract. Keep the verified clean
    // start profile (static OAuth + per-request X-Zse) for the first GET; if
    // an endpoint actually needs a mobile Guest context, the response path
    // below establishes Guest and retries once. A 40352 network challenge is
    // handled before that recovery path, so it cannot cause token churn.
    if (method == 'GET') return false;
    return uri.path != '/api/account/prod/init/udid_guest' &&
        uri.path != '/api/account/prod/guests/token';
  }

  Future<void> ensureGuestContext() async {
    final existing = guestBootstrap;
    if (existing != null) return existing;
    if (session.hasGuestSession) return;
    final started = bootstrapGuestContext();
    guestBootstrap = started;
    try {
      await started;
    } finally {
      guestBootstrap = null;
    }
  }
}
