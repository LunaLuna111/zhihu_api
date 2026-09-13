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
  test('builds the native sentence-comment root route', () {
    final api = ZhihuApiClient(
      InMemoryApiSession(),
      transport: _NoopTransport(),
    );
    addTearDown(api.close);

    expect(
      api
          .segmentCommentsInitialUri(
            contentType: 'answer',
            contentId: '123',
            segmentId: 'segment-a,segment-b',
            orderBy: 'time',
          )
          .toString(),
      'https://api.zhihu.com/comment_v5/answers/123/segment/root_comment?'
      'segment_id=segment-a,segment-b&limit=20&offset=&order_by=ts',
    );
  });

  test('rejects an unsafe sentence-comment locator', () {
    final api = ZhihuApiClient(
      InMemoryApiSession(),
      transport: _NoopTransport(),
    );
    addTearDown(api.close);

    expect(
      () => api.segmentCommentsInitialUri(
        contentType: 'answer',
        contentId: '123',
        segmentId: 'segment-a&offset=all',
      ),
      throwsA(isA<ApiTransportException>()),
    );
  });
}
