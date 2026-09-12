/// One selectable search filter returned by Zhihu's search configuration API.
class SearchFilterOption {
  const SearchFilterOption({
    required this.group,
    required this.title,
    required this.linkName,
  });

  final String group;
  final String title;
  final String linkName;
}

/// Parses the validated filter groups used by the native search screen.
/// Unknown groups and malformed link names are ignored so a changed server
/// configuration cannot create an unsafe query value in a client.
List<List<SearchFilterOption>> parseSearchFilterGroups(Object? value) {
  if (value is! Map) return const [];
  final root = value.map((key, child) => MapEntry(key.toString(), child));
  final data = root['data'];
  if (data is! List) return const [];
  final groups = <List<SearchFilterOption>>[];
  for (final rawGroup in data) {
    if (rawGroup is! List) continue;
    final options = <SearchFilterOption>[];
    for (final rawOption in rawGroup) {
      if (rawOption is! Map) continue;
      final option = rawOption.map(
        (key, child) => MapEntry(key.toString(), child),
      );
      final group = _text(option['group']);
      final title = _text(option['title']);
      final linkName = _text(option['link_name'] ?? option['linkName']);
      if (!const {'vertical', 'sort', 'time_interval'}.contains(group) ||
          title.isEmpty ||
          (linkName.isNotEmpty && !RegExp(r'^[a-z_]+$').hasMatch(linkName))) {
        continue;
      }
      options.add(
        SearchFilterOption(group: group, title: title, linkName: linkName),
      );
    }
    if (options.length >= 2 &&
        options.every((item) => item.group == options.first.group)) {
      groups.add(List.unmodifiable(options));
    }
  }
  return List.unmodifiable(groups);
}

String _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text == 'null' ? '' : text;
}
