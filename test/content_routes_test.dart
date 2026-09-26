import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api.dart';

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

void main() {
  final api = ZhihuApiClient(InMemoryApiSession(), transport: _NoopTransport());

  tearDownAll(api.close);

  test('keeps content detail targets in the API package', () {
    expect(
      api.contentDetailUri(contentType: 'answer', contentId: '123').toString(),
      'https://api.zhihu.com/answers/v2/123',
    );
    expect(
      api
          .publicAnswerUri('123', query: const {'include': 'content'})
          .toString(),
      'https://www.zhihu.com/api/v4/answers/123?include=content',
    );
  });

  test('builds discovery and topic routes centrally', () {
    expect(api.columnTabFeedUri().path, '/column/column_tab/feed');
    expect(api.hotTopicsUri().path, '/hot/topics');
    expect(
      api.topicEssenceFeedsUri('42').toString(),
      'https://api.zhihu.com/topics/42/essence_feeds?offset=0&limit=10',
    );
  });

  test('rejects unsafe content route segments', () {
    expect(
      () => api.columnDetailUri('../private'),
      throwsA(isA<ApiTransportException>()),
    );
    expect(
      () => api.topicBasicUri('not-a-number'),
      throwsA(isA<ApiTransportException>()),
    );
  });
}
