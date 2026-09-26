import 'api_client.dart';

/// Protocol helpers for session data that is persisted by an application.
///
/// The secure-storage implementation stays in the host app; exact request
/// target validation stays here so each client uses the same signing rules.
abstract final class ZhihuApiSessionProtocol {
  static String signatureTarget(String method, Uri uri) {
    final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    return '${method.trim().toUpperCase()} $target';
  }

  static String normalizeSignatureTarget(String source) {
    final value = source.trim();
    if (value.isEmpty) return '';
    final match = RegExp(r'^([A-Za-z]+)\s+(/\S*)$').firstMatch(value);
    if (match == null || value.contains('\r') || value.contains('\n')) {
      throw const FormatException('签名目标格式应为 METHOD /path?exact=query');
    }
    final method = match.group(1)!.toUpperCase();
    if (!const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method)) {
      throw const FormatException('签名目标包含不支持的 HTTP method');
    }
    final requestTarget = match.group(2)!;
    final uri = Uri.tryParse('https://${ZhihuApiClient.apiHost}$requestTarget');
    if (uri == null ||
        uri.host != ZhihuApiClient.apiHost ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('签名目标必须是 api.zhihu.com 的 path/query');
    }
    return '$method $requestTarget';
  }
}
