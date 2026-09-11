import 'rich_and_feed.dart';
import 'unwrap_and_component.dart';

// ordinary library module

Map<String, dynamic> saltManuscriptObject(Map<String, dynamic> root) {
  final pending = <Object?>[root];
  final visited = <int>{};
  while (pending.isNotEmpty) {
    final candidate = pending.removeAt(0);
    final map = stringMap(candidate);
    if (map == null || !visited.add(identityHashCode(map))) continue;
    if (map.containsKey('manuscript_sum') ||
        map.containsKey('manuscript_info') ||
        map.containsKey('render_list')) {
      return map;
    }
    for (final key in const ['data', 'payload', 'result', 'object', 'body']) {
      final nested = map[key];
      if (nested is List) {
        pending.addAll(nested);
      } else if (nested is Map) {
        pending.add(nested);
      }
    }
  }
  return root;
}

Map<String, dynamic>? saltFirstMap(Iterable<Object?> values) {
  for (final value in values) {
    final map = stringMap(value);
    if (map != null) return map;
  }
  return null;
}

String saltManuscriptText(Object? value) {
  if (value == null) return '';
  if (value is List) {
    return value
        .map(saltManuscriptText)
        .where((item) => item.isNotEmpty)
        .join('\n');
  }
  final map = stringMap(value);
  if (map != null) {
    for (final key in const [
      'plain_text',
      'text',
      'content',
      'value',
      'name',
      'title',
      'description',
      'summary',
      'url',
      'src',
    ]) {
      final text = saltManuscriptText(map[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
  return plainText(value);
}

String saltFirstText(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return '';
  for (final key in keys) {
    final text = saltManuscriptText(map[key]);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String saltTextFromMaps(
  Iterable<Map<String, dynamic>?> maps,
  List<String> keys,
) {
  for (final map in maps) {
    final text = saltFirstText(map, keys);
    if (text.isNotEmpty) return text;
  }
  return '';
}

int? _saltManuscriptInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  final text = saltManuscriptText(value).replaceAll(',', '');
  return int.tryParse(text);
}

int? saltFirstInt(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final number = _saltManuscriptInt(map[key]);
    if (number != null) return number;
  }
  return null;
}

bool? _saltManuscriptBool(Object? value) {
  if (value is bool) return value;
  final text = saltManuscriptText(value).toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

bool? saltFirstBool(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final value = _saltManuscriptBool(map[key]);
    if (value != null) return value;
  }
  return null;
}

String saltArtworkUrl(Object? value) {
  if (value is List) {
    for (final item in value) {
      final url = saltArtworkUrl(item);
      if (url.isNotEmpty) return url;
    }
    return '';
  }
  final map = stringMap(value);
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
      final url = saltArtworkUrl(map[key]);
      if (url.isNotEmpty) return url;
    }
    return '';
  }
  final text = plainText(value);
  return Uri.tryParse(text)?.scheme == 'https' ? text : '';
}

List<Map<String, dynamic>> _saltAuthorMaps(Object? value) {
  final result = <Map<String, dynamic>>[];
  void visit(Object? candidate, int depth) {
    if (candidate == null || depth > 4) return;
    if (candidate is List) {
      for (final item in candidate) {
        visit(item, depth + 1);
      }
      return;
    }
    final map = stringMap(candidate);
    if (map == null) return;
    result.add(map);
    for (final key in const ['profile', 'user', 'author', 'author_info']) {
      visit(map[key], depth + 1);
    }
  }

  visit(value, 0);
  return result;
}

Map<String, dynamic>? saltMergeAuthorMaps(Iterable<Object?> values) {
  final merged = <String, dynamic>{};
  for (final value in values) {
    for (final map in _saltAuthorMaps(value)) {
      for (final entry in map.entries) {
        if (saltManuscriptText(merged[entry.key]).isEmpty &&
            saltManuscriptText(entry.value).isNotEmpty) {
          merged[entry.key] = entry.value;
        }
      }
    }
  }
  return merged.isEmpty ? null : merged;
}

String saltAuthorField(Map<String, dynamic>? author, List<String> keys) =>
    saltFirstText(author, keys);

List<String> saltLabelList(Object? value) {
  final labels = <String>[];
  void add(Object? candidate) {
    if (candidate is List) {
      for (final item in candidate) {
        add(item);
      }
      return;
    }
    final map = stringMap(candidate);
    final text = saltManuscriptText(
      map?['name'] ??
          map?['text'] ??
          map?['title'] ??
          map?['value'] ??
          candidate,
    );
    if (text.isNotEmpty && !labels.contains(text)) labels.add(text);
  }

  add(value);
  return labels;
}
