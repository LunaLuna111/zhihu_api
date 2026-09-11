import 'api_response.dart';

/// Platform-neutral HTTP boundary.
///
/// The app can inject its audited Android MethodChannel transport, while
/// other consumers can implement this with `package:http` or another client.
abstract interface class ApiTransport {
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  });

  void close();
}
