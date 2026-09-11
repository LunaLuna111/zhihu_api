import 'api_response.dart';

/// Redacts credentials and request-specific values before a URI is sent to a
/// logger.  This belongs to the pure client because transports and loggers
/// should never need to depend on the Flutter application's storage layer.
String sanitizeUri(Uri uri) {
  const safeKeys = <String>{
    'offset',
    'limit',
    'page',
    'order',
    'type',
    'sort_by',
    'show_detail',
    'window_width',
  };
  final query = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    query[entry.key] = safeKeys.contains(entry.key)
        ? entry.value
        : '[redacted]';
  }
  return uri.replace(queryParameters: query).toString();
}

/// Optional debug sink. It is intentionally separate from [ApiLogger] so a
/// release application can keep diagnostics enabled without exporting raw
/// request/response exchanges.
abstract interface class ApiDebugSink {
  bool get enabled;

  void write(String message);

  Future<void> recordExchange({
    required String method,
    required Uri uri,
    required Map<String, String> requestHeaders,
    required List<int>? requestBody,
    required ApiResponse response,
  });
}

class NoopApiDebugSink implements ApiDebugSink {
  const NoopApiDebugSink();

  @override
  bool get enabled => false;

  @override
  void write(String message) {}

  @override
  Future<void> recordExchange({
    required String method,
    required Uri uri,
    required Map<String, String> requestHeaders,
    required List<int>? requestBody,
    required ApiResponse response,
  }) => Future<void>.value();
}
