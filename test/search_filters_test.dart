import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api.dart';

class _Transport implements ApiTransport {
  _Transport(this.response);

  final ApiResponse response;
  Uri? requestedUri;
  Map<String, String>? requestedHeaders;

  @override
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  }) async {
    requestedUri = uri;
    requestedHeaders = headers;
    return response;
  }

  @override
  void close() {}
}

ApiResponse _response(Uri uri, Object json) => ApiResponse(
  uri: uri,
  statusCode: 200,
  bodyBytes: 2,
  json: json,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test('parses valid groups and rejects unsafe or mixed options', () {
    final result = parseSearchFilterGroups({
      'data': [
        [
          {'group': 'vertical', 'title': '不限类型', 'link_name': ''},
          {'group': 'vertical', 'title': '只看回答', 'link_name': 'answer'},
          {'group': 'vertical', 'title': '危险值', 'link_name': '../token'},
        ],
        [
          {'group': 'sort', 'title': '综合排序', 'linkName': ''},
          {'group': 'other', 'title': '不支持', 'link_name': 'x'},
        ],
      ],
    });

    expect(result, hasLength(1));
    expect(result.single.map((item) => item.title), ['不限类型', '只看回答']);
    expect(result.single.last.linkName, 'answer');
  });

  test('fetches search filters with the native API version', () async {
    final responseUri = Uri.https('api.zhihu.com', '/search/customize');
    final transport = _Transport(
      _response(responseUri, const {
        'data': [
          [
            {'group': 'sort', 'title': '综合排序', 'link_name': ''},
            {'group': 'sort', 'title': '最多赞同', 'link_name': 'upvoted_count'},
          ],
        ],
      }),
    );
    final api = ZhihuApiClient(InMemoryApiSession(), transport: transport);

    final result = await api.fetchSearchFilterGroups();

    expect(result.single.last.linkName, 'upvoted_count');
    expect(transport.requestedUri, responseUri);
    expect(transport.requestedHeaders?['x-api-version'], '3.0.91');
  });
}
