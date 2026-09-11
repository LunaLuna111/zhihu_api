import 'components_and_images.dart';
import 'identity_and_metrics.dart';
import 'rich_and_feed.dart';
import 'search_normalizers.dart';
import 'unwrap_and_component.dart';

// ordinary library module

/// Parses the dedicated story-category header contract.
///
/// Unlike ordinary Zhihu list endpoints this response is a `PageItemList`
/// whose `data` items have `category_cn`, `category_name`, `background`,
/// `banner` and `url`; none of those fields are understood by `titleOf`, so
/// passing it through `extractRows` used to make the category screen look
/// empty. The normalized `title`/`subtitle` aliases keep the rest of the UI
/// code intentionally data-source agnostic.
List<Map<String, dynamic>> extractSaltStoryCategoryItems(Object? value) {
  final root = stringMap(value);
  Object? raw = root?['data'] ?? value;
  // The category header has used both `data: [...]` and nested object-list
  // envelopes (`data: {data: [...]}`, `data: {items: [...]}`).  Unwrap those
  // envelopes before inspecting fields so a valid response never renders as
  // an empty page just because its transport wrapper changed.
  for (var depth = 0; depth < 4 && raw is Map; depth++) {
    final map = stringMap(raw);
    if (map == null) break;
    final next = map['data'] ?? map['items'] ?? map['list'] ?? map['results'];
    if (next == null || identical(next, raw)) break;
    raw = next;
  }
  if (raw is! List) return const [];
  final items = <Map<String, dynamic>>[];
  for (final candidate in raw) {
    final item = stringMap(candidate);
    if (item == null) continue;
    final categoryCn = plainText(item['category_cn']);
    final categoryName = plainText(item['category_name']);
    final url = plainText(item['url']);
    if (categoryCn.isEmpty && categoryName.isEmpty && url.isEmpty) continue;
    items.add({
      ...item,
      if (categoryCn.isNotEmpty) 'title': categoryCn,
      if (categoryName.isNotEmpty) 'subtitle': categoryName,
    });
  }
  return List.unmodifiable(items);
}

/// Extracts the native book-city category contract used by newer clients.
/// The endpoint returns tag groups (`tags`) and each group contains nested
/// `categories`/`labels`, so treating the response as a flat list silently
/// produced the old empty category page.
List<Map<String, dynamic>> extractSaltBookCityCategoryItems(Object? value) {
  final root = stringMap(value);
  if (root == null) return const [];

  // The response has appeared in both of these forms:
  //   {"tags": [...]} and {"data": {"tags": [...]}}.
  // A third server variant puts the tag objects directly in data.  Do not
  // require one envelope shape or the native category screen becomes empty
  // even though the response is a valid BookCityConditionsData payload.
  final tags = <Map<String, dynamic>>[];
  void collectTags(Object? candidate, {int depth = 0}) {
    if (depth > 3) return;
    final map = stringMap(candidate);
    if (map != null) {
      final nestedTags = map['tags'];
      if (nestedTags is List) {
        for (final item in nestedTags) {
          final tag = stringMap(item);
          if (tag != null) tags.add(tag);
        }
      }
      collectTags(map['data'], depth: depth + 1);
      return;
    }
    if (candidate is List) {
      for (final item in candidate) {
        final itemMap = stringMap(item);
        if (itemMap == null) continue;
        if (itemMap['tag_type'] != null || itemMap['tag_title'] != null) {
          tags.add(itemMap);
        } else {
          collectTags(itemMap, depth: depth + 1);
        }
      }
    }
  }

  collectTags(root);
  if (tags.isEmpty) return const [];
  final items = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final tag in tags) {
    final tagType = plainText(tag['tag_type'] ?? tag['value'] ?? tag['key']);
    final tagTitle = plainText(tag['tag_title'] ?? tag['title']);

    // Categories are not a flat list.  Each category is a group with its own
    // `key/title/value` and a `data` list of ConditionsLevelData children.
    // Flatten the children while retaining the parent query values used by
    // /book_city/section/{tag_type}.
    final groups = <Map<String, dynamic>>[];
    for (final key in const [
      'categories',
      'labels',
      'hot_labels',
      'short_content_type',
    ]) {
      final rawGroups = tag[key];
      if (rawGroups is! List) continue;
      for (final rawGroup in rawGroups) {
        final group = stringMap(rawGroup);
        if (group != null) groups.add(group);
      }
    }

    // The native filter header also exposes quick filters and sort choices
    // outside the category groups. Keep them as first-class entries instead
    // of silently dropping the controls that drive the same section query.
    final directConditions = <String, List<Object?>>{
      'quick': [
        if (tag['quick_filter'] != null) tag['quick_filter'],
        ...?tag['quick_filters'] is List
            ? (tag['quick_filters'] as List)
            : null,
      ],
      'sort': [...?tag['sorts'] is List ? (tag['sorts'] as List) : null],
    };
    for (final entry in directConditions.entries) {
      for (final rawCondition in entry.value) {
        final condition = stringMap(rawCondition);
        if (condition == null) continue;
        final key = plainText(condition['key']);
        final value = plainText(condition['value'] ?? key);
        final title = plainText(
          condition['title'] ?? condition['show_text'] ?? condition['name'],
        );
        if (title.isEmpty && value.isEmpty) continue;
        final query = <String, String>{
          if (key.isNotEmpty && value.isNotEmpty) key: value,
        };
        final dedupeKey = [tagType, entry.key, key, value, title].join('|');
        if (!seen.add(dedupeKey)) continue;
        items.add({
          ...condition,
          'title': title.isEmpty ? value : title,
          'subtitle': tagTitle,
          if (tagType.isNotEmpty) '_salt_tag_type': tagType,
          '_salt_condition_role': entry.key,
          if (key.isNotEmpty) '_salt_filter_key': key,
          if (value.isNotEmpty) '_salt_filter_value': value,
          if (query.isNotEmpty) '_salt_filter_query': query,
        });
      }
    }

    // The original BookCityConditionsData keeps the bottom-sheet filters in
    // a nested `filters` object (sku_types, content_status and right_types).
    // Older extraction code only flattened quick filters and categories, so
    // the native classify page had no way to render or submit those controls.
    // Flatten them while preserving the server's key/value pair and a stable
    // Chinese section title used by the UI.
    final rawFilters = stringMap(tag['filters']);
    if (rawFilters != null) {
      const filterTitles = <String, String>{
        'sku_types': '类型',
        'resource_types': '类型',
        'short_content_type': '类型',
        'content_status': '状态',
        'right_types': '权益',
      };
      for (final entry in rawFilters.entries) {
        final rawChoices = entry.value;
        if (rawChoices is! List) continue;
        final parentTitle = filterTitles[entry.key] ?? entry.key;
        for (final rawChoice in rawChoices) {
          final choice = stringMap(rawChoice);
          if (choice == null) continue;
          final key = plainText(choice['key']);
          final value = plainText(choice['value'] ?? key);
          final title = plainText(
            choice['title'] ?? choice['show_text'] ?? choice['name'],
          );
          if (title.isEmpty || key.isEmpty || value.isEmpty) continue;
          final dedupeKey = [
            tagType,
            'filter',
            entry.key,
            key,
            value,
          ].join('|');
          if (!seen.add(dedupeKey)) continue;
          items.add({
            ...choice,
            'title': title,
            'subtitle': tagTitle,
            if (tagType.isNotEmpty) '_salt_tag_type': tagType,
            '_salt_condition_role': 'filter',
            '_salt_filter_group': entry.key,
            '_salt_parent_title': parentTitle,
            '_salt_filter_key': key,
            '_salt_filter_value': value,
            '_salt_filter_query': <String, String>{key: value},
          });
        }
      }
    }

    final hasDirectConditions = directConditions.values.any(
      (conditions) => conditions.isNotEmpty,
    );
    if (groups.isEmpty && !hasDirectConditions) {
      if (tagType.isNotEmpty || tagTitle.isNotEmpty) {
        items.add({
          ...tag,
          'title': tagTitle.isEmpty ? tagType : tagTitle,
          if (tagType.isNotEmpty) '_salt_tag_type': tagType,
        });
      }
      continue;
    }

    for (final group in groups) {
      final parentKey = plainText(group['key']);
      final parentValue = plainText(group['value'] ?? group['key']);
      final parentTitle = plainText(group['title'] ?? group['show_text']);
      final rawChoices = group['data'];
      final choices = rawChoices is List && rawChoices.isNotEmpty
          ? rawChoices
          : <Object?>[group];
      for (final rawChoice in choices) {
        final choice = stringMap(rawChoice);
        if (choice == null) continue;
        final title = plainText(
          choice['show_text'] ?? choice['title'] ?? choice['name'],
        );
        final choiceKey = plainText(choice['key']);
        final valueText = plainText(choice['value'] ?? choiceKey);
        if (title.isEmpty && valueText.isEmpty) continue;
        final filterKey = choiceKey.isEmpty ? parentKey : choiceKey;
        final filterValue = valueText.isEmpty ? parentValue : valueText;
        final query = <String, String>{
          if (parentKey.isNotEmpty && parentValue.isNotEmpty)
            parentKey: parentValue,
          if (choiceKey.isNotEmpty && valueText.isNotEmpty)
            choiceKey: valueText,
        };
        final dedupeKey = [tagType, filterKey, filterValue, title].join('|');
        if (!seen.add(dedupeKey)) continue;
        items.add({
          ...choice,
          'title': title.isEmpty ? valueText : title,
          'subtitle': tagTitle.isEmpty ? parentTitle : tagTitle,
          if (tagType.isNotEmpty) '_salt_tag_type': tagType,
          if (filterKey.isNotEmpty) '_salt_filter_key': filterKey,
          if (filterValue.isNotEmpty) '_salt_filter_value': filterValue,
          if (parentKey.isNotEmpty) '_salt_parent_key': parentKey,
          if (parentValue.isNotEmpty) '_salt_parent_value': parentValue,
          if (parentTitle.isNotEmpty) '_salt_parent_title': parentTitle,
          if (query.isNotEmpty) '_salt_filter_query': query,
        });
      }
    }
  }
  return List.unmodifiable(items);
}

/// Flattens both variants of the long-story discovery response.
///
/// `vip_pin/discover` returns `BasePinInfo` rows (`module_data.data` contains
/// the actual Pin/EveryoneWatch payload), while older server variants return
/// a plain `data` list of book cards. Normalizing those payloads here makes
/// long-story cards retain their cover, producer, intro, labels and like
/// summary instead of falling back to an empty generic row.
List<Map<String, dynamic>> extractSaltLongStoryRows(Object? value) {
  final root = stringMap(value);
  if (root == null) return const [];
  final output = <Map<String, dynamic>>[];

  String artworkUrl(Object? raw, {int depth = 0}) {
    if (raw == null || depth > 4) return '';
    if (raw is List) {
      for (final item in raw) {
        final url = artworkUrl(item, depth: depth + 1);
        if (url.isNotEmpty) return url;
      }
      return '';
    }
    final map = stringMap(raw);
    if (map != null) {
      for (final key in const [
        'url',
        'src',
        'image_url',
        'cover_url',
        'original_url',
        'large',
        'medium',
        'small',
        'data',
      ]) {
        final url = artworkUrl(map[key], depth: depth + 1);
        if (url.isNotEmpty) return url;
      }
      return '';
    }
    final text = plainText(raw);
    final uri = Uri.tryParse(text);
    return uri?.scheme == 'https' ? text : '';
  }

  void addCandidate(Object? candidate, {int depth = 0}) {
    if (depth > 5) return;
    final map = stringMap(candidate);
    if (map == null) return;

    final moduleData = stringMap(map['module_data']);
    final rawModulePayload = moduleData?['data'];
    if (rawModulePayload is List) {
      for (final child in rawModulePayload) {
        addCandidate(child, depth: depth + 1);
      }
      return;
    }
    final modulePayload = stringMap(rawModulePayload);
    if (modulePayload != null) {
      // Discover rows commonly wrap the useful Pin in module_data.data.
      addCandidate(modulePayload, depth: depth + 1);
      return;
    }

    final nestedData = map['data'];
    if (nestedData is List) {
      for (final child in nestedData) {
        addCandidate(child, depth: depth + 1);
      }
      return;
    }
    if (nestedData is Map) {
      addCandidate(nestedData, depth: depth + 1);
      return;
    }

    final title = plainText(
      map['title'] ?? map['content_title'] ?? map['question_title'],
    );
    final artwork = artworkUrl(
      map['artwork'] ??
          map['image_url'] ??
          map['cover_url'] ??
          map['cover_image'] ??
          map['head_artwork'] ??
          map['tab_artwork'] ??
          map['image'] ??
          map['images'],
    );
    final businessId = plainText(
      map['business_id'] ??
          map['well_id'] ??
          map['book_list_id'] ??
          map['work_id'] ??
          map['book_id'] ??
          map['f95768id'] ??
          map['id'] ??
          map['sku_id'],
    );
    final url = plainText(map['url']);
    if (title.isEmpty && artwork.isEmpty && businessId.isEmpty && url.isEmpty) {
      return;
    }
    final labels = map['labels'];
    final contentLikeCount = map['content_like_count'];
    final producer = plainText(
      map['producer'] ??
          map['producer_name'] ??
          map['author_name'] ??
          map['property_type'] ??
          saltAuthorName(map['publisher'] ?? map['authors']),
    );
    // Some book-city responses reuse `producer` for the SKU marker rather
    // than an author name (for example `paid_column`).  It is a transport
    // value, not user-facing copy, and rendering it below every title makes
    // the category cards visibly diverge from the native client.
    final visibleProducer =
        const {
          'paid_column',
          'content_short',
          'ebook',
          'ebook_audio',
          'assessment',
        }.contains(producer.toLowerCase())
        ? ''
        : producer;
    final producerIsTransportMarker = const {
      'paid_column',
      'content_short',
      'ebook',
      'ebook_audio',
      'assessment',
    }.contains(producer.toLowerCase());
    final subtitle = plainText(
      map['sub_title'] ?? map['subtitle'] ?? map['summary'],
    );
    final content = plainText(
      map['content'] ?? map['description'] ?? map['summary'],
    );
    final contentCount = map['content_count'];
    final contentCountText = contentCount is num
        ? contentCount > 0
              ? '${contentCount.round()}节'
              : ''
        : plainText(contentCount);
    output.add({
      ...map,
      if (title.isNotEmpty) 'title': title,
      if (artwork.isNotEmpty) 'artwork': artwork,
      if (producerIsTransportMarker) 'producer': '',
      if (businessId.isNotEmpty) 'business_id': businessId,
      if (url.isNotEmpty) 'url': url,
      if (visibleProducer.isNotEmpty) 'producer_name': visibleProducer,
      if (subtitle.isNotEmpty) 'subtitle': subtitle,
      if (content.isNotEmpty) 'description': content,
      if (plainText(map['like_count']).isEmpty &&
          plainText(contentLikeCount).isNotEmpty)
        'like_count': contentLikeCount,
      if (contentCountText.isNotEmpty) 'content_count_text': contentCountText,
      if (plainText(map['business_type']).isEmpty &&
          plainText(map['property_type']).isNotEmpty)
        'business_type': plainText(map['property_type']),
      if (plainText(map['progress_text']).isEmpty &&
          plainText(map['process_text']).isNotEmpty)
        'progress_text': plainText(map['process_text']),
      if (labels is List) 'labels': labels,
    });
  }

  final data = root['data'] ?? root['view_data'];
  if (data is List) {
    for (final row in data) {
      addCandidate(row);
    }
  } else if (data is Map) {
    addCandidate(data);
  }
  // FCT11CData (`/bazaar/vip_tab/shelf`) places the native shelf cards in
  // `view_data`, while some gateway versions wrap that list in `data`.
  for (final key in const ['view_data', 'viewData']) {
    final rows = root[key];
    if (rows is List) {
      for (final row in rows) {
        addCandidate(row);
      }
    } else if (rows is Map) {
      addCandidate(rows);
    }
  }
  // A few ZHObjectList responses use `items` or `list` instead of `data`.
  for (final key in const ['items', 'list', 'results', 'content_list']) {
    final rows = root[key];
    if (rows is List) {
      for (final row in rows) {
        addCandidate(row);
      }
    }
  }

  final seen = <String>{};
  return List.unmodifiable(
    output.where((row) {
      final key = [
        plainText(row['business_id']),
        plainText(row['section_id']),
        plainText(row['url']),
        titleOf(row),
      ].join('|');
      return seen.add(key);
    }),
  );
}

/// Normalizes the cloud shelf envelopes used by both native shelf services.
/// `/pluton/shelves` returns `data`, whereas the VIP home shelf returns
/// `view_data`; both are converted to the same catalog-card model so cloud
/// and local entries can be rendered and merged without a second card stack.
List<Map<String, dynamic>> extractSaltShelfRows(Object? value) {
  final root = stringMap(value);
  if (root == null) return const [];
  Object? candidate = root['view_data'] ?? root['viewData'];
  if (candidate == null) {
    final data = root['data'];
    candidate = data is Map
        ? (data['view_data'] ??
              data['viewData'] ??
              data['items'] ??
              data['data'])
        : data;
  }
  if (candidate is! List) {
    final rows = extractRows(value);
    return rows.isEmpty ? const [] : extractSaltLongStoryRows({'data': rows});
  }
  return extractSaltLongStoryRows({'data': candidate});
}
