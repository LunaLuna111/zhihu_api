import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'api_cloud_id.dart';
import 'api_debug.dart';
import 'api_logger.dart';
import 'api_policies.dart';
import 'api_response.dart';
import 'api_session.dart';
import 'api_transport.dart';
import 'comment_emoticons.dart';
import 'content_interaction_models.dart';
import 'mobile_login_body_encoder.dart';
import 'mobile_login_models.dart';
import 'privacy_device_profile.dart';
import 'x_zse_signer.dart';

export 'api_client_parts/bootstrap_and_diagnostics.dart';
export 'api_client_parts/content_writes.dart';
export 'api_client_parts/guest_bootstrap.dart';
export 'api_client_parts/mobile_login.dart';
export 'api_client_parts/negative_feedback.dart';
export 'api_client_parts/qr_login.dart';
export 'api_client_parts/request_pipeline.dart';
export 'api_client_parts/routes.dart';
export 'api_client_parts/salt_routes.dart';
export 'api_client_parts/transport.dart';
export 'api_cloud_id.dart';
export 'api_debug.dart';
export 'api_logger.dart';
export 'api_policies.dart';
export 'api_response.dart';
export 'api_session.dart';
export 'api_transport.dart';
export 'comment_emoticons.dart';
export 'content_interaction_models.dart';
export 'mobile_login_body_encoder.dart';
export 'mobile_login_contract.dart';
export 'mobile_login_models.dart';
export 'negative_feedback.dart';
export 'privacy_device_profile.dart';
export 'x_zse_signer.dart';

class ZhihuApiClient {
  ZhihuApiClient(
    ApiSession session, {
    required this.transport,
    XZseSigner? xZseSigner,
    ApiCloudIdProvider? cloudIdProvider,
    MobileLoginBodyEncoder? mobileLoginBodyEncoder,
    ApiLogger? logger,
    ApiDebugSink? debugSink,
    ApiRetryPolicy? retryPolicy,
    ApiAuthenticationPolicy? authenticationPolicy,
    ApiResponseCache? cache,
  }) : _session = session,
       xZseSigner = xZseSigner ?? XZseSigner(),
       cloudIdProvider = cloudIdProvider ?? const DefaultApiCloudIdProvider(),
       mobileLoginBodyEncoder =
           mobileLoginBodyEncoder ?? MobileLoginBodyEncoder(),
       apiLogger = logger ?? const NoopApiLogger(),
       debugSink = debugSink ?? const NoopApiDebugSink(),
       retryPolicy = retryPolicy ?? const DefaultApiRetryPolicy(),
       authenticationPolicy =
           authenticationPolicy ?? const DefaultApiAuthenticationPolicy(),
       cache = cache ?? const NoopApiResponseCache();

  static const apiHost = 'api.zhihu.com';
  static const appCloudHost = 'appcloud.zhihu.com';
  static const publicWebHost = 'www.zhihu.com';
  static const lensHost = 'lens.zhihu.com';
  static const saltParagraphCommentObjectType = 'doc_sections';
  static const maxResponseBytes = 12 * 1024 * 1024;
  static const debugSaltAuthorizationRelay = bool.fromEnvironment(
    'ZH_SALT_AUTH_RELAY',
  );
  // The question feed uses the AnswerListV2 contract with media_detail,
  // order, and show_detail fields.
  static const questionFeedsInitialInclude =
      'big_card_summary,media_detail,reaction_instruction,is_author,is_thanked,'
      'voting,is_favorited,label_info,content_text_length,reactions';
  static const searchVerticalInfo = '0,0,0,0,0,0,0,0,0,0,0,0';
  static const Map<String, Object> questionFeedsInitialQuery = {
    'order': 'default',
    'show_detail': 1,
  };
  static final Random searchRandom = Random.secure();
  static const appUserAgent = PrivacyDeviceProfile.appUserAgent;

  final ApiSession _session;

  ApiSession get session => _session;

  final ApiTransport transport;
  final XZseSigner xZseSigner;
  final ApiCloudIdProvider cloudIdProvider;
  final MobileLoginBodyEncoder mobileLoginBodyEncoder;
  final ApiLogger apiLogger;
  final ApiDebugSink debugSink;
  final ApiRetryPolicy retryPolicy;
  final ApiAuthenticationPolicy authenticationPolicy;
  final ApiResponseCache cache;
  Future<void>? guestBootstrap;
  Future<void>? guestRecovery;
  Future<String>? appInfoLoad;
  Future<String>? qrLoginPrefetch;
  DateTime? qrLoginPrefetchedAt;
  String qrLoginPrefetchedCookie = '';
  String appInfo = '';
  String loginCookie = '';
  Future<MobileSignInResult>? accountRefresh;
  Future<void>? accountLogout;
  DateTime? freshGuestRetryDeadline;
  int freshGuestRetryRemaining = 0;
  int freshGuestRetryAttempt = 0;

  static Map<String, Object?> buildCommentBody({
    required String content,
    String replyCommentId = '',
    CommentEmoticon? sticker,
    ContentSelection? selection,
  }) {
    final normalizedText = content.trim();
    final markup = sticker?.submissionMarkup() ?? '';
    final text = '$normalizedText$markup';
    if (text.isEmpty || text.runes.length > 5000) {
      throw const ApiTransportException('评论不能为空且不能超过 5000 字');
    }
    final replyId = replyCommentId.trim();
    if (replyId.isNotEmpty && !RegExp(r'^\d+$').hasMatch(replyId)) {
      throw const ApiTransportException('被回复评论 ID 必须是数字');
    }
    // Preserve the wire-field order for both root comments and replies.
    return <String, Object?>{
      'comment_id': '',
      'content': text,
      'extra_params': '',
      'has_img': false,
      'reply_comment_id': replyId,
      'score': 0,
      'selected_settings': <Object?>[],
      'segment': selection?.hasSegmentTarget == true
          ? selection!.toSegmentJson()
          : null,
      'sticker_type': markup.isEmpty
          ? null
          : <String>[sticker!.isVip ? 'vip' : 'normal'],
      'unfriendly_check': 'strict',
    };
  }

  /// Builds the payload used by the answer editor. The same map shape can be
  /// sent to `/content/drafts` and `/content/publish`.
  static Map<String, Object?> buildAnswerEditorBody({
    required String questionId,
    required String questionTitle,
    required String content,
    String? traceId,
    String? extraTag,
  }) {
    final normalizedQuestionId = questionId.trim();
    final normalizedTitle = questionTitle.trim();
    final normalizedContent = content.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalizedQuestionId)) {
      throw const ApiTransportException('问题 ID 必须是数字');
    }
    if (normalizedContent.isEmpty || normalizedContent.runes.length > 100000) {
      throw const ApiTransportException('回答不能为空且不能超过 100000 字');
    }
    final resolvedTraceId = traceId?.trim().isNotEmpty == true
        ? traceId!.trim()
        : newUuidV4();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(resolvedTraceId)) {
      throw const ApiTransportException('回答发布 traceId 必须是 UUID v4');
    }
    final resolvedExtraTag = extraTag?.trim().isNotEmpty == true
        ? extraTag!.trim()
        : 'fakeurl://edit_answer_new/question_$normalizedQuestionId';
    return <String, Object?>{
      'data': <String, Object?>{
        'answerConfig': <String, Object?>{'bind_article_id': null},
        'reprint': <String, Object?>{'copyright_permission': 'public'},
        'subscribe': <String, Object?>{'follow_enabled': null},
        'zvideoCollections': <String, Object?>{'collections': null},
        'contribute': <String, Object?>{'questionId': null},
        'column': <String, Object?>{'column': <Object?>[]},
        'media': <String, Object?>{'medias': null},
        'title': <String, Object?>{'title': normalizedTitle},
        'creationStatement': <String, Object?>{
          'disclaimer_desc': null,
          'disclaimer_type': null,
          'disclaimer_status': null,
        },
        'publishSwitch': <String, Object?>{'draft_type': 'normal'},
        'hybrid': <String, Object?>{
          'attachment': <String, Object?>{},
          'meta': <String, Object?>{
            'linkCard': <String, Object?>{'all': 0, 'data': <Object?>[]},
            'fileLinkCard': <String, Object?>{'all': 0},
            'eduCard': <String, Object?>{'all': 0},
            'mcnLinkCard': <String, Object?>{'all': 0},
            'adLinkCard': <String, Object?>{'all': 0},
            'image': <String, Object?>{
              'all': 0,
              'uploading': 0,
              'error': <String, Object?>{},
            },
            'video': <String, Object?>{
              'all': 0,
              'uploading': 0,
              'error': <String, Object?>{},
              'data': <Object?>[],
            },
          },
          'textLength': normalizedContent.runes.length,
          'html': answerHtml(normalizedContent),
        },
        'extra_info': <String, Object?>{
          'extra_tag': resolvedExtraTag,
          'publish_type': 'answer',
          'extra_is_anonymous': false,
          'key_router_raw_url': 'zhihu://answer/editor/$normalizedQuestionId',
          'question_id': normalizedQuestionId,
          'key_router_module': 'content',
        },
        'appreciate': <String, Object?>{'tagline': '', 'can_reward': false},
        'originalReprint': <String, Object?>{'originalReprint': 'original'},
        'draft': <String, Object?>{
          'contentId': '',
          'id': normalizedQuestionId,
          'isPublished': false,
        },
        'publish': <String, Object?>{'traceId': resolvedTraceId},
        'anonymity': <String, Object?>{'isAnonymity': false},
        'commentsPermission': <String, Object?>{'comment_permission': 'all'},
        'thanksInvitation': <String, Object?>{
          'thank_inviter': null,
          'thank_inviter_name': null,
          'thank_inviter_status': null,
        },
      },
      'action': 'answer',
      'template_id': '0',
    };
  }

  static String publishedAnswerId(ApiResponse response) {
    final data = response.jsonMap?['data'];
    if (data is! Map) return '';
    final result = data['result'];
    Object? decoded = result;
    if (result is String) {
      try {
        decoded = jsonDecode(result);
      } on FormatException {
        return '';
      }
    }
    if (decoded is! Map) return '';
    final id = decoded['id'] ?? decoded['answer_id'];
    return id?.toString() ?? '';
  }

  static String answerHtml(String content) {
    const escape = HtmlEscape(HtmlEscapeMode.element);
    return content
        .split(RegExp(r'\r?\n'))
        .map((line) => '<p>${escape.convert(line)}</p>')
        .join();
  }

  static String newUuidV4() {
    final bytes = List<int>.generate(16, (_) => searchRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final raw = hex.join();
    return '${raw.substring(0, 8)}-${raw.substring(8, 12)}-'
        '${raw.substring(12, 16)}-${raw.substring(16, 20)}-'
        '${raw.substring(20)}';
  }

  static String numericIdentifier(String value, String label) {
    final normalized = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw ApiTransportException('$label 必须是数字');
    }
    return normalized;
  }

  static const notificationEntryNames = <String>{
    'comment',
    'like',
    'favorite',
    'follow',
    'invite',
    'system',
    'system_message',
  };

  /// Official search uses one 32-character lowercase-hex request correlation
  /// ID. It is telemetry, not an account/device credential, and is regenerated
  /// for every initial search rather than persisted.
  static String newSearchId() {
    const alphabet = '0123456789abcdef';
    return List.generate(
      32,
      (_) => alphabet[searchRandom.nextInt(alphabet.length)],
    ).join();
  }

  static String cookiePairsOnly(String raw) {
    if (raw.trim().isEmpty) return '';
    const cookieAttributes = {
      'domain',
      'path',
      'expires',
      'max-age',
      'httponly',
      'secure',
      'samesite',
      'priority',
      'partitioned',
    };
    final values = <String, String>{};
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      for (final part in line.split(';')) {
        final pair = part.trim();
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        final name = pair.substring(0, separator).trim();
        if (cookieAttributes.contains(name.toLowerCase()) ||
            !RegExp(r'^[^=;\s]+$').hasMatch(name)) {
          continue;
        }
        values[name] = pair.substring(separator + 1).trim();
      }
    }
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static String mergeCookieHeaders(
    String first, [
    String second = '',
    String third = '',
  ]) {
    final values = <String, String>{};
    for (final source in [first, second, third]) {
      for (final part in source.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        final name = part.substring(0, separator).trim();
        final value = part.substring(separator + 1).trim();
        if (name.isNotEmpty) values[name] = value;
      }
    }
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static int? positiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static int? nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static String randomHex(int length) {
    const alphabet = '0123456789abcdef';
    return List.generate(
      length,
      (_) => alphabet[searchRandom.nextInt(alphabet.length)],
    ).join();
  }

  static void removeHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    final matches = headers.keys
        .where((key) => key.toLowerCase() == lower)
        .toList();
    for (final key in matches) {
      headers.remove(key);
    }
  }

  static Map<String, String> canonicalizeHeaders(Map<String, String> headers) {
    final canonical = <String, String>{};
    for (final entry in headers.entries) {
      removeHeader(canonical, entry.key);
      canonical[entry.key] = entry.value;
    }
    return canonical;
  }

  static String epochSeconds() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  static String? stringValue(Map<String, dynamic> source, String key) {
    return source[key]?.toString();
  }

  void debugLogBootstrap(
    String stage,
    ApiResponse response,
    Map<String, dynamic>? json,
  ) {
    if (!debugSink.enabled) return;
    final keys = json == null ? <String>[] : json.keys.take(12).toList();
    final cookie = json?['cookie'];
    final guest = json?['guest'];
    final guestCookie = guest is Map<String, dynamic> ? guest['cookie'] : null;
    final split = json?['split_udid_guest_api'];
    final afterPrivacy = json?['after_privacy_agreed'];
    final msidNeed = json?['msid_need'];
    debugSink.write(
      'guest bootstrap $stage status=${response.statusLabel} '
      'bodyBytes=${response.bodyBytes} keys=$keys '
      'split=$split afterPrivacy=$afterPrivacy msidNeed=$msidNeed '
      'accessLen=${stringValue(json ?? const {}, 'access_token')?.length ?? 0} '
      'cookieMap=${cookie is Map} guestMap=${guest is Map} '
      'guestAccessLen=${guest is Map<String, dynamic> ? (stringValue(guest, 'access_token')?.length ?? 0) : 0} '
      'guestCookieMap=${guestCookie is Map}',
    );
  }

  static const Set<String> officialCloudIdBodyFields = {
    'additional_oaid',
    'android_id',
    'app_build',
    'app_install_time',
    'app_ticket',
    'app_version',
    'bt_ck',
    'bundle_id',
    'cp_ct',
    'cp_fq',
    'cp_tp',
    'cp_us',
    'd_n',
    'device_token',
    'fr_mem',
    'fr_st',
    'icid',
    'idfa',
    'im_e',
    'im_e2',
    'im_s',
    'im_s2',
    'latitude',
    'longitude',
    'mc_ad',
    'mcc',
    'meid',
    'mnc',
    'nt_st',
    'oaid',
    'ph_br',
    'ph_md',
    'ph_os',
    'ph_sn',
    'pre_install',
    'pvd_nm',
    'tt_mem',
    'tt_st',
    'tz_of',
    'uuid',
    'zx_aid',
    'zx_expired',
    'zx_tag',
    'zx_zid',
  };

  static const Set<String> cloudIdShapeFields = {
    'android_id',
    'app_install_time',
    'bt_ck',
    'cp_fq',
    'cp_tp',
    'mc_ad',
    'mcc',
    'nt_st',
    'ph_md',
    'pvd_nm',
  };

  void debugLogCloudIdBody(
    String stage,
    Map<String, Object?> fields,
    String bodyText,
  ) {
    if (!debugSink.enabled) return;
    final implementedNames = fields.keys.toSet();
    final includedNames = <String>{
      for (final part in bodyText.split('&'))
        if (part.isNotEmpty) Uri.decodeQueryComponent(part.split('=').first),
    };
    final missingImplementation = officialCloudIdBodyFields
        .where((field) => !implementedNames.contains(field))
        .toList();
    final extraImplementation = implementedNames
        .where((field) => !officialCloudIdBodyFields.contains(field))
        .toList();
    final omittedByFormEncode = implementedNames
        .where((field) => !includedNames.contains(field))
        .toList();
    final shape = <String, String>{
      for (final field in cloudIdShapeFields)
        if (includedNames.contains(field))
          field: valueShape(fields[field]?.toString() ?? ''),
    };
    debugSink.write(
      'guest cloudid body stage=$stage '
      'bodyLen=${utf8.encode(bodyText).length} '
      'implemented=${implementedNames.length} included=${includedNames.length} '
      'missingImplementation=$missingImplementation '
      'extraImplementation=$extraImplementation '
      'omittedByFormEncode=$omittedByFormEncode keyShapes=$shape',
    );
  }

  void debugLogRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    List<int>? body, {
    required String profile,
  }) {
    if (!debugSink.enabled) return;
    if (uri.host != apiHost && uri.host != appCloudHost) return;
    final interesting =
        uri.path.startsWith('/topstory/') ||
        uri.path.startsWith('/km-vip-zhihu-web/vip_tab/') ||
        uri.path.startsWith('/questions/') ||
        uri.path.startsWith('/comment_v5/') ||
        uri.path.startsWith('/km-indep-home-vip-comment/') ||
        uri.path.startsWith('/people/') ||
        uri.path.startsWith('/columns/') ||
        uri.path.startsWith('/remix-pre-web/manuscript/') ||
        uri.path == '/v1/device' ||
        uri.path == '/guest/self' ||
        uri.path == '/api/account/prod/init/udid_guest' ||
        uri.path == '/api/account/prod/init/new_flow_check' ||
        uri.path == '/api/account/prod/init/udid' ||
        uri.path == '/api/account/prod/guests/token';
    if (!interesting) return;
    final authorization = headerValue(headers, 'Authorization') ?? '';
    final cookie = headerValue(headers, 'Cookie') ?? '';
    final udid = headerValue(headers, 'x-udid') ?? '';
    final msId = headerValue(headers, 'X-MS-ID') ?? '';
    final zse96 = headerValue(headers, 'X-Zse-96') ?? '';
    final appInfo = headerValue(headers, 'x-app-za') ?? '';
    final hasAdStyles = headers.keys.any(
      (key) => key.toLowerCase() == 'x-ad-styles',
    );
    final safePath = uri.path.startsWith('/people/')
        ? uri.path.replaceFirst(
            RegExp(r'^/people/[^/]+'),
            '/people/{member_id}',
          )
        : uri.path.startsWith('/remix-pre-web/manuscript/')
        ? uri.path.replaceFirst(
            RegExp(r'^/remix-pre-web/manuscript/\d+/\d+'),
            '/remix-pre-web/manuscript/{business_id}/{section_id}',
          )
        : uri.path;
    final headerNames = headers.keys.map((name) => name.toLowerCase()).toList()
      ..sort();
    final safeQuery = uri.path.startsWith('/remix-pre-web/manuscript/')
        ? 'window_width=${uri.queryParameters['window_width'] ?? ''}'
        : 'len=${uri.query.length}';
    debugSink.write(
      'request $method $safePath query=$safeQuery '
      'profile=$profile '
      'api=${headerValue(headers, 'x-api-version') ?? ''} '
      'adStyles=$hasAdStyles '
      'authScheme=${authScheme(authorization)} '
      'authLen=${authorization.length} udidLen=${udid.length} '
      'cookieLen=${cookie.length} msidLen=${msId.length} '
      'appZaLen=${appInfo.length} '
      'zse96Len=${zse96.length} '
      'bodyLen=${body?.length ?? 0} udidShape=${ZhihuApiClient.valueShape(udid)} '
      'headers=$headerNames',
    );
  }

  void debugLogResponse(String method, Uri uri, ApiResponse response) {
    if (!debugSink.enabled) return;
    if (uri.host != apiHost && uri.host != appCloudHost) return;
    final interesting =
        uri.path.startsWith('/topstory/') ||
        uri.path.startsWith('/km-vip-zhihu-web/vip_tab/') ||
        uri.path.startsWith('/questions/') ||
        uri.path.startsWith('/comment_v5/') ||
        uri.path.startsWith('/km-indep-home-vip-comment/') ||
        uri.path.startsWith('/people/') ||
        uri.path.startsWith('/columns/') ||
        uri.path.startsWith('/remix-pre-web/manuscript/') ||
        uri.path == '/v1/device' ||
        uri.path == '/guest/self' ||
        uri.path == '/api/account/prod/init/udid_guest' ||
        uri.path == '/api/account/prod/init/new_flow_check' ||
        uri.path == '/api/account/prod/init/udid' ||
        uri.path == '/api/account/prod/guests/token';
    if (!interesting) return;
    final safePath = uri.path.startsWith('/people/')
        ? uri.path.replaceFirst(
            RegExp(r'^/people/[^/]+'),
            '/people/{member_id}',
          )
        : uri.path.startsWith('/remix-pre-web/manuscript/')
        ? uri.path.replaceFirst(
            RegExp(r'^/remix-pre-web/manuscript/\d+/\d+'),
            '/remix-pre-web/manuscript/{business_id}/{section_id}',
          )
        : uri.path;
    debugSink.write(
      'response $method $safePath '
      '${uri.path.startsWith('/remix-pre-web/manuscript/') ? 'HTTP ${response.statusCode}' : response.statusLabel} '
      'bodyBytes=${response.bodyBytes} '
      'errorName=${response.errorName} '
      'serverMessage=${response.serverMessage}',
    );
  }

  static String? headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static String authScheme(String authorization) {
    final lower = authorization.toLowerCase();
    if (lower.startsWith('bearer ')) return 'bearer';
    if (lower.startsWith('oauth ')) return 'oauth';
    return authorization.isEmpty ? 'none' : 'other';
  }

  static String valueShape(String value) {
    if (value.isEmpty) return 'empty';
    var upper = 0;
    var lower = 0;
    var digit = 0;
    var hyphen = 0;
    var underscore = 0;
    var other = 0;
    for (final codeUnit in value.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (RegExp(r'[A-Z]').hasMatch(char)) {
        upper++;
      } else if (RegExp(r'[a-z]').hasMatch(char)) {
        lower++;
      } else if (RegExp(r'[0-9]').hasMatch(char)) {
        digit++;
      } else if (char == '-') {
        hyphen++;
      } else if (char == '_') {
        underscore++;
      } else {
        other++;
      }
    }
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
    return 'upper=$upper lower=$lower digit=$digit hyphen=$hyphen '
        'underscore=$underscore other=$other uuid=$uuid';
  }

  void debugPrint(String message) {
    if (debugSink.enabled) debugSink.write('[zhihu-api] $message');
  }
}
