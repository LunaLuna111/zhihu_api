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
  test('parses current hot-search payload and preserves server order', () {
    final result = parseSearchHotItems({
      'top_search': {
        'words': [
          {'query': 'DeepSeek', 'hot_score': '5340000', 'hot_show': '534 万'},
          {'query': 'deepseek'},
          {'display_query': 'Flutter', 'heatScore': 42},
        ],
      },
    });

    expect(result.map((item) => item.query), ['DeepSeek', 'Flutter']);
    expect(result.first.heatScore, 5340000);
    expect(result.first.hotShow, '534 万');
    expect(result.last.displayQuery, 'Flutter');
  });

  test('parses legacy hot_search_queries and nested wrappers', () {
    expect(
      parseSearchHotItems({
        'data': {
          'hot_search_queries': [
            {'query': '第一条'},
            {'query': '第二条'},
          ],
        },
      }).map((item) => item.query),
      ['第一条', '第二条'],
    );
  });

  test('fetches hot search anonymously through public Web route', () async {
    final responseUri = Uri.https('www.zhihu.com', '/api/v4/search/hot_search');
    final transport = _Transport(
      _response(responseUri, const {
        'hot_search_queries': [
          {'query': '热搜一'},
        ],
      }),
    );
    final api = ZhihuApiClient(InMemoryApiSession(), transport: transport);

    final result = await api.fetchSearchHotItems();

    expect(result.single.query, '热搜一');
    expect(transport.requestedUri, responseUri);
    expect(transport.requestedHeaders, {
      'accept': ZhihuApiClient.appUserAgent.isEmpty
          ? 'application/json'
          : 'application/json',
      'user-agent': ZhihuApiClient.appUserAgent,
    });
  });
}
