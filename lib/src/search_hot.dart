/// Ordered hot-search entries returned by Zhihu's public Web API.
class SearchHotItem {
  const SearchHotItem({
    required this.query,
    required this.displayQuery,
    required this.heatScore,
    this.hotShow = '',
  });

  final String query;
  final String displayQuery;
  final int heatScore;
  final String hotShow;

  static SearchHotItem? tryParse(Object? value) {
    if (value is! Map) return null;
    final item = value.map((key, child) => MapEntry(key.toString(), child));
    final query = _text(
      item['query'] ??
          item['display_query'] ??
          item['displayQuery'] ??
          item['word'],
    );
    if (query.isEmpty) return null;
    final displayQuery = _text(
      item['display_query'] ?? item['displayQuery'] ?? query,
    );
    final score =
        item['heat_score'] ??
        item['heatScore'] ??
        item['hot_score'] ??
        item['hotScore'];
    final hotShow = _text(
      item['hot_show'] ?? item['hotShow'] ?? item['display_hot'],
    );
    return SearchHotItem(
      query: query,
      displayQuery: displayQuery.isEmpty ? query : displayQuery,
      heatScore: _nonNegativeInt(score),
      hotShow: hotShow,
    );
  }

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse(_text(value));
    return parsed != null && parsed >= 0 ? parsed : 0;
  }
}

/// Parses the payload shapes used by the public endpoint over different Web
/// client versions. The first occurrence wins because the server order is the
/// display order used by the native search screen.
List<SearchHotItem> parseSearchHotItems(Object? value, {int limit = 15}) {
  if (limit <= 0) return const [];
  final candidates = _hotItemList(value);
  final result = <SearchHotItem>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final item = SearchHotItem.tryParse(candidate);
    if (item == null || !seen.add(item.query.toLowerCase())) continue;
    result.add(item);
    if (result.length >= limit) break;
  }
  return List.unmodifiable(result);
}

List<Object?> _hotItemList(Object? value) {
  if (value is List) return List<Object?>.from(value);
  if (value is! Map) return const [];
  final root = value.map((key, child) => MapEntry(key.toString(), child));
  final topSearch = root['top_search'] ?? root['topSearch'];
  final topItems = topSearch is Map
      ? topSearch['words'] ?? topSearch['items']
      : null;
  if (topItems is List) return List<Object?>.from(topItems);

  final data = root['data'];
  final nestedItems = data is Map
      ? data['words'] ?? data['hot_search_queries'] ?? data['items']
      : null;
  if (root['hot_search_queries'] is List) {
    return List<Object?>.from(root['hot_search_queries'] as List);
  }
  if (nestedItems is List) return List<Object?>.from(nestedItems);
  if (data is List) return List<Object?>.from(data);
  return const [];
}
