import 'dart:async';

import '../api_client.dart';

extension ZhihuApiClientSaltRoutes on ZhihuApiClient {
  String saltIdentifier(String value, String label) {
    final normalized = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw ApiTransportException('$label 必须是数字');
    }
    return normalized;
  }

  /// Salt Story home route.
  Uri saltStoryHomeUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/km-vip-zhihu-web/vip_tab/svip_story',
  );

  /// The official Salt bookshelf presenter fixes `type` to `vip_pin` and
  /// follows the returned paging offset/limit. This endpoint is account-bound
  /// but read-only; an anonymous response is shown as its real auth boundary.
  Uri saltBookshelfUri({int? offset, int? limit}) {
    if (offset != null && offset < 0) {
      throw const ApiTransportException('书架 offset 无效');
    }
    if (limit != null && (limit < 1 || limit > 100)) {
      throw const ApiTransportException('书架 limit 无效');
    }
    final query = <String>['type=vip_pin'];
    if (offset != null) query.add('offset=$offset');
    if (limit != null) query.add('limit=$limit');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/km-vip-zhihu-web/vip_tab/member/like_list?'
      '${query.join('&')}',
    );
  }

  /// Native shelf screen data.  The newer market home exposes the same cloud
  /// shelf through `/pluton/shelves`; unlike the legacy like-list endpoint it
  /// returns the complete `MarketShelfSkuInfo` metadata (progress, cover,
  /// author and download state) used by the original "我的书架" screen.
  Uri saltCloudShelfUri({
    int offset = 0,
    int limit = 20,
    String propertyType = '',
    String orderBy = '',
    String skuName = '',
    String learnProgress = '',
  }) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const ApiTransportException('云书架分页参数无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/pluton/shelves',
      <String, String>{
        'property_type': propertyType,
        'order_by': orderBy,
        'sku_name': skuName,
        'offset': '$offset',
        'learn_progress': learnProgress,
      },
    );
  }

  /// The shelf landing response used by the native VIP tab.  It contains
  /// `view_data` and is useful on accounts where `/pluton/shelves` is still
  /// warming its cache.
  Uri saltShelfHomeUri() =>
      Uri.parse('https://${ZhihuApiClient.apiHost}/bazaar/vip_tab/shelf');

  Uri saltShelfAnnotationsUri({int offset = 0, int limit = 20}) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const ApiTransportException('弹评分页参数无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/km-vip-zhihu-web/vip_tab/member/list_blank',
      <String, String>{
        'tab': 'annotation',
        'offset': '$offset',
        'limit': '$limit',
        'refresh_type': '0',
      },
    );
  }

  Uri saltShelfHistoryUri({int offset = 0}) {
    if (offset < 0) throw const ApiTransportException('历史记录 offset 无效');
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/bazaar/learning_history',
      <String, String>{'offset': '$offset'},
    );
  }

  Uri saltShelfBookListsUri({int offset = 0, int limit = 20}) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const ApiTransportException('书单分页参数无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/pluton/book_list/list',
      <String, String>{
        'offset': '$offset',
        'limit': '$limit',
        'type': 'collect',
      },
    );
  }

  Uri saltBookshelfMutationUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/km-indep-home-comm/member/book_shelf',
  );

  /// Adds the current Salt work to the account bookshelf using the exact
  /// `ShelfRequestParam` field names declared by App 11.4.0.
  Future<ApiResponse> addSaltToBookshelf({
    required String bookListId,
    required String propertyType,
  }) {
    requireWriteSession();
    final normalizedProperty = propertyType.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(normalizedProperty)) {
      throw const ApiTransportException('盐选作品类型无效');
    }
    return postJsonUri(
      saltBookshelfMutationUri(),
      jsonBody: {
        'book_list_id': saltIdentifier(bookListId, '盐选作品 ID'),
        'property_type': normalizedProperty,
      },
    );
  }

  /// Story category header. This read route also works without account state.
  Uri saltStoryCategoriesUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/pluton/category/story/header',
  );

  /// Long-form/discovery feed used by the Salt home "长篇" entry.
  ///
  /// The story shortcut currently points at this route on some server
  /// variants and at a web deep-link on others. Keeping the API target here
  /// gives the Flutter page a native-data fallback instead of silently
  /// returning the home modules when the shortcut URL is not an API URL.
  Uri saltLongStoryDiscoverUri({
    int offset = 0,
    int limit = 20,
    int clickedPin = 0,
    int refreshType = 0,
    int flowType = 0,
    String subTabAbValue = '',
  }) {
    if (offset < 0) throw const ApiTransportException('长篇 offset 无效');
    if (limit < 1 || limit > 100) {
      throw const ApiTransportException('长篇 limit 无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/km-vip-zhihu-web/vip_tab/vip_pin/discover',
      <String, String>{
        'offset': '$offset',
        'limit': '$limit',
        'clicked_pin': '$clickedPin',
        'refresh_type': '$refreshType',
        'flow_type': '$flowType',
        if (subTabAbValue.isNotEmpty) 'sub_tab_ab_val': subTabAbValue,
      },
    );
  }

  /// Book-city category conditions used by the original story/classify
  /// surface. It is kept separate from `/pluton/category/story/header`:
  /// the latter supplies the WebView tabs, while this route supplies native
  /// filter labels for servers that expose the new book-city implementation.
  Uri saltBookCityConditionsUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/bazaar/vip_tab/book_city/conditions',
  );

  Uri saltBookCitySectionUri({
    required String tagType,
    int limit = 20,
    int offset = 0,
    Map<String, String>? filters,
  }) {
    final normalized = tagType.trim();
    if (normalized.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(normalized)) {
      throw const ApiTransportException('故事分类无效');
    }
    if (limit < 1 || limit > 100 || offset < 0) {
      throw const ApiTransportException('故事分类分页参数无效');
    }
    final query = <String, String>{
      ...?filters,
      'limit': '$limit',
      'offset': '$offset',
    };
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/bazaar/vip_tab/book_city/section/$normalized',
      query,
    );
  }

  /// Native initial request (`m98383t`) deliberately has no `limit` or
  /// `offset`.  Sending those paging parameters on the first request makes
  /// the book/assessment tabs return 403/10003 on current servers.
  Uri saltBookCitySectionInitialUri({
    required String tagType,
    Map<String, String>? filters,
  }) {
    final normalized = tagType.trim();
    if (normalized.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(normalized)) {
      throw const ApiTransportException('故事分类无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/bazaar/vip_tab/book_city/section/$normalized',
      <String, String>{...?filters},
    );
  }

  /// Older app/server combinations use the SKU-list variant for the same
  /// category surface.  Keep it as a protocol-compatible fallback while the
  /// section request remains the primary native contract.
  Uri saltBookCitySkuListUri({
    required String tagType,
    Map<String, String>? filters,
    int? limit,
    int? offset,
  }) {
    final normalized = tagType.trim();
    if (normalized.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(normalized)) {
      throw const ApiTransportException('故事分类无效');
    }
    if (limit != null && (limit < 1 || limit > 100)) {
      throw const ApiTransportException('故事分类分页参数无效');
    }
    if (offset != null && offset < 0) {
      throw const ApiTransportException('故事分类 offset 无效');
    }
    return Uri.https(
      ZhihuApiClient.apiHost,
      '/bazaar/vip_tab/book_city/sku_list/$normalized',
      <String, String>{
        ...?filters,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    );
  }

  /// Exact initial catalog target used by the current long-story reader.
  /// `after_id` is the currently selected section (`0` on the work detail
  /// page), not a generic offset. Query order and the empty/zero distinction
  /// are retained because the mobile signature covers the request target.
  Uri saltCatalogInitialUri({
    required String wellId,
    String currentSectionId = '0',
  }) => saltCatalogBoundaryUri(wellId: wellId, afterId: currentSectionId);

  /// Reader catalog window used by the mobile reader.
  /// The forward request sends `after_id=current`; when the current chapter
  /// is not first, a second request sends `before_id=current` and the two
  /// windows are merged.
  Uri saltCatalogBoundaryUri({
    required String wellId,
    String? afterId,
    String? beforeId,
  }) {
    final well = saltIdentifier(wellId, '作品 ID');
    if ((afterId == null) == (beforeId == null)) {
      throw const ApiTransportException('目录边界必须且只能提供 after_id 或 before_id');
    }
    final query = <String>[];
    if (afterId != null) {
      query.add('after_id=${saltIdentifier(afterId, '当前章节 ID')}');
    }
    if (beforeId != null) {
      query.add('before_id=${saltIdentifier(beforeId, '当前章节 ID')}');
    }
    query.addAll(const [
      'include_search_id=1',
      'need_boundary=1',
      'limit=20',
      'scene=manuscript',
    ]);
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/km-indep-home-comm/catalog/$well?${query.join('&')}',
    );
  }

  Uri saltWorkSectionListUri(String workId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/km-indep-home-comm/work/'
    '${saltIdentifier(workId, '作品 ID')}/section_list',
  );

  Uri saltProgressUri(String wellId) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/km-indep-home-comm/progress/'
    '${saltIdentifier(wellId, '作品 ID')}?scene=manuscript',
  );

  Uri saltManuCacheUri({
    required String businessId,
    required String sectionId,
  }) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/remix-pre-web/manuscript/'
    '${saltIdentifier(businessId, '作品 ID')}/'
    '${saltIdentifier(sectionId, '章节 ID')}/manu_cache?is_mid_long=true',
  );

  /// Exact 11.4.0 long-story core request. The live App sends an empty
  /// `transmission`, `zs_page_turn=0`, and `is_mid_long=true`.
  Uri saltManuCoreUri({
    required String businessId,
    required String sectionId,
    int windowWidth = 411,
  }) {
    if (windowWidth < 1 || windowWidth > 10000) {
      throw const ApiTransportException('window_width 无效');
    }
    final business = saltIdentifier(businessId, '作品 ID');
    final section = saltIdentifier(sectionId, '章节 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/remix-pre-web/manuscript/$business/$section/manu_core'
      '?transmission=&window_width=$windowWidth&zs_page_turn=0'
      '&is_mid_long=true',
    );
  }

  Uri saltContentUri({
    required String businessId,
    required String sectionId,
    required int windowWidth,
  }) {
    if (windowWidth < 1 || windowWidth > 10000) {
      throw const ApiTransportException('window_width 无效');
    }
    final business = saltIdentifier(businessId, '作品 ID');
    final section = saltIdentifier(sectionId, '章节 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/remix-pre-web/manuscript/$business/$section/content'
      '?window_width=$windowWidth',
    );
  }

  /// Per-section key envelope used by the actual 11.4.0 NovelActivity reader.
  /// Its response must remain paired with the same in-memory raw request key.
  Uri saltArticleCodeUri() => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/remix-pre-web/manuscript/code',
  );

  /// Paragraph-level manuscript comments ("弹评") are fetched separately
  /// from the encrypted chapter body. The response maps reader paragraph
  /// indexes to numeric comment object IDs.
  Uri saltAnnotationsUri({required String sectionId}) => Uri.parse(
    'https://${ZhihuApiClient.apiHost}/remix-pre-web/manuscript/annotations?section_id='
    '${saltIdentifier(sectionId, '章节 ID')}',
  );

  /// Salt uses runtime-provided comment object types such as
  /// `annotation_vip_story` and `manuscript`. They are already pluralized (or
  /// otherwise server-defined), so they must not pass through the public
  /// answer/article/pin mapper below.
  Uri saltCommentsInitialUri({
    required String objectType,
    required String objectId,
    String orderBy = 'score',
  }) {
    final type = saltCommentObjectType(objectType);
    final id = saltIdentifier(objectId, '盐选评论对象 ID');
    final order = orderBy.trim().toLowerCase();
    if (!const {'score', 'hot', 'voteup_count', 'ts'}.contains(order)) {
      throw const ApiTransportException('盐选评论排序无效');
    }
    if (type == 'paid_column_section_manuscripts') {
      final vipOrder = order == 'hot' ? 'voteup_count' : order;
      return Uri.parse(
        'https://${ZhihuApiClient.apiHost}/km-indep-home-vip-comment/'
        'paid_column_section_manuscripts/$id/root_comment'
        '?order_by=$vipOrder&limit=20&offset=&source=',
      );
    }
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$type/$id/root_comment'
      '?order_by=$order&type=',
    );
  }

  String saltCommentObjectType(String objectType) {
    final type = objectType.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(type)) {
      throw const ApiTransportException('盐选评论对象类型无效');
    }
    return type == 'paid_column_section_manuscript'
        ? 'paid_column_section_manuscripts'
        : type;
  }

  /// The official Salt screen loads its author/context block through the
  /// regular comment-v5 list-headers contract, even when its root list uses
  /// the km-indep-home-vip-comment service.
  Uri saltCommentListHeadersUri({
    required String objectType,
    required String objectId,
  }) {
    final type = saltCommentObjectType(objectType);
    final id = saltIdentifier(objectId, '盐选评论对象 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$type/$id/list-headers',
    );
  }

  Uri saltCommentCreateUri({
    required String objectType,
    required String objectId,
  }) {
    final type = saltCommentObjectType(objectType);
    final id = saltIdentifier(objectId, '盐选评论对象 ID');
    return Uri.parse(
      'https://${ZhihuApiClient.apiHost}/comment_v5/$type/$id/comment',
    );
  }
}
