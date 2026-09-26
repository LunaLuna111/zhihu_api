import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api.dart';

void main() {
  test('keeps native target policy in the API package', () {
    final allowed = Uri.parse('https://api.zhihu.com/answers/v2/42');
    final upload = Uri.parse('https://api.zhihu.com/upload_image');
    final lens = Uri.parse('https://lens.zhihu.com/api/v4/videos/abc_123');

    expect(ZhihuApiTransportPolicy.isApprovedNativeHttpTarget(allowed), isTrue);
    expect(
      ZhihuApiTransportPolicy.isApprovedNativeHttpRequest('GET', allowed, null),
      isTrue,
    );
    expect(ZhihuApiTransportPolicy.maxRequestBytes(upload), 20 * 1024 * 1024);
    expect(ZhihuApiTransportPolicy.isLensVideoMetadataUri(lens), isTrue);
    expect(
      ZhihuApiTransportPolicy.isApprovedNativeHttpRequest('POST', lens, null),
      isFalse,
    );
    expect(
      ZhihuApiTransportPolicy.isApprovedNativeHttpTarget(
        Uri.parse('https://example.com/api/v4/answers/42'),
      ),
      isFalse,
    );
    expect(
      ZhihuApiTransportPolicy.isApprovedNativeHttpTarget(
        Uri.parse('https://www.zhihu.com/signin'),
      ),
      isFalse,
    );
    expect(
      ZhihuApiTransportPolicy.isApprovedNativeHttpRequest(
        'GET',
        Uri.parse('https://www.zhihu.com/signin'),
        null,
      ),
      isTrue,
    );
    expect(
      ZhihuApiTransportPolicy.isApprovedLoginCaptureTarget(
        Uri.parse('https://api.zhihu.com/people/self#fragment'),
      ),
      isFalse,
    );
    expect(
      ZhihuApiTransportPolicy.isApprovedSaltRelayRequest(
        'POST',
        Uri.parse('https://api.zhihu.com/remix-pre-web/manuscript/1/2/content'),
        List<int>.filled(4 * 1024 * 1024 + 1, 0),
      ),
      isFalse,
    );
  });

  test('builds browser bridge targets without client-side host rules', () {
    expect(
      ZhihuApiTransportPolicy.browserBridgeUri(
        Uri.parse('https://www.zhihu.com/api/v4/search/hot_search'),
      ).toString(),
      '/web-api/api/v4/search/hot_search',
    );
    expect(
      ZhihuApiTransportPolicy.browserAllowedHeaders,
      contains('x-api-version'),
    );
  });

  test('normalizes session signature targets centrally', () {
    expect(
      ZhihuApiSessionProtocol.signatureTarget(
        ' get ',
        Uri.parse('https://api.zhihu.com/search_v3?q=flutter'),
      ),
      'GET /search_v3?q=flutter',
    );
    expect(
      ZhihuApiSessionProtocol.normalizeSignatureTarget(
        'post /content/publish?draft=1',
      ),
      'POST /content/publish?draft=1',
    );
    expect(
      () => ZhihuApiSessionProtocol.normalizeSignatureTarget(
        'GET https://example.com/private',
      ),
      throwsFormatException,
    );
  });

  test('normalizes server-provided API profile URLs', () {
    final api = ZhihuApiClient(
      InMemoryApiSession(),
      transport: _NoopTransport(),
    );
    addTearDown(api.close);

    expect(
      api.apiUriFromServerValue('/people/alice/answers')?.toString(),
      'https://api.zhihu.com/people/alice/answers',
    );
    expect(
      api
          .apiUriFromServerValue('https://api.zhihu.com/people/alice/answers')
          ?.path,
      '/people/alice/answers',
    );
    expect(
      api.apiUriFromServerValue('https://example.com/people/alice/answers'),
      isNull,
    );
    expect(api.apiUriFromServerValue('/people/alice/answers#fragment'), isNull);
  });
}

class _NoopTransport implements ApiTransport {
  @override
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  }) => throw StateError('not used');

  @override
  void close() {}
}
