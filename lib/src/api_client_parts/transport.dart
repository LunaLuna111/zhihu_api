import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../api_client.dart';

extension ZhihuApiClientTransport on ZhihuApiClient {
  Uri publicWebUri(String path, {Map<String, Object?> query = const {}}) {
    final uri = uriForHost(ZhihuApiClient.publicWebHost, path, query: query);
    if (!uri.path.startsWith('/api/v4/')) {
      throw const ApiTransportException('公开 Web 回退只允许 /api/v4/ 读取路由');
    }
    return uri;
  }

  Uri uriForHost(
    String host,
    String path, {
    Map<String, Object?> query = const {},
  }) {
    final initial = Uri.parse(
      'https://$host/${path.replaceFirst(RegExp(r'^/+'), '')}',
    );
    final pairs = <String, String>{};
    initial.queryParametersAll.forEach((key, values) {
      if (values.isNotEmpty) pairs[key] = values.last;
    });
    query.forEach((key, value) {
      if (value != null) pairs[key] = value.toString();
    });
    return initial.replace(queryParameters: pairs.isEmpty ? null : pairs);
  }

  Uri validatePagingUri(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != ZhihuApiClient.apiHost ||
        uri.hasPort && uri.port != 443) {
      throw const ApiTransportException('拒绝跟随非 api.zhihu.com 的分页地址');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const ApiTransportException('分页地址不得包含 user info');
    }
    return uri;
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    String? cacheKey,
  }) => getUri(
    apiUri(path, query: query),
    headers: headers,
    cacheKey: cacheKey,
  );

  /// Anonymous, read-only Web API fallback for content that Zhihu exposes
  /// without a mobile guest/account context. It deliberately carries no
  /// session values or mobile x-app-* headers because the two profiles have
  /// different server-side authorization behavior.
  Future<ApiResponse> publicWebGet(
    String path, {
    Map<String, Object?> query = const {},
  }) => send('GET', publicWebUri(path, query: query), headers: const {});

  /// Fetches the same read-only video metadata used by the official player
  /// when an answer only contains a Lens ID or its embedded playlist expired.
  /// This profile is intentionally anonymous: no account/guest token, cookie,
  /// UDID or other persisted client identifier is attached.
  Uri publicLensVideoUri(String videoId) {
    final normalized = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(normalized)) {
      throw const ApiTransportException('视频 ID 无效');
    }
    return Uri.https(ZhihuApiClient.lensHost, '/api/v4/videos/$normalized');
  }

  Future<ApiResponse> publicLensVideoGet(String videoId) =>
      send('GET', publicLensVideoUri(videoId), headers: const {});

  Future<ApiResponse> getUri(
    Uri uri, {
    Map<String, String> headers = const {},
    String? cacheKey,
  }) async {
    final validated = validatePagingUri(uri.toString());
    if (cacheKey != null && cacheKey.trim().isNotEmpty) {
      final cached = await cache.read(cacheKey.trim());
      if (cached != null) return cached;
    }
    final response = await send('GET', validated, headers: headers);
    if (cacheKey != null && cacheKey.trim().isNotEmpty && response.isSuccess) {
      await cache.write(cacheKey.trim(), response);
    }
    return response;
  }

  /// Debug-build interoperability probe. When explicitly enabled with
  /// `--dart-define=ZH_SALT_AUTH_RELAY=true`, a local test proxy may replace
  /// this marker with an exact official in-memory request context. No account
  /// material enters Flutter storage or the release build.
  Future<ApiResponse> getSaltUri(Uri uri) {
    debugPrint(
      '[zhihu-api] salt-auth-relay enabled=${ZhihuApiClient.debugSaltAuthorizationRelay}',
    );
    return getUri(
      uri,
      headers: ZhihuApiClient.debugSaltAuthorizationRelay
          ? const {'x-zh-debug-auth-relay': 'salt'}
          : const {},
    );
  }

  Future<ApiResponse> debugGetUriWithMinimalMobileHeaders(
    Uri uri, {
    Map<String, String> headers = const {},
    bool includeAuthorization = true,
    bool includeUdid = true,
    bool includeCookie = true,
    String? debugProfile,
  }) async {
    if (!debugSink.enabled) {
      throw const ApiTransportException(
        'minimal mobile header probe is debug-only',
      );
    }
    if (!session.hasCompleteMobileContext) {
      await ensureGuestContext();
    }
    final resolvedProfile =
        debugProfile ??
        'minimal-mobile'
            '${includeAuthorization ? '' : '-no-auth'}'
            '${includeUdid ? '' : '-no-udid'}'
            '${includeCookie ? '' : '-no-cookie'}';
    return sendMobileRaw(
      'GET',
      validatePagingUri(uri.toString()),
      headers: {
        'Accept': 'application/json',
        'User-Agent': ZhihuApiClient.appUserAgent,
        if (includeAuthorization && session.authorization.isNotEmpty)
          'Authorization': session.authorization,
        if (includeUdid && session.udid.isNotEmpty) 'x-udid': session.udid,
        if (includeCookie && session.cookie.isNotEmpty)
          'Cookie': session.cookie,
        ...headers,
      },
      body: null,
      includeBaseHeaders: false,
      debugProfile: resolvedProfile,
    );
  }

  /// Debug-only anonymous control request matching the official clean-start
  /// profile observed before a guest/CloudID context exists. This deliberately
  /// excludes every persisted session header so a stale imported guest cannot
  /// mask the OAuth-first result during an A/B probe.
  Future<ApiResponse> debugGetUriWithOauthOnly(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (!debugSink.enabled) {
      throw const ApiTransportException('OAuth-only probe is debug-only');
    }
    return sendMobileRaw(
      'GET',
      validatePagingUri(uri.toString()),
      headers: {
        'Accept': 'application/json',
        'User-Agent': ZhihuApiClient.appUserAgent,
        'Authorization': ZhihuCloudProtocol.oauthAuthorization,
        ...headers,
      },
      body: null,
      includeBaseHeaders: false,
      debugProfile: 'minimal-mobile-oauth-only',
    );
  }

  Future<ApiResponse> postJson(
    String path, {
    Map<String, Object?> query = const {},
    required Object jsonBody,
    Map<String, String> headers = const {},
  }) {
    final bytes = utf8.encode(jsonEncode(jsonBody));
    return send(
      'POST',
      apiUri(path, query: query),
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
      body: bytes,
    );
  }

  Future<ApiResponse> postJsonUri(
    Uri uri, {
    required Object jsonBody,
    Map<String, String> headers = const {},
  }) {
    final bytes = utf8.encode(jsonEncode(jsonBody));
    return send(
      'POST',
      validatePagingUri(uri.toString()),
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
      body: bytes,
    );
  }

  Uri accountSelfProfileUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/people/self');

  Uri accountSelfProfileV2Uri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/people/self/profile_v2');

  /// Updates the basic profile fields accepted by the profile service. Empty
  /// strings are retained because clearing a
  /// headline or description is a valid edit.
  Future<ApiResponse> updateAccountProfile(Map<String, String> fields) {
    requireWriteSession();
    const allowed = {
      'name',
      'headline',
      'description',
      'birthday',
      'gender',
      'business',
    };
    if (fields.isEmpty || fields.keys.any((key) => !allowed.contains(key))) {
      throw const ApiTransportException('个人资料字段无效');
    }
    final body = utf8.encode(MobileLoginBodyEncoder.formEncode(fields));
    return send(
      'PUT',
      accountSelfProfileUri(),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  /// Updates the structured profile arrays using the exact Retrofit field
  /// names recovered from the official editor.
  Future<ApiResponse> updateAccountProfileV2({
    required List<Map<String, Object?>> educations,
    required List<Map<String, Object?>> employments,
    required List<Map<String, Object?>> locations,
  }) {
    requireWriteSession();
    final fields = <String, String>{
      'educations': jsonEncode(educations),
      'employments': jsonEncode(employments),
      'locations': jsonEncode(locations),
    };
    final body = utf8.encode(MobileLoginBodyEncoder.formEncode(fields));
    return send(
      'PUT',
      accountSelfProfileV2Uri(),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  /// Uploads one profile image through the same multipart endpoint used by
  /// the official feedback/profile image pipeline. The returned object is an
  /// `Image` payload containing at least `src`/`url` and, for cover images,
  /// its content `hash`.
  Future<ApiResponse> uploadProfileImage({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) {
    requireWriteSession();
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const ApiTransportException('图片大小必须在 20 MB 以内');
    }
    final normalizedMime = mimeType.trim().toLowerCase();
    if (!RegExp(r'^image/[a-z0-9.+-]+$').hasMatch(normalizedMime)) {
      throw const ApiTransportException('图片格式无效');
    }
    final safeName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    final normalizedName = safeName.isEmpty ? 'profile.jpg' : safeName;
    final boundary =
        '----zhihu-profile-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final builder = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$normalizedName"\r\n'
          'Content-Type: $normalizedMime\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return send(
      'POST',
      apiUri('/upload_image'),
      headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      body: builder.takeBytes(),
    );
  }

  /// Commits the URL returned by `/upload_image` to the current account.
  Future<ApiResponse> updateAccountAvatar(String avatarUrl) {
    requireWriteSession();
    final normalized = avatarUrl.trim();
    if (normalized.isEmpty || normalized.length > 4096) {
      throw const ApiTransportException('头像地址无效');
    }
    final body = utf8.encode(
      MobileLoginBodyEncoder.formEncode({'avatar_url': normalized}),
    );
    return send(
      'POST',
      apiUri('/people/self/avatar'),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }

  /// Commits the uploaded image hash as the account's home-page cover.
  Future<ApiResponse> updateAccountCover(String coverHash) {
    requireWriteSession();
    final normalized = coverHash.trim();
    if (normalized.isEmpty || normalized.length > 512) {
      throw const ApiTransportException('主页背景图片哈希无效');
    }
    final body = utf8.encode(
      MobileLoginBodyEncoder.formEncode({'cover_hash': normalized}),
    );
    return send(
      'PUT',
      accountSelfProfileUri(),
      headers: const {
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
    );
  }
}
