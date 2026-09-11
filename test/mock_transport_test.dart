import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api.dart';

class _MemorySession implements ApiSession {
  @override
  String authorization = '';
  @override
  String udid = '';
  @override
  String cookie = '';
  @override
  String msId = '';
  @override
  String sessionKind = '';
  @override
  String refreshToken = '';
  @override
  String accountUid = '';
  @override
  String accountUserId = '';
  @override
  DateTime? accessTokenExpiry;
  @override
  DateTime? accessTokenRefreshAt;
  @override
  int credentialRevision = 0;

  @override
  bool get hasAuthorization => authorization.isNotEmpty;

  @override
  bool get hasCompleteMobileContext =>
      authorization.isNotEmpty && udid.isNotEmpty;

  @override
  bool get hasAccountSession => sessionKind == 'account';

  @override
  bool get hasRefreshableAccountSession => sessionKind == 'account';

  @override
  bool get hasGuestSession => sessionKind == 'guest';

  @override
  bool get isAccessTokenExpired => false;

  @override
  bool get shouldRefreshAccountToken => false;

  @override
  bool get supportsPersistentApiSession => true;

  @override
  Map<String, String> requestHeaders({
    required String method,
    required Uri uri,
  }) {
    if (authorization.isEmpty) return const {};
    return {
      'Authorization': authorization,
      'x-udid': udid,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  @override
  Future<void> saveMsId(String value) async => msId = value;

  @override
  Future<void> saveGuestSession({
    required String accessToken,
    required String udid,
    String zCookie = '',
  }) async {
    authorization = accessToken;
    this.udid = udid;
    cookie = zCookie;
    sessionKind = 'guest';
    credentialRevision += 1;
  }

  @override
  Future<void> clearGuestSession() async {
    authorization = '';
    udid = '';
    cookie = '';
    sessionKind = '';
    credentialRevision += 1;
  }

  @override
  Future<bool> saveAccountSession({
    required String accessToken,
    required String refreshToken,
    required String udid,
    required Duration expiresIn,
    String tokenType = 'Bearer',
    String zCookie = '',
    String? uid,
    String? userId,
    String? scope,
    String? unlockTicket,
    int? lockInSeconds,
    int? expectedCredentialRevision,
  }) async => false;

  @override
  Future<bool> saveQrSession({
    required String cookie,
    required String udid,
    String? uid,
    String? userId,
  }) async => false;

  @override
  Future<void> clear() async {
    authorization = '';
    udid = '';
    cookie = '';
    sessionKind = '';
    credentialRevision += 1;
  }
}

class _MockTransport implements ApiTransport {
  _MockTransport(this.response);

  final ApiResponse response;
  int calls = 0;
  final requests = <({String method, Uri uri, Map<String, String> headers})>[];

  @override
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  }) async {
    calls += 1;
    requests.add((method: method, uri: uri, headers: headers));
    return response;
  }

  @override
  void close() {}
}

class _GuestBootstrapTransport implements ApiTransport {
  final calls = <({String method, Uri uri, Map<String, String> headers})>[];
  bool rejectNextRecommendation = false;
  int recommendationRejectionCode = 403;

  @override
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  }) async {
    calls.add((method: method, uri: uri, headers: headers));
    if (uri.path == '/topstory/recommend' && rejectNextRecommendation) {
      rejectNextRecommendation = false;
      final error = <String, Object?>{
        'code': recommendationRejectionCode,
        'need_login': true,
      };
      return ApiResponse(
        uri: uri,
        statusCode: 403,
        bodyBytes: 2,
        json: {'error': error},
        headers: const {},
      );
    }
    final json = switch (uri.path) {
      '/api/account/prod/init/new_flow_check' => const {
        'split_udid_guest_api': false,
      },
      '/api/account/prod/init/udid_guest' => const {'udid': 'guest-udid'},
      '/api/account/prod/guests/token' => const {
        'access_token': 'guest-access',
        'cookie': {'z_c0': 'guest-cookie'},
      },
      '/guest/self' => const {'id': 'guest'},
      _ => const {
        'data': <Object>[],
        'paging': {'is_end': true},
      },
    };
    return ApiResponse(
      uri: uri,
      statusCode: 200,
      bodyBytes: 2,
      json: json,
      headers: const {'content-type': 'application/json'},
    );
  }

  @override
  void close() {}
}

class _StaticCloudIdProvider implements ApiCloudIdProvider {
  @override
  Future<Map<String, Object?>> deviceInfo() async => const {};

  @override
  Future<String> appInfo() async => '';

  @override
  Future<String> localMsId() async => 'install-ms-id';

  @override
  Future<String> sign({
    required String body,
    required String requestTimestamp,
    String udid = '',
    String fallbackUdid = '',
  }) async => 'cloud-signature';
}

class _MemoryCache implements ApiResponseCache {
  final values = <String, ApiResponse>{};

  @override
  Future<ApiResponse?> read(String key) async => values[key];

  @override
  Future<void> write(String key, ApiResponse response) async {
    values[key] = response;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _PassthroughSigner extends XZseSigner {
  _PassthroughSigner();

  @override
  Future<Map<String, String>> signHeaders({
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async => Map<String, String>.of(headers);
}

ApiResponse _response(Uri uri, Object json) => ApiResponse(
  uri: uri,
  statusCode: 200,
  bodyBytes: 2,
  json: json,
  headers: const {'content-type': 'application/json'},
  rawBody: const <int>[123, 125],
);

void main() {
  test('public read uses the injected transport', () async {
    final uri = Uri.https('www.zhihu.com', '/api/v4/questions/42');
    final transport = _MockTransport(_response(uri, {'id': '42'}));
    final api = ZhihuApiClient(
      _MemorySession(),
      transport: transport,
      xZseSigner: _PassthroughSigner(),
    );

    final result = await api.publicWebGet('/api/v4/questions/42');

    expect(result.jsonMap?['id'], '42');
    expect(transport.calls, 1);
    expect(transport.requests.single.method, 'GET');
    expect(transport.requests.single.uri, uri);
  });

  test('cache boundary prevents a duplicate read', () async {
    final uri = Uri.https('api.zhihu.com', '/v4/questions/42');
    final transport = _MockTransport(_response(uri, {'id': '42'}));
    final cache = _MemoryCache();
    final api = ZhihuApiClient(
      _MemorySession(),
      transport: transport,
      xZseSigner: _PassthroughSigner(),
      cache: cache,
    );

    final first = await api.getUri(uri, cacheKey: 'question:42');
    final second = await api.getUri(uri, cacheKey: 'question:42');

    expect(first.jsonMap?['id'], '42');
    expect(second.jsonMap?['id'], '42');
    expect(transport.calls, 1);
    expect(cache.values, contains('question:42'));
  });

  test(
    'public home reads use the verified anonymous OAuth context first',
    () async {
      final session = _MemorySession();
      final transport = _GuestBootstrapTransport();
      final api = ZhihuApiClient(
        session,
        transport: transport,
        cloudIdProvider: _StaticCloudIdProvider(),
        xZseSigner: _PassthroughSigner(),
      );
      addTearDown(api.close);

      final recommendation = await api.getUri(
        api.recommendationFeedInitialUri(),
      );
      final hot = await api.getUri(api.hotListInitialUri());

      expect(recommendation.isSuccess, isTrue);
      expect(hot.isSuccess, isTrue);
      expect(transport.calls.map((call) => call.uri.path), [
        '/topstory/recommend',
        '/topstory/hot-lists/total',
      ]);
      expect(session.hasGuestSession, isFalse);
      expect(
        transport.calls[0].headers['Authorization'],
        ZhihuCloudProtocol.oauthAuthorization,
      );
      expect(
        transport.calls[1].headers['Authorization'],
        ZhihuCloudProtocol.oauthAuthorization,
      );
      expect(transport.calls[0].headers.containsKey('x-udid'), isFalse);
      expect(transport.calls[1].headers.containsKey('x-udid'), isFalse);
    },
  );

  test(
    'public home reads bootstrap Guest only after an OAuth boundary',
    () async {
      final session = _MemorySession();
      final transport = _GuestBootstrapTransport()
        ..rejectNextRecommendation = true;
      final api = ZhihuApiClient(
        session,
        transport: transport,
        cloudIdProvider: _StaticCloudIdProvider(),
        xZseSigner: _PassthroughSigner(),
      );
      addTearDown(api.close);

      final response = await api.getUri(api.recommendationFeedInitialUri());

      expect(response.isSuccess, isTrue);
      expect(transport.calls.map((call) => call.uri.path), [
        '/topstory/recommend',
        '/api/account/prod/init/new_flow_check',
        '/api/account/prod/init/udid_guest',
        '/api/account/prod/guests/token',
        '/guest/self',
        '/topstory/recommend',
      ]);
      expect(
        transport.calls.first.headers['Authorization'],
        ZhihuCloudProtocol.oauthAuthorization,
      );
      expect(transport.calls.last.headers['Authorization'], 'guest-access');
      expect(session.hasGuestSession, isTrue);
    },
  );

  test(
    'public home reads refresh a stale guest after generic login boundary',
    () async {
      final session = _MemorySession()
        ..authorization = 'Bearer stale-guest'
        ..udid = 'stale-udid'
        ..sessionKind = 'guest';
      final transport = _GuestBootstrapTransport();
      transport.rejectNextRecommendation = true;
      final api = ZhihuApiClient(
        session,
        transport: transport,
        cloudIdProvider: _StaticCloudIdProvider(),
        xZseSigner: _PassthroughSigner(),
      );
      addTearDown(api.close);

      final response = await api.getUri(api.recommendationFeedInitialUri());

      expect(response.isSuccess, isTrue);
      expect(session.hasGuestSession, isTrue);
      expect(session.authorization, 'guest-access');
      expect(transport.calls.map((call) => call.uri.path), [
        '/topstory/recommend',
        '/api/account/prod/init/new_flow_check',
        '/api/account/prod/init/udid_guest',
        '/api/account/prod/guests/token',
        '/guest/self',
        '/topstory/recommend',
      ]);
    },
  );

  test(
    'public home reads keep the Guest state during a network challenge',
    () async {
      final session = _MemorySession()
        ..authorization = 'Bearer stale-guest'
        ..udid = 'stale-udid'
        ..sessionKind = 'guest';
      final transport = _GuestBootstrapTransport()
        ..rejectNextRecommendation = true
        ..recommendationRejectionCode = 40352;
      final api = ZhihuApiClient(
        session,
        transport: transport,
        cloudIdProvider: _StaticCloudIdProvider(),
        xZseSigner: _PassthroughSigner(),
      );
      addTearDown(api.close);

      final response = await api.getUri(api.recommendationFeedInitialUri());

      expect(response.isSuccess, isFalse);
      expect(transport.calls.map((call) => call.uri.path), [
        '/topstory/recommend',
      ]);
      expect(session.hasGuestSession, isTrue);
      expect(session.authorization, 'Bearer stale-guest');
      final failure = ApiFailure.forAnonymousRead(response);
      expect(failure.kind, ApiFailureKind.networkChallenge);
      expect(failure.title, '需要验证网络环境');
      expect(failure.retryable, isTrue);
    },
  );

  test('response normalizes nested business errors', () {
    final response = _response(Uri.https('api.zhihu.com', '/v4/test'), {
      'error': {'code': 101, 'message': 'expired'},
    });

    expect(response.businessCode, '101');
    expect(response.serverMessage, 'expired');
    expect(response.failure.kind, ApiFailureKind.authentication);
    expect(
      accountAuthenticationAction(
        ApiResponse(
          uri: response.uri,
          statusCode: 401,
          bodyBytes: response.bodyBytes,
          json: response.json,
          headers: response.headers,
        ),
      ),
      AccountAuthenticationAction.logout,
    );
  });

  test('anonymous public boundary is retryable and never asks for account', () {
    final response = ApiResponse(
      uri: Uri.https('api.zhihu.com', '/topstory/recommend'),
      statusCode: 403,
      bodyBytes: 2,
      json: const {
        'error': {'code': 403, 'need_login': true},
      },
      headers: const {},
    );

    final failure = ApiFailure.forAnonymousRead(response);

    expect(failure.kind, ApiFailureKind.guestContext);
    expect(failure.title, '暂时无法加载');
    expect(failure.detail, '匿名内容服务暂时不可用，请稍后重试。');
    expect(failure.retryable, isTrue);
    expect(ApiFailure.from(failure), same(failure));
  });
}
