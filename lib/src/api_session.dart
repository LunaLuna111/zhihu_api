import 'api_cloud_id.dart';

/// The credential and session boundary consumed by [ZhihuApiClient].
///
/// Storage is deliberately not part of this interface. A Flutter application
/// can implement it with secure storage, while a command-line client can keep
/// the same session in memory or in an encrypted file.
abstract interface class ApiSession {
  String get authorization;
  String get udid;
  String get cookie;
  String get msId;
  String get sessionKind;
  String get refreshToken;
  String get accountUid;
  String get accountUserId;

  DateTime? get accessTokenExpiry;
  DateTime? get accessTokenRefreshAt;

  bool get hasAuthorization;
  bool get hasCompleteMobileContext;
  bool get hasAccountSession;
  bool get hasRefreshableAccountSession;
  bool get hasGuestSession;
  bool get isAccessTokenExpired;
  bool get shouldRefreshAccountToken;
  bool get supportsPersistentApiSession;
  int get credentialRevision;

  Map<String, String> requestHeaders({
    required String method,
    required Uri uri,
  });

  Future<void> saveMsId(String value);

  Future<void> saveGuestSession({
    required String accessToken,
    required String udid,
    String zCookie,
  });

  Future<void> clearGuestSession();

  Future<bool> saveAccountSession({
    required String accessToken,
    required String refreshToken,
    required String udid,
    required Duration expiresIn,
    String tokenType,
    String zCookie,
    String? uid,
    String? userId,
    String? scope,
    String? unlockTicket,
    int? lockInSeconds,
    int? expectedCredentialRevision,
  });

  Future<bool> saveQrSession({
    required String cookie,
    required String udid,
    String? uid,
    String? userId,
  });

  Future<void> clear();
}

/// A non-persistent session implementation for command-line clients,
/// examples, and applications that provide their own storage boundary.
///
/// It deliberately keeps every credential only in memory and reports
/// [supportsPersistentApiSession] as `false`. Flutter applications should
/// continue to inject a secure-storage-backed [ApiSession] instead.
class InMemoryApiSession implements ApiSession {
  InMemoryApiSession({
    String authorization = '',
    String udid = '',
    String cookie = '',
    String msId = '',
    String sessionKind = '',
    String refreshToken = '',
    DateTime? accessTokenExpiry,
    DateTime? accessTokenRefreshAt,
    String accountUid = '',
    String accountUserId = '',
  }) : _authorization = authorization.trim(),
       _udid = udid.trim(),
       _cookie = cookie.trim(),
       _msId = msId.trim(),
       _sessionKind = sessionKind.trim(),
       _refreshToken = refreshToken.trim(),
       _expiry = accessTokenExpiry,
       _refreshAt = accessTokenRefreshAt,
       _accountUid = accountUid.trim(),
       _accountUserId = accountUserId.trim();

  String _authorization;
  String _udid;
  String _cookie;
  String _msId;
  String _sessionKind;
  String _refreshToken;
  DateTime? _expiry;
  DateTime? _refreshAt;
  String _accountUid;
  String _accountUserId;
  int _credentialRevision = 0;

  @override
  String get authorization => _authorization;

  @override
  String get udid => _udid;

  @override
  String get cookie => _cookie;

  @override
  String get msId => _msId;

  @override
  String get sessionKind => _sessionKind;

  @override
  String get refreshToken => _refreshToken;

  @override
  String get accountUid => _accountUid;

  @override
  String get accountUserId => _accountUserId;

  @override
  DateTime? get accessTokenExpiry => _expiry;

  @override
  DateTime? get accessTokenRefreshAt => _refreshAt;

  @override
  bool get hasAuthorization => _authorization.isNotEmpty;

  @override
  bool get hasCompleteMobileContext =>
      _authorization.isNotEmpty && _udid.isNotEmpty;

  @override
  bool get hasAccountSession =>
      hasCompleteMobileContext &&
      (_sessionKind == 'account' ||
          _sessionKind == 'qr' && _hasQrIdentityCookie);

  @override
  bool get hasRefreshableAccountSession =>
      _sessionKind == 'account' && hasCompleteMobileContext;

  @override
  bool get hasGuestSession =>
      _sessionKind == 'guest' && hasCompleteMobileContext;

  @override
  bool get isAccessTokenExpired =>
      _expiry != null && !DateTime.now().toUtc().isBefore(_expiry!);

  @override
  bool get shouldRefreshAccountToken =>
      _sessionKind == 'account' &&
      _refreshToken.isNotEmpty &&
      _refreshAt != null &&
      !DateTime.now().toUtc().isBefore(_refreshAt!);

  @override
  bool get supportsPersistentApiSession => false;

  @override
  int get credentialRevision => _credentialRevision;

  @override
  Map<String, String> requestHeaders({
    required String method,
    required Uri uri,
  }) => {
    if (_authorization.isNotEmpty) 'Authorization': _authorization,
    if (_udid.isNotEmpty) 'x-udid': _udid,
    if (_cookie.isNotEmpty) 'Cookie': _cookie,
    if (_msId.isNotEmpty) 'X-MS-ID': _msId,
  };

  @override
  Future<void> saveMsId(String value) async {
    _msId = _validated(value, 'X-MS-ID');
  }

  @override
  Future<void> saveGuestSession({
    required String accessToken,
    required String udid,
    String zCookie = '',
  }) async {
    final token = _required(accessToken, 'guest access_token');
    final device = _required(udid, 'guest udid');
    final cookie = _cookieValue(zCookie);
    _credentialRevision += 1;
    _authorization = 'Bearer $token';
    _udid = device;
    _cookie = cookie;
    _sessionKind = 'guest';
    _refreshToken = '';
    _expiry = null;
    _refreshAt = null;
    _clearAccountMetadata();
  }

  @override
  Future<void> clearGuestSession() async {
    if (_sessionKind != 'guest') return;
    _credentialRevision += 1;
    _authorization = '';
    _udid = '';
    _cookie = '';
    _sessionKind = '';
    _refreshToken = '';
    _expiry = null;
    _refreshAt = null;
    _clearAccountMetadata();
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
  }) async {
    if (expectedCredentialRevision != null &&
        expectedCredentialRevision != _credentialRevision) {
      return false;
    }
    if (expiresIn <= Duration.zero) {
      throw const FormatException('账号 Token 有效期必须大于零');
    }
    if (tokenType.trim().toLowerCase() != 'bearer') {
      throw const FormatException('当前只接受 Bearer token_type');
    }
    if (lockInSeconds != null && lockInSeconds < 0) {
      throw const FormatException('lock_in 不能为负数');
    }
    final token = _required(accessToken, 'access_token');
    final refresh = _required(refreshToken, 'refresh_token');
    final device = _required(udid, '账号 udid');
    final now = DateTime.now().toUtc();
    _credentialRevision += 1;
    _authorization = 'Bearer $token';
    _udid = device;
    _cookie = _cookieValue(zCookie);
    _sessionKind = 'account';
    _refreshToken = refresh;
    _expiry = now.add(expiresIn);
    _refreshAt = now.add(
      Duration(milliseconds: expiresIn.inMilliseconds * 21 ~/ 30),
    );
    _accountUid = uid?.trim() ?? _accountUid;
    _accountUserId = userId?.trim() ?? _accountUserId;
    return true;
  }

  @override
  Future<bool> saveQrSession({
    required String cookie,
    required String udid,
    String? uid,
    String? userId,
  }) async {
    final normalizedCookie = _required(cookie, '扫码登录 Cookie');
    if (!_containsZCookie(normalizedCookie)) {
      throw const FormatException('扫码登录响应缺少 z_c0 Cookie');
    }
    final device = _required(udid, '扫码登录 udid');
    _credentialRevision += 1;
    _authorization = ZhihuCloudProtocol.oauthAuthorization;
    _udid = device;
    _cookie = normalizedCookie;
    _sessionKind = 'qr';
    _refreshToken = '';
    _expiry = null;
    _refreshAt = null;
    _accountUid = uid?.trim() ?? '';
    _accountUserId = userId?.trim() ?? '';
    return true;
  }

  @override
  Future<void> clear() async {
    _credentialRevision += 1;
    _authorization = '';
    _udid = '';
    _cookie = '';
    _msId = '';
    _sessionKind = '';
    _refreshToken = '';
    _expiry = null;
    _refreshAt = null;
    _clearAccountMetadata();
  }

  bool get _hasQrIdentityCookie => _containsZCookie(_cookie);

  void _clearAccountMetadata() {
    _accountUid = '';
    _accountUserId = '';
  }

  static String _required(String value, String label) {
    final normalized = _validated(value, label);
    if (normalized.isEmpty) throw FormatException('$label 不能为空');
    return normalized;
  }

  static String _validated(String value, String label) {
    final normalized = value.trim();
    if (normalized.contains('\r') || normalized.contains('\n')) {
      throw FormatException('$label 不能包含换行');
    }
    return normalized;
  }

  static String _cookieValue(String value) {
    final normalized = _validated(value, 'z_c0 Cookie');
    if (normalized.isEmpty) return '';
    if (normalized.toLowerCase().startsWith('z_c0=')) return normalized;
    return 'z_c0=$normalized';
  }

  static bool _containsZCookie(String value) => value.split(';').any((part) {
    final separator = part.indexOf('=');
    return separator > 0 &&
        part.substring(0, separator).trim().toLowerCase() == 'z_c0' &&
        part.substring(separator + 1).trim().isNotEmpty;
  });
}
