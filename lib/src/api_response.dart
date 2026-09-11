import 'api_exceptions.dart';

export 'api_exceptions.dart';

class ApiResponse {
  const ApiResponse({
    required this.uri,
    required this.statusCode,
    required this.bodyBytes,
    required this.json,
    required this.headers,
    this.rawBody = const <int>[],
  });

  final Uri uri;
  final int statusCode;
  final int bodyBytes;
  final Object? json;
  final Map<String, String> headers;
  final List<int> rawBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? get jsonMap {
    final value = json;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return _stringMap(value);
    return null;
  }

  Map<String, dynamic>? get error {
    final root = jsonMap;
    if (root == null) return null;
    final value = root['error'];
    if (value is Map) return _stringMap(value);
    final data = root['data'];
    if (data is Map) {
      final nested = data['error'];
      if (nested is Map) return _stringMap(nested);
    }
    if (_containsErrorFields(root)) return root;
    return null;
  }

  /// Business code returned by Zhihu. Responses observed across the App use
  /// all three spellings below, and the value can be either a JSON number or a
  /// string. The UI and callers consume one normalized string.
  String? get businessCode {
    for (final source in [error, jsonMap]) {
      if (source == null) continue;
      for (final key in const ['code', 'error_code', 'errorCode']) {
        final value = source[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
    }
    return null;
  }

  String get errorName => _firstText([
    error?['name'],
    error?['error_name'],
    error?['errorName'],
    jsonMap?['error_name'],
    jsonMap?['errorName'],
  ]);

  String get serverMessage => _firstText([
    error?['message'],
    error?['error_message'],
    error?['errorMessage'],
    error?['msg'],
    error?['toast_message'],
    error?['detail'],
    error?['description'],
    jsonMap?['message'],
    jsonMap?['error_message'],
    jsonMap?['errorMessage'],
    jsonMap?['msg'],
    jsonMap?['toast_message'],
    jsonMap?['detail'],
    jsonMap?['description'],
    if (jsonMap?['error'] is String) jsonMap?['error'],
  ]);

  bool get needLogin => _firstBool([
    error?['need_login'],
    error?['needLogin'],
    jsonMap?['need_login'],
    jsonMap?['needLogin'],
  ]);

  ApiFailure get failure => ApiFailure.fromResponse(this);

  String get statusLabel {
    final code = businessCode;
    if (code != null) return 'HTTP $statusCode · 业务码 $code';
    return 'HTTP $statusCode';
  }
}

/// Account action used by the official Android response interceptor.
///
/// The HTTP status and Zhihu business code are both required. In particular,
/// an arbitrary 401/403 must never erase a locally stored account session.
enum AccountAuthenticationAction { none, refresh, logout }

AccountAuthenticationAction accountAuthenticationAction(ApiResponse response) {
  if (response.statusCode != 401) {
    return AccountAuthenticationAction.none;
  }
  return switch (response.businessCode) {
    '100' => AccountAuthenticationAction.refresh,
    '101' || '401' => AccountAuthenticationAction.logout,
    _ => AccountAuthenticationAction.none,
  };
}

enum ApiFailureKind {
  transport,
  guestContext,
  networkChallenge,
  authentication,
  permission,
  notFound,
  rateLimited,
  server,
  request,
  invalidResponse,
  unknown,
}

/// A single presentation and control-flow model for HTTP, business and
/// transport failures. It intentionally keeps the HTTP status and business
/// code separate: `403 / 40353` is not interchangeable with `401 / 101`.
class ApiFailure {
  const ApiFailure({
    required this.kind,
    required this.title,
    required this.detail,
    required this.retryable,
    this.httpStatus,
    this.businessCode,
    this.errorName = '',
    this.serverMessage = '',
    this.needLogin = false,
  });

  factory ApiFailure.from(Object error) {
    if (error is ApiResponse) return ApiFailure.fromResponse(error);
    if (error is ApiFailure) return error;
    final message = error is ApiTransportException
        ? error.message
        : error.toString().trim();
    final technical = RegExp(
      r'API|HTTP|X-Zse|UDID|Bearer|Cookie|Header|JSON|Guest|guest|token|host|path|query|\bcode\b',
      caseSensitive: false,
    ).hasMatch(message);
    return ApiFailure(
      kind: ApiFailureKind.transport,
      title: '网络连接失败',
      detail: message.isEmpty || technical ? '暂时无法加载，请稍后重试。' : message,
      retryable: true,
    );
  }

  factory ApiFailure.fromResponse(ApiResponse response) {
    final status = response.statusCode;
    final code = response.businessCode;
    final message = response.serverMessage;
    final name = response.errorName;
    final needLogin = response.needLogin;

    ApiFailure build({
      required ApiFailureKind kind,
      required String title,
      required String fallback,
      required bool retryable,
    }) => ApiFailure(
      kind: kind,
      title: title,
      detail: fallback,
      retryable: retryable,
      httpStatus: status,
      businessCode: code,
      errorName: name,
      serverMessage: message,
      needLogin: needLogin,
    );

    if (code == '40352' || message.contains('网络环境存在异常')) {
      return build(
        kind: ApiFailureKind.networkChallenge,
        title: '需要验证网络环境',
        fallback: '知乎检测到当前网络环境需要验证，请先完成验证后再重试。',
        retryable: true,
      );
    }
    if (const {'10003', '40350', '40353'}.contains(code)) {
      return build(
        kind: ApiFailureKind.guestContext,
        title: '暂时无法加载',
        fallback: '请稍后重试。',
        retryable: true,
      );
    }
    if (status == 401 || code == '101') {
      return build(
        kind: ApiFailureKind.authentication,
        title: '请先登录',
        fallback: '登录后即可继续。',
        retryable: false,
      );
    }
    if (status == 403 || code == '403') {
      return build(
        kind: ApiFailureKind.permission,
        title: needLogin ? '请先登录' : '暂无访问权限',
        fallback: needLogin ? '登录后即可继续。' : '当前内容暂时无法查看。',
        retryable: false,
      );
    }
    if (status == 404 || code == '404') {
      return build(
        kind: ApiFailureKind.notFound,
        title: '内容不存在或已删除',
        fallback: '该内容可能已被删除。',
        retryable: false,
      );
    }
    if (status == 408 || status == 425 || status == 429) {
      return build(
        kind: ApiFailureKind.rateLimited,
        title: status == 429 ? '请求过于频繁' : '请求暂时未完成',
        fallback: status == 429 ? '请稍候片刻再试。' : '连接超时或服务端要求稍后重试。',
        retryable: true,
      );
    }
    if (status >= 500) {
      return build(
        kind: ApiFailureKind.server,
        title: '服务暂时不可用',
        fallback: '服务器暂时无法完成请求，请稍后重试。',
        retryable: true,
      );
    }
    if (status >= 400) {
      return build(
        kind: ApiFailureKind.request,
        title: '请求未被接受',
        fallback: '暂时无法完成，请稍后再试。',
        retryable: status == 409,
      );
    }
    if (!response.isSuccess) {
      return build(
        kind: ApiFailureKind.unknown,
        title: '请求没有完成',
        fallback: '暂时无法完成，请稍后再试。',
        retryable: true,
      );
    }
    return build(
      kind: ApiFailureKind.invalidResponse,
      title: '响应内容无法使用',
      fallback: '内容暂时无法显示。',
      retryable: true,
    );
  }

  /// Converts an authentication-shaped response from a known public read
  /// route into a retryable anonymous-context failure.  The server may use a
  /// generic 401/403 or `need_login` flag for a stale/missing Guest context;
  /// that response must not tell a signed-out reader that an account is
  /// required. Account-scoped callers continue to use [fromResponse].
  factory ApiFailure.forAnonymousRead(ApiResponse response) {
    final code = response.businessCode;
    final serverMessage = response.serverMessage;
    if (code == '40352' || serverMessage.contains('网络环境存在异常')) {
      return ApiFailure.fromResponse(response);
    }
    final anonymousBoundary =
        response.statusCode == 401 ||
        response.statusCode == 403 ||
        code == '101' ||
        code == '401' ||
        code == '403' ||
        response.needLogin;
    if (!anonymousBoundary) return ApiFailure.fromResponse(response);
    return ApiFailure(
      kind: ApiFailureKind.guestContext,
      title: '暂时无法加载',
      detail: '匿名内容服务暂时不可用，请稍后重试。',
      retryable: true,
      httpStatus: response.statusCode,
      businessCode: code,
      errorName: response.errorName,
      serverMessage: response.serverMessage,
    );
  }

  final ApiFailureKind kind;
  final String title;
  final String detail;
  final bool retryable;
  final int? httpStatus;
  final String? businessCode;
  final String errorName;
  final String serverMessage;
  final bool needLogin;

  String get statusLabel {
    final parts = <String>[
      if (httpStatus != null) 'HTTP $httpStatus',
      if (businessCode != null) '业务码 $businessCode',
      if (errorName.isNotEmpty) errorName,
    ];
    return parts.join(' · ');
  }

  String get userMessage {
    return detail;
  }
}

Map<String, dynamic> _stringMap(Map value) =>
    value.map((key, value) => MapEntry(key.toString(), value));

bool _containsErrorFields(Map<String, dynamic> value) => const [
  'code',
  'error_code',
  'errorCode',
  'error_message',
  'errorMessage',
].any(value.containsKey);

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    if (value == null || value is Map || value is List) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

bool _firstBool(Iterable<Object?> values) {
  for (final value in values) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  return false;
}
