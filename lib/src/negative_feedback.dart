Map<String, dynamic> _feedStringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _feedText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text == 'null' ? '' : text;
}

String _feedFirstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _feedText(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _feedTypeOf(Map<String, dynamic> source) => _feedFirstText([
  source['type'],
  source['content_type'],
  source['object_type'],
]);

String _feedIdOf(Map<String, dynamic> source) =>
    _feedFirstText([source['id'], source['object_id'], source['target_id']]);

String _feedAuthorNameOf(Map<String, dynamic> source) {
  final author = _feedStringMap(source['author']);
  return _feedFirstText([
    author['name'],
    author['nickname'],
    source['author_name'],
  ]);
}

class NegativeFeedbackIdentity {
  const NegativeFeedbackIdentity({
    required this.sceneCode,
    required this.contentType,
    required this.contentToken,
    required this.authorName,
    this.itemBrief = '',
  });

  factory NegativeFeedbackIdentity.fromFeed(Map<String, dynamic> source) {
    final rawType = _feedTypeOf(source).trim().toLowerCase();
    final contentType = switch (rawType) {
      'answer' => 'Answer',
      // NegativeFeedbackFragment rewrites the Android Post enum to `pin`
      // before requesting the panel. In this feed model Post is an article.
      'article' || 'post' => 'pin',
      'pin' => 'Pin',
      _ => '',
    };
    return NegativeFeedbackIdentity(
      sceneCode: 'recommend',
      contentType: contentType,
      contentToken: _feedIdOf(source).trim(),
      authorName: _feedAuthorNameOf(source).trim(),
      itemBrief: _feedBriefOf(source),
    );
  }

  final String sceneCode;
  final String contentType;
  final String contentToken;
  final String authorName;
  final String itemBrief;

  bool get isUsable =>
      sceneCode.isNotEmpty &&
      contentType.isNotEmpty &&
      RegExp(r'^\d+$').hasMatch(contentToken);
}

class NegativeFeedbackAction {
  const NegativeFeedbackAction({
    this.actionType = 0,
    this.backendUrl = '',
    this.intentUrl = '',
    this.method = '',
    this.parameters = const {},
    this.viewId,
    this.viewInfo = '',
  });

  factory NegativeFeedbackAction.fromJson(Object? value) {
    final map = _feedStringMap(value);
    final params = <String, String>{};
    final rawParams = map['param'];
    if (rawParams is Map) {
      rawParams.forEach((key, value) {
        if (value != null) params[key.toString()] = value.toString();
      });
    }
    return NegativeFeedbackAction(
      actionType: _feedIntOf(map['action_type']),
      backendUrl: _feedText(map['backend_url']),
      intentUrl: _feedText(map['intent_url']),
      method: _feedText(map['method']).toUpperCase(),
      parameters: Map.unmodifiable(params),
      viewId: map['view_id'] == null ? null : _feedIntOf(map['view_id']),
      viewInfo: _feedText(map['view_info']),
    );
  }

  final int actionType;
  final String backendUrl;
  final String intentUrl;
  final String method;
  final Map<String, String> parameters;
  final int? viewId;
  final String viewInfo;

  bool get hasBackend => backendUrl.isNotEmpty;
  bool get isUninterest => intentUrl == 'zhihu://uninterest_feed';
  bool get isBlockKeywords => intentUrl.contains('zhihu://block_keywords');
  bool get isReport => intentUrl.contains('www.zhihu.com/report');
}

class NegativeFeedbackMenuItem {
  const NegativeFeedbackMenuItem({
    required this.label,
    required this.toastText,
    required this.action,
    required this.hasRightIcon,
    required this.attachedInfo,
    required this.isRawButton,
  });

  factory NegativeFeedbackMenuItem.fromJson(Object? value) {
    final item = _feedStringMap(value);
    final alternative = _feedStringMap(item['alternative_button']);
    final button = item['raw_button'] is Map
        ? _feedStringMap(item['raw_button'])
        : _feedStringMap(alternative['current_button']);
    final buttonText = _feedStringMap(button['text']);
    final itemText = _feedStringMap(item['text']);
    final actionSource =
        button['action'] ?? buttonText['action'] ?? itemText['action'];
    return NegativeFeedbackMenuItem(
      label: _feedFirstText([
        buttonText['panel_text'],
        itemText['panel_text'],
        buttonText['toast_text'],
      ]),
      toastText: _feedFirstText([
        buttonText['toast_text'],
        itemText['toast_text'],
      ]),
      action: NegativeFeedbackAction.fromJson(actionSource),
      hasRightIcon: button['right_icon'] is Map,
      attachedInfo: _feedText(button['attached_info']),
      isRawButton: item['raw_button'] is Map,
    );
  }

  final String label;
  final String toastText;
  final NegativeFeedbackAction action;
  final bool hasRightIcon;
  final String attachedInfo;
  final bool isRawButton;

  bool get removesFeedItem => action.isUninterest || isRawButton;
}

class NegativeFeedbackMenu {
  const NegativeFeedbackMenu({required this.items, this.style = ''});

  factory NegativeFeedbackMenu.fromJson(Object? value) {
    final root = _feedStringMap(value);
    final data = root['data'] is Map ? _feedStringMap(root['data']) : root;
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
              .map(NegativeFeedbackMenuItem.fromJson)
              .where((item) => item.label.isNotEmpty)
              .toList(growable: false)
        : const <NegativeFeedbackMenuItem>[];
    if (items.isEmpty) {
      throw const FormatException('反馈菜单没有可显示的项目');
    }
    return NegativeFeedbackMenu(items: items, style: _feedText(data['style']));
  }

  final List<NegativeFeedbackMenuItem> items;
  final String style;
}

class BlockKeywordsConfig {
  const BlockKeywordsConfig({
    required this.keywords,
    required this.isVip,
    required this.minLength,
    required this.maxLength,
    required this.maxCount,
  });

  factory BlockKeywordsConfig.fromJson(Object? value) {
    final root = _feedStringMap(value);
    final data = root['data'];
    final keywords = data is List
        ? data
              .map(_feedText)
              .where((word) => word.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return BlockKeywordsConfig(
      keywords: keywords,
      isVip: root['is_vip'] == true,
      minLength: _feedPositiveOr(root['kw_min_length'], 2),
      maxLength: _feedPositiveOr(root['kw_max_length'], 15),
      maxCount: _feedPositiveOr(root['kw_max_count'], 5),
    );
  }

  final List<String> keywords;
  final bool isVip;
  final int minLength;
  final int maxLength;
  final int maxCount;
}

int _feedIntOf(Object? value) =>
    value is int ? value : int.tryParse(value?.toString().trim() ?? '') ?? 0;

int _feedPositiveOr(Object? value, int fallback) {
  final parsed = _feedIntOf(value);
  return parsed > 0 ? parsed : fallback;
}

String _feedBriefOf(Map<String, dynamic> source) {
  String find(Object? value) {
    if (value is Map) {
      for (final key in const ['brief', 'item_brief']) {
        final text = _feedText(value[key]);
        if (text.isNotEmpty && text.length <= 20000) return text;
      }
      for (final nested in value.values) {
        final result = find(nested);
        if (result.isNotEmpty) return result;
      }
    } else if (value is List) {
      for (final nested in value) {
        final result = find(nested);
        if (result.isNotEmpty) return result;
      }
    }
    return '';
  }

  return find(source);
}
