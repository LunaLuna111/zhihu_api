import 'content_helpers.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'search_normalizers.dart';
import 'unwrap_and_component.dart';

// ordinary library module

String searchTitleText(Object? value) {
  if (value is List) {
    return value.map(searchTitleText).where((part) => part.isNotEmpty).join();
  }
  final map = stringMap(value);
  if (map != null) {
    for (final key in const [
      'plain_text',
      'text',
      'name',
      'title',
      'content',
      'value',
      'segments',
      'fragments',
    ]) {
      final text = searchTitleText(map[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
  return plainText(value);
}

String _humanSearchTitle(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final candidate in [object, source]) {
    for (final key in const [
      'title',
      'name',
      'excerpt_title',
      'headline',
      'display_query',
      'query_correction',
      'real_query',
      'query',
    ]) {
      final title = searchTitleText(candidate[key]);
      if (title.isNotEmpty) return title;
    }
  }
  final question = stringMap(object['question']);
  if (question != null) {
    final title = searchTitleText(question['title'] ?? question['name']);
    if (title.isNotEmpty) return title;
  }
  for (final candidate in [source['highlight'], object['highlight']]) {
    final highlight = stringMap(candidate);
    if (highlight == null) continue;
    final title = searchTitleText(
      highlight['title'] ?? highlight['name'] ?? highlight['text'],
    );
    if (title.isNotEmpty) return title;
  }
  // Do not call titleOf here: its `type #id` fallback is useful to diagnostics
  // and routing, but is exactly the implementation detail this repair keeps
  // out of human-facing search results.
  return '';
}

List<Map<String, dynamic>> repairIncompleteSearchRows(
  List<Map<String, dynamic>> rows,
) {
  // General search can emit a bare QuestionEntity immediately beside an
  // AnswerEntity for that same question. The question stub contains only its
  // numeric identity, while the answer already carries the real title. Reuse
  // that data locally instead of issuing one detail request per result.
  final questionTitles = <String, String>{};
  for (final row in rows) {
    final object = unwrapObject(row);
    final question = stringMap(object['question']);
    if (question == null) continue;
    final questionId = idOf(question);
    final questionTitle = _humanSearchTitle(question);
    if (questionId.isNotEmpty && questionTitle.isNotEmpty) {
      questionTitles.putIfAbsent(questionId, () => questionTitle);
    }
  }

  final repaired = <Map<String, dynamic>>[];
  for (final row in rows) {
    final type = typeOf(row).replaceAll('search_', '').toLowerCase();
    if ((isSearchHotTimingRow(row) && searchHotTimingItemsOf(row).isNotEmpty) ||
        (isSearchSectionRow(row) && searchSectionItemsOf(row).isNotEmpty)) {
      repaired.add(row);
      continue;
    }
    final humanTitle = _humanSearchTitle(row);
    if (type != 'question') {
      // Every ordinary result needs a human-facing title. Unknown transport
      // boundaries such as `education` are not useful cards; letting titleOf
      // fall back to their wire type exposes an implementation detail as if it
      // were content. Structured sections and timing groups were validated and
      // handled before reaching this repair pass.
      if (humanTitle.isEmpty) continue;
      repaired.add(row);
      continue;
    }
    if (humanTitle.isNotEmpty) {
      repaired.add(row);
      continue;
    }
    final recoveredTitle = questionTitles[idOf(row)];
    if (recoveredTitle != null) {
      repaired.add({...row, 'title': recoveredTitle});
    }
    // A bare identity has no information a person can evaluate. Omitting it
    // is preferable to reserving a blank-looking, tappable row forever.
  }
  return List.unmodifiable(repaired);
}

/// Search responses are module-oriented rather than a plain object list on
/// some app/server combinations.  In particular the 小说 vertical can place
/// `knowledge_ad` cards below `sections`, `items`, or a nested `data` object.
/// `extractRows` intentionally stops at the first list for ordinary feeds, so
/// use a search-specific walker here and keep every visible wire row exactly
/// once.  Embedded `object`/`answer_obj` maps are decoded by the row
/// normalizers and are not emitted as a second result.
List<Map<String, dynamic>> _extractSearchWireRows(Object? value) {
  final rows = <Map<String, dynamic>>[];
  final emitted = <String>{};
  final visited = <Object>{};
  const wrapperTypes = {
    'knowledge_result',
    'knowledge_ad',
    'search_advert',
    'advert',
    'advertisement',
    'promotion',
    'search_section',
    'hot_timing',
    'ring_box',
    'relevant_query',
    'search_query_correction',
    'search_result',
  };
  const containerKeys = {
    'data',
    'items',
    'results',
    'sections',
    'feeds',
    'list',
    'data_list',
    'dataList',
    'content_list',
    'contentList',
    'children',
    'modules',
    'view_data',
    'viewData',
    'payload',
    'response',
    'body',
    'contents',
    'result',
    'result_list',
    'resultList',
    'search_data',
  };

  String rowKey(Map<String, dynamic> row) {
    final object = stringMap(row['object']) ?? stringMap(row['answer_obj']);
    final target = object ?? row;
    final parts = [
      plainText(row['type']),
      plainText(target['id']),
      plainText(target['url']),
      plainText(target['title'] ?? target['name']),
    ];
    // Group wrappers such as `knowledge_result` legitimately have no own
    // identity; using only the type would collapse hot-timing and query
    // entries that happen to be adjacent in the same response.
    if (parts.skip(1).every((part) => part.isEmpty)) {
      return '${parts.join('\u0000')}\u0000${row.hashCode}';
    }
    return parts.join('\u0000');
  }

  void visit(Object? raw, int depth, {bool embedded = false}) {
    if (depth > 9 || raw == null) return;
    if (raw is List) {
      for (final item in raw.take(200)) {
        visit(item, depth + 1, embedded: embedded);
      }
      return;
    }
    final original = raw is Map ? raw : null;
    final map = stringMap(raw);
    if (map == null) return;
    if (original != null && !visited.add(original)) return;
    final type = plainText(map['type']).toLowerCase();
    final canEmit =
        !embedded &&
        type.isNotEmpty &&
        (wrapperTypes.contains(type) ||
            map.containsKey('object') ||
            map.containsKey('answer_obj') ||
            map.containsKey('highlight') ||
            map.containsKey('title') ||
            map.containsKey('name') ||
            map.containsKey('id'));
    if (canEmit && emitted.add(rowKey(map))) rows.add(map);

    // A result wrapper owns its object; the object's fields are intentionally
    // left to the normalizer.  Only recurse into known container fields so a
    // nested module is still discovered without turning every author/question
    // object into a duplicate card.
    for (final entry in map.entries) {
      if (!containerKeys.contains(entry.key)) continue;
      visit(entry.value, depth + 1);
    }
  }

  visit(value, 0);
  return rows;
}

/// Applies the supplied client's search-container rules.
///
/// `knowledge_result` is a real result wrapper whose `object` must be rendered.
/// General `knowledge_ad` rows are omitted; the novel and publication
/// verticals may opt into their matching market inventory because those
/// endpoints use the same wrapper for real results. A `hot_timing` object is a
/// visible grouped result, not a telemetry record.
List<Map<String, dynamic>> extractSearchRows(
  Object? value, {
  bool includeNovelMarketCards = false,
  bool includePublicationMarketCards = false,
}) {
  final rows = <Map<String, dynamic>>[];
  for (final row in _extractSearchWireRows(value)) {
    final wireType = plainText(row['type']).toLowerCase();
    if (isRingBoxSearchRow(row)) {
      rows.addAll(normalizeRingBoxSearchRow(row));
      continue;
    }
    if (isSearchAdvertisementRow(row)) {
      final marketCard = normalizeKnowledgeMarketCard(
        row,
        includeNovelMarketCards: includeNovelMarketCards,
        includePublicationMarketCards: includePublicationMarketCards,
      );
      if (marketCard != null) rows.add(marketCard);
      continue;
    }
    if (wireType == 'search_section') {
      if (searchSectionItemsOf(row).isNotEmpty) rows.add(row);
      continue;
    }
    if (wireType == 'knowledge_result') {
      final normalized = normalizeKnowledgeSearchResult(row);
      if (normalized == null) continue;
      if (isSearchHotTimingRow(normalized) &&
          searchHotTimingItemsOf(normalized).isEmpty) {
        continue;
      }
      if (includeNovelMarketCards && isNovelSearchObject(normalized)) {
        normalized['_search_novel_card'] = true;
      }
      rows.add(normalized);
      continue;
    }
    if (wireType == 'hot_timing') {
      if (searchHotTimingItemsOf(row).isNotEmpty) rows.add(row);
      continue;
    }
    if (wireType == 'relevant_query' && searchQueryOf(row).isEmpty) continue;
    if (includeNovelMarketCards && isNovelSearchObject(row)) {
      rows.add({...row, '_search_novel_card': true});
    } else {
      rows.add(row);
    }
  }
  return repairIncompleteSearchRows(rows);
}

String searchQueryOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  for (final candidate in [object, source]) {
    for (final key in const [
      'display_query',
      'query_correction',
      'real_query',
      'query',
    ]) {
      final value = plainText(candidate[key]);
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

List<(String, int)> searchStatisticsOf(Map<String, dynamic> source) {
  final object = unwrapObject(source);
  final raw = object['search_statistics'] ?? source['statistics'];
  if (raw is! List) return const [];
  final values = <(String, int)>[];
  for (final item in raw) {
    final map = stringMap(item);
    if (map == null) continue;
    final label = plainText(map['description']);
    final count = jsonInt(map['count']);
    if (label.isEmpty || count == null) continue;
    values.add((label, count));
    if (values.length == 3) break;
  }
  return List.unmodifiable(values);
}

/// Flattens the module-oriented Salt Story home response used by Zhihu 11.4.0.
///
/// The live `/km-vip-zhihu-web/vip_tab/svip_story` payload is not a legacy
/// catalog. Its top-level `data` contains seven modules. Work cards may live in
/// either `module_data.data.content_list` or in
/// `module_data.data.data[].content_list`; tab shortcuts live in `items`.
/// Module/group metadata is copied under private UI keys so the card renderer
/// can retain the hierarchy without changing server fields.
List<Map<String, dynamic>> extractSaltStoryModules(Object? value) {
  if (value is! Map) return const [];
  final root = value.map((key, value) => MapEntry(key.toString(), value));
  Object? modules = root['data'];
  // Older Salt gateways wrap the same module array one level deeper. Keep
  // accepting those envelopes: an absent `tab_nav` must not make the story
  // home lose its 分类/长篇/书架 entry group.
  if (modules is Map) {
    final nested = modules.map((key, value) => MapEntry(key.toString(), value));
    modules =
        nested['modules'] ??
        nested['data'] ??
        nested['items'] ??
        nested['list'] ??
        nested['content_list'];
    if (modules is Map &&
        (modules['module_type'] != null || modules['module_data'] != null)) {
      modules = [modules];
    }
  }
  if (modules is! List) return const [];
  return modules
      .map(stringMap)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

List<Map<String, dynamic>> extractSaltStoryRows(Object? value) {
  final modules = extractSaltStoryModules(value);
  final rows = <Map<String, dynamic>>[];

  void addCards(
    Object? candidates, {
    required String moduleType,
    required String moduleTitle,
    String groupTitle = '',
  }) {
    if (candidates is! List) return;
    var first = true;
    for (final candidate in candidates) {
      final card = stringMap(candidate);
      if (card == null) continue;
      rows.add({
        ...card,
        '_salt_module_type': moduleType,
        if (moduleTitle.isNotEmpty) '_salt_module_title': moduleTitle,
        if (groupTitle.isNotEmpty) '_salt_group_title': groupTitle,
        '_salt_group_first': first,
      });
      first = false;
    }
  }

  for (final candidate in modules) {
    final module = stringMap(candidate);
    if (module == null) continue;
    final moduleType = plainText(module['module_type'] ?? module['card_type']);
    final moduleData = stringMap(module['module_data']);
    final data = stringMap(moduleData?['data']);
    if (data == null) continue;
    final moduleTitle = plainText(
      module['module_title'] ?? data['title'] ?? module['title'],
    );

    addCards(data['items'], moduleType: moduleType, moduleTitle: moduleTitle);
    addCards(
      data['content_list'],
      moduleType: moduleType,
      moduleTitle: moduleTitle,
    );

    final groups = data['data'];
    if (groups is! List) continue;
    for (final groupValue in groups) {
      final group = stringMap(groupValue);
      if (group == null) continue;
      final head = stringMap(group['head']);
      addCards(
        group['content_list'],
        moduleType: moduleType,
        moduleTitle: moduleTitle,
        groupTitle: plainText(head?['title']),
      );
    }
  }
  return rows;
}

/// Navigation encoded by the live Salt story home cards.
///
/// Short stories use
/// `https://www.zhihu.com/market/paid_column/{business}/section/{section}` and
/// must enter the reader directly. Mid/long works use
/// `/market/manuscript?business_id=...&is_mid_long=...` and first need the
/// catalog endpoint. Treating every `PaidColumn` as a long catalog produces a
/// real but incorrect `/catalog/{section}` request.
