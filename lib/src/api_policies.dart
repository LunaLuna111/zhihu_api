import 'dart:collection';

import 'api_response.dart';
import 'api_session.dart';

/// Retry decisions are injected so callers can choose offline-first, strict,
/// or application-specific retry behavior without changing endpoint code.
abstract interface class ApiRetryPolicy {
  int get freshGuestMaxAttempts;

  bool shouldRetryGetWithGuest(ApiResponse response);

  bool shouldRetryFreshGuestActivation({
    required String method,
    required ApiResponse response,
    required ApiSession session,
    required int remainingAttempts,
    required DateTime? deadline,
    required DateTime now,
  });

  Duration delayForFreshGuestAttempt(int attempt);
}

class DefaultApiRetryPolicy implements ApiRetryPolicy {
  const DefaultApiRetryPolicy();

  @override
  int get freshGuestMaxAttempts => 4;

  @override
  bool shouldRetryGetWithGuest(ApiResponse response) =>
      response.statusCode == 401 || response.statusCode == 403;

  @override
  bool shouldRetryFreshGuestActivation({
    required String method,
    required ApiResponse response,
    required ApiSession session,
    required int remainingAttempts,
    required DateTime? deadline,
    required DateTime now,
  }) =>
      method == 'GET' &&
      session.hasCompleteMobileContext &&
      remainingAttempts > 0 &&
      deadline != null &&
      now.isBefore(deadline) &&
      response.statusCode == 403 &&
      response.businessCode == '40353';

  @override
  Duration delayForFreshGuestAttempt(int attempt) {
    final bounded = attempt.clamp(1, 8);
    return Duration(milliseconds: 400 * (1 << (bounded - 1)));
  }
}

class NoRetryPolicy extends DefaultApiRetryPolicy {
  const NoRetryPolicy();

  @override
  int get freshGuestMaxAttempts => 0;

  @override
  bool shouldRetryGetWithGuest(ApiResponse response) => false;

  @override
  bool shouldRetryFreshGuestActivation({
    required String method,
    required ApiResponse response,
    required ApiSession session,
    required int remainingAttempts,
    required DateTime? deadline,
    required DateTime now,
  }) => false;
}

/// Account recovery policy. The default policy only treats `/people/self`
/// with an explicit identity error as authoritative for clearing credentials.
abstract interface class ApiAuthenticationPolicy {
  bool isAuthoritativeIdentityRejection({
    required String method,
    required Uri uri,
    required ApiResponse response,
    required String apiHost,
  });

  bool shouldClearAfterRefreshFailure(ApiResponse response);
}

class DefaultApiAuthenticationPolicy implements ApiAuthenticationPolicy {
  const DefaultApiAuthenticationPolicy();

  @override
  bool isAuthoritativeIdentityRejection({
    required String method,
    required Uri uri,
    required ApiResponse response,
    required String apiHost,
  }) {
    if (method != 'GET' ||
        uri.scheme != 'https' ||
        uri.host != apiHost ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.path != '/people/self') {
      return false;
    }
    final error = response.jsonMap?['error'];
    if (error is! Map) return false;
    final code = error['code']?.toString().trim() ?? '';
    return code == '101' || code == '401';
  }

  @override
  bool shouldClearAfterRefreshFailure(ApiResponse response) =>
      response.businessCode == '100008' ||
      response.statusCode == 401 &&
          const {'101', '401'}.contains(response.businessCode);
}

/// Optional response cache boundary. The core client does not cache by
/// default; the Flutter app can connect its existing answer/Salt caches.
abstract interface class ApiResponseCache {
  Future<ApiResponse?> read(String key);

  Future<void> write(String key, ApiResponse response);

  Future<void> remove(String key);
}

class NoopApiResponseCache implements ApiResponseCache {
  const NoopApiResponseCache();

  @override
  Future<ApiResponse?> read(String key) => Future<ApiResponse?>.value();

  @override
  Future<void> write(String key, ApiResponse response) => Future<void>.value();

  @override
  Future<void> remove(String key) => Future<void>.value();
}

/// A bounded in-memory response cache for short-lived Dart processes.
///
/// Persistent applications should inject a storage-backed implementation so
/// cached responses survive process restarts. This helper is intentionally
/// small and never writes API responses to disk.
class InMemoryApiResponseCache implements ApiResponseCache {
  InMemoryApiResponseCache({this.maxEntries = 64})
    : assert(maxEntries > 0),
      _values = LinkedHashMap<String, ApiResponse>();

  final int maxEntries;
  final LinkedHashMap<String, ApiResponse> _values;

  @override
  Future<ApiResponse?> read(String key) async => _values[key.trim()];

  @override
  Future<void> write(String key, ApiResponse response) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    _values
      ..remove(normalized)
      ..[normalized] = response;
    while (_values.length > maxEntries) {
      _values.remove(_values.keys.first);
    }
  }

  @override
  Future<void> remove(String key) async => _values.remove(key.trim());

  void clear() => _values.clear();
}
