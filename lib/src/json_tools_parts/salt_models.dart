import 'rich_and_feed.dart';
import 'unwrap_and_component.dart';

// ordinary library module

class SaltStoryNavigation {
  const SaltStoryNavigation({required this.businessId, this.sectionId});

  final String businessId;
  final String? sectionId;

  bool get opensReader => sectionId != null;
}

SaltStoryNavigation? parseSaltStoryNavigation(Object? value) {
  final card = stringMap(value);
  if (card == null) return null;

  Object? nestedAlias(List<String> keys) {
    Object? visit(Object? candidate, int depth) {
      if (depth > 3) return null;
      final map = stringMap(candidate);
      if (map == null) return null;
      for (final key in keys) {
        final found = map[key];
        if (found != null && plainText(found).isNotEmpty) return found;
      }
      for (final key in const [
        'business',
        'work',
        'product',
        'sku',
        'resource',
        'content',
        'object',
        'data',
      ]) {
        final found = visit(map[key], depth + 1);
        if (found != null && plainText(found).isNotEmpty) return found;
      }
      return null;
    }

    return visit(card, 0);
  }

  // Native discovery cards may omit a fully-qualified URL while retaining
  // the identifiers used by the original reader routes.
  final directBusiness = numericIdentifier(
    nestedAlias(const [
      'business_id',
      'well_id',
      'book_list_id',
      'work_id',
      'book_id',
    ]),
  );
  final directSection = numericIdentifier(
    nestedAlias(const ['section_id', 'chapter_id']),
  );
  if (directBusiness != null && directSection != null) {
    return SaltStoryNavigation(
      businessId: directBusiness,
      sectionId: directSection,
    );
  }

  final rawUrl = plainText(
    nestedAlias(const [
      'url',
      'redirect_url',
      'target_url',
      'link',
      'deep_link',
    ]),
  );
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return directBusiness == null
        ? null
        : SaltStoryNavigation(businessId: directBusiness);
  }

  final queryBusiness = numericIdentifier(
    uri.queryParameters['business_id'] ??
        uri.queryParameters['well_id'] ??
        uri.queryParameters['book_list_id'] ??
        uri.queryParameters['work_id'],
  );
  final querySection = numericIdentifier(
    uri.queryParameters['section_id'] ?? uri.queryParameters['chapter_id'],
  );
  if (queryBusiness != null && querySection != null) {
    return SaltStoryNavigation(
      businessId: queryBusiness,
      sectionId: querySection,
    );
  }
  if (queryBusiness != null) {
    return SaltStoryNavigation(businessId: queryBusiness);
  }

  final segments = uri.host == 'market'
      ? <String>[uri.host, ...uri.pathSegments]
      : uri.pathSegments;
  final isZhihuRoute =
      uri.host == 'www.zhihu.com' ||
      uri.host == 'zhihu.com' ||
      uri.host == 'story.zhihu.com' ||
      uri.host == 'api.zhihu.com' ||
      uri.scheme == 'zhihu';
  final paidColumnIndex = segments.indexOf('paid_column');
  if (isZhihuRoute &&
      paidColumnIndex >= 0 &&
      segments.length > paidColumnIndex + 1) {
    final businessId = numericIdentifier(segments[paidColumnIndex + 1]);
    if (businessId != null) {
      final sectionIndex = paidColumnIndex + 2;
      final sectionId =
          segments.length > sectionIndex + 1 &&
              segments[sectionIndex] == 'section'
          ? numericIdentifier(segments[sectionIndex + 1])
          : null;
      return SaltStoryNavigation(businessId: businessId, sectionId: sectionId);
    }
  }

  if (isZhihuRoute &&
      (uri.path == '/market/manuscript' ||
          (uri.host == 'market' && uri.path == '/manuscript'))) {
    final businessId = numericIdentifier(uri.queryParameters['business_id']);
    if (businessId != null) {
      return SaltStoryNavigation(businessId: businessId);
    }
  }
  if (directBusiness != null) {
    return SaltStoryNavigation(businessId: directBusiness);
  }
  return null;
}

/// Returns the question id embedded in a Zhihu question URL.
///
/// Long-form discovery occasionally returns a regular question deep-link
/// instead of a salt-selected work identifier.  Those links must stay inside
/// the native question flow; opening them in the public web view can return
/// Zhihu's anti-bot JSON document rather than a usable page.
String? saltQuestionIdFromUrl(Object? value) {
  final raw = plainText(value).trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final isZhihuRoute =
      uri.scheme == 'zhihu' ||
      uri.host == 'www.zhihu.com' ||
      uri.host == 'zhihu.com' ||
      uri.host == 'api.zhihu.com';
  if (!isZhihuRoute) return null;
  final segments = uri.scheme == 'zhihu' && uri.host == 'question'
      ? <String>['question', ...uri.pathSegments]
      : uri.pathSegments;
  final questionIndex = segments.indexOf('question');
  if (questionIndex < 0 || questionIndex + 1 >= segments.length) {
    return null;
  }
  final questionId = segments[questionIndex + 1];
  return RegExp(r'^\d+$').hasMatch(questionId) ? questionId : null;
}

String officialSaltSectionUrl({
  required String businessId,
  required String sectionId,
}) {
  final business = numericIdentifier(businessId);
  final section = numericIdentifier(sectionId);
  if (business == null || section == null) {
    throw ArgumentError('盐选作品 ID 和章节 ID 必须是数字。');
  }
  return Uri(
    scheme: 'https',
    host: 'www.zhihu.com',
    pathSegments: ['market', 'paid_column', business, 'section', section],
  ).toString();
}

String? numericIdentifier(Object? value) {
  final text = plainText(value).trim();
  return RegExp(r'^\d+$').hasMatch(text) ? text : null;
}
