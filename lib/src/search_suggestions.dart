/// Search completion items returned by Zhihu's public search endpoint.
class SearchSuggestion {
  const SearchSuggestion({
    required this.query,
    this.id = '',
    this.iconUrl = '',
    this.width = 0,
    this.height = 0,
    this.label = '',
    this.tabType = '',
    this.targetUrl = '',
    this.attachedInfo = '',
  });

  final String query;
  final String id;
  final String iconUrl;
  final int width;
  final int height;
  final String label;
  final String tabType;
  final String targetUrl;
  final String attachedInfo;

  /// Returns null for an item that cannot be shown to a user.
  static SearchSuggestion? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry(key.toString(), item));
    final query = _text(map['query']);
    if (query.isEmpty) return null;
    return SearchSuggestion(
      query: query,
      id: _text(map['id']),
      iconUrl: _text(map['icon_url']),
      width: _nonNegativeInt(map['width']),
      height: _nonNegativeInt(map['height']),
      label: _text(map['label']),
      tabType: _text(map['tab_type']),
      targetUrl: _text(map['target_url']),
      attachedInfo: _text(map['attached_info']),
    );
  }

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(_text(value));
    return parsed != null && parsed >= 0 ? parsed : 0;
  }
}

/// Parses both the current `{suggest: [...]}` response and the older list
/// wrappers observed in public Web responses. Duplicate visible queries are
/// removed while preserving the server order.
List<SearchSuggestion> parseSearchSuggestions(Object? value, {int limit = 10}) {
  if (limit <= 0) return const [];
  final candidates = _suggestionList(value);
  final result = <SearchSuggestion>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final suggestion = SearchSuggestion.tryParse(candidate);
    if (suggestion == null || !seen.add(suggestion.query)) continue;
    result.add(suggestion);
    if (result.length >= limit) break;
  }
  return List.unmodifiable(result);
}

List<Object?> _suggestionList(Object? value) {
  if (value is List) return List<Object?>.from(value);
  if (value is! Map) return const [];
  final map = value.map((key, item) => MapEntry(key.toString(), item));
  for (final candidate in [map['suggest'], map['data']]) {
    if (candidate is List) return List<Object?>.from(candidate);
    if (candidate is Map) {
      final nested = candidate.map(
        (key, item) => MapEntry(key.toString(), item),
      );
      for (final key in const [
        'suggest',
        'suggestions',
        'items',
        'list',
        'data',
      ]) {
        if (nested[key] is List) return List<Object?>.from(nested[key] as List);
      }
    }
  }
  return const [];
}
