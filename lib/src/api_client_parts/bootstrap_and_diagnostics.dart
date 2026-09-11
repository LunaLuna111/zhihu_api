import 'dart:async';

import '../api_client.dart';

extension ZhihuApiClientBootstrapAndDiagnostics on ZhihuApiClient {
  Future<ApiResponse> sendMobileRaw(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int>? body,
    bool includeBaseHeaders = true,
    String debugProfile = 'mobile-base',
  }) async {
    final appInfo = includeBaseHeaders ? await resolveAppInfo() : '';
    var merged = ZhihuApiClient.canonicalizeHeaders({
      if (includeBaseHeaders) ...baseHeaders,
      if (includeBaseHeaders && appInfo.isNotEmpty) 'x-app-za': appInfo,
      if (session.msId.isNotEmpty) 'X-MS-ID': session.msId,
      ...headers,
    });
    try {
      merged = await xZseSigner.signHeaders(
        uri: uri,
        headers: merged,
        body: body,
      );
    } on ApiTransportException {
      rethrow;
    } on Object catch (error) {
      throw ApiTransportException('Guest 初始化 X-Zse 失败：${error.runtimeType}');
    }
    debugLogRequest(method, uri, merged, body, profile: debugProfile);
    for (final entry in merged.entries) {
      if (entry.value.contains('\n') || entry.value.contains('\r')) {
        throw ApiTransportException('${entry.key} 含非法换行');
      }
    }
    final stopwatch = Stopwatch()..start();
    final response = await transport.send(
      method: method,
      uri: uri,
      headers: merged,
      body: body,
      maxResponseBytes: ZhihuApiClient.maxResponseBytes,
    );
    stopwatch.stop();
    debugLogResponse(method, uri, response);
    unawaited(
      apiLogger.recordNetwork(
        method: method,
        uri: uri,
        profile: debugProfile,
        statusCode: response.statusCode,
        statusLabel: response.statusLabel,
        businessCode: response.businessCode,
        bodyBytes: response.bodyBytes,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
    await debugSink.recordExchange(
      method: method,
      uri: uri,
      requestHeaders: merged,
      requestBody: body,
      response: response,
    );
    return response;
  }

  Future<String> resolveAppInfo() async {
    if (appInfo.isNotEmpty) return appInfo;
    final existing = appInfoLoad;
    if (existing != null) return existing;
    final started = loadAppInfo();
    appInfoLoad = started;
    try {
      final value = await started;
      if (value.isNotEmpty) appInfo = value;
      return value;
    } finally {
      appInfoLoad = null;
    }
  }

  Future<String> loadAppInfo() async {
    try {
      return await cloudIdProvider.appInfo();
    } on TimeoutException {
      debugPrint('x-app-za unavailable=timeout');
      return '';
    } on Object catch (error) {
      debugPrint('x-app-za unavailable=${error.runtimeType}');
      return '';
    }
  }

  void close() => transport.close();
}
