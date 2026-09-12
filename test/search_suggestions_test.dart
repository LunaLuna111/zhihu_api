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
  test('parses current suggest payload and removes duplicate queries', () {
    final suggestions = parseSearchSuggestions({
      'suggest': [
        {'query': 'deepseek', 'id': -1, 'label': 'hot'},
        {'query': ' deepseek '},
        {'query': 'DeepSeek V4', 'tab_type': 'general'},
        {'label': 'invalid'},
      ],
    });

    expect(suggestions.map((item) => item.query), ['deepseek', 'DeepSeek V4']);
    expect(suggestions.first.id, '-1');
    expect(suggestions.first.label, 'hot');
    expect(suggestions.last.tabType, 'general');
  });

  test('builds the anonymous public Web route', () {
    final api = ZhihuApiClient(
      InMemoryApiSession(),
      transport: _Transport(
        _response(Uri.https('www.zhihu.com', '/api/v4/search/suggest'), const {
          'suggest': <Object>[],
        }),
      ),
    );

    final uri = api.searchSuggestionsUri(keyword: '深度 学习');
    expect(uri.host, 'www.zhihu.com');
    expect(uri.path, '/api/v4/search/suggest');
    expect(uri.queryParameters, {'q': '深度 学习', 'magi': '1'});
  });

  test('fetches suggestions without session headers', () async {
    final responseUri = Uri.https('www.zhihu.com', '/api/v4/search/suggest', {
      'q': 'deepseek',
      'magi': '1',
    });
    final transport = _Transport(
      _response(responseUri, const {
        'suggest': [
          {'query': 'deepseek R1'},
        ],
      }),
    );
    final api = ZhihuApiClient(InMemoryApiSession(), transport: transport);

    final result = await api.fetchSearchSuggestions(keyword: 'deepseek');

    expect(result.single.query, 'deepseek R1');
    expect(transport.requestedUri, responseUri);
    expect(transport.requestedHeaders, {
      'accept': ZhihuApiClient.appUserAgent.isEmpty
          ? 'application/json'
          : 'application/json',
      'user-agent': ZhihuApiClient.appUserAgent,
    });
  });
}
