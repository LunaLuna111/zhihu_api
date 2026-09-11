import 'dart:async';

/// Observability boundary for the request pipeline. No logger is required;
/// the default client is silent and never persists credentials or bodies.
abstract interface class ApiLogger {
  Future<void> record({
    required String category,
    required String level,
    required String message,
    Map<String, Object?> details,
  });

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String message,
    String category,
  });

  Future<void> recordNetwork({
    required String method,
    required Uri uri,
    required String profile,
    int? statusCode,
    String? statusLabel,
    String? businessCode,
    int? bodyBytes,
    int? durationMs,
    String? errorType,
  });
}

class NoopApiLogger implements ApiLogger {
  const NoopApiLogger();

  @override
  Future<void> record({
    required String category,
    required String level,
    required String message,
    Map<String, Object?> details = const {},
  }) => Future<void>.value();

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String message = '未处理异常',
    String category = 'error',
  }) => Future<void>.value();

  @override
  Future<void> recordNetwork({
    required String method,
    required Uri uri,
    required String profile,
    int? statusCode,
    String? statusLabel,
    String? businessCode,
    int? bodyBytes,
    int? durationMs,
    String? errorType,
  }) => Future<void>.value();
}

Future<void> awaitLogger(FutureOr<void> value) async {
  await value;
}
