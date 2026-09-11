# zhihu_api

> 感谢 [zly2006/zhihu-plus-plus](https://github.com/zly2006/zhihu-plus-plus/) 项目。本库许多知乎接口的路径、参数和响应结构参照了该项目。

独立的纯 Dart 知乎 API 库，提供请求客户端、路由、响应模型、解析器、评论/内容模型、
手机号登录、二维码登录和盐选接口。

- 版本：<code>0.2.0</code>
- Dart：<code>&gt;=3.8.0 &lt;4.0.0</code>
- 依赖：<code>crypto</code>

## 安装

### Git

~~~yaml
dependencies:
  zhihu_api:
    git:
      url: https://github.com/LunaLuna111/zhihu_api.git
      ref: v0.2.0
~~~

## 导入入口

| 入口 | 内容 |
| --- | --- |
| <code>package:zhihu_api/zhihu_api.dart</code> | 全部公开接口 |
| <code>package:zhihu_api/zhihu_api_core.dart</code> | 客户端、传输、会话、响应和策略 |
| <code>package:zhihu_api/zhihu_api_parsers.dart</code> | JSON、富文本、评论、表情和盐选解析器 |
| <code>package:zhihu_api/zhihu_api_mobile_login.dart</code> | 手机号和 refresh token 登录 |
| <code>package:zhihu_api/zhihu_api_qr_login.dart</code> | 二维码登录 |
| <code>package:zhihu_api/zhihu_api_salt.dart</code> | 盐选接口和模型 |

## 客户端

~~~dart
import 'package:zhihu_api/zhihu_api.dart';

final session = InMemoryApiSession();
final api = ZhihuApiClient(
  session,
  transport: transport,
  cache: InMemoryApiResponseCache(maxEntries: 64),
);

final response = await api.getUri(
  api.recommendationFeedInitialUri(),
  cacheKey: 'recommendation:first',
);

if (response.isSuccess) {
  final rows = extractRows(response.json);
}

api.close();
~~~

## 注入接口

### ApiTransport

~~~dart
abstract interface class ApiTransport {
  Future<ApiResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required int maxResponseBytes,
  });

  void close();
}
~~~

### ApiSession

~~~dart
abstract interface class ApiSession {
  String get authorization;
  String get udid;
  String get cookie;
  String get msId;
  String get sessionKind;
  String get refreshToken;
  String get accountUid;
  String get accountUserId;

  DateTime? get accessTokenExpiry;
  DateTime? get accessTokenRefreshAt;

  bool get hasAuthorization;
  bool get hasCompleteMobileContext;
  bool get hasAccountSession;
  bool get hasRefreshableAccountSession;
  bool get hasGuestSession;
  bool get isAccessTokenExpired;
  bool get shouldRefreshAccountToken;
  bool get supportsPersistentApiSession;
  int get credentialRevision;

  Map<String, String> requestHeaders({
    required String method,
    required Uri uri,
  });

  Future<void> saveMsId(String value);
  Future<void> clearGuestSession();
  Future<void> clear();

  Future<void> saveGuestSession({
    required String accessToken,
    required String udid,
    String zCookie,
  });

  Future<bool> saveAccountSession({
    required String accessToken,
    required String refreshToken,
    required String udid,
    required Duration expiresIn,
    String tokenType,
    String zCookie,
    String? uid,
    String? userId,
    String? scope,
    String? unlockTicket,
    int? lockInSeconds,
    int? expectedCredentialRevision,
  });

  Future<bool> saveQrSession({
    required String cookie,
    required String udid,
    String? uid,
    String? userId,
  });
}
~~~

内置实现：

- <code>InMemoryApiSession</code>
- <code>InMemoryApiResponseCache</code>
- <code>NoopApiResponseCache</code>
- <code>NoopApiLogger</code>
- <code>NoopApiDebugSink</code>
- <code>DefaultApiRetryPolicy</code>
- <code>NoRetryPolicy</code>
- <code>DefaultApiAuthenticationPolicy</code>

### 客户端可选参数

~~~dart
ZhihuApiClient(
  session,
  transport: transport,
  xZseSigner: signer,
  cloudIdProvider: cloudIdProvider,
  mobileLoginBodyEncoder: bodyEncoder,
  logger: logger,
  debugSink: debugSink,
  retryPolicy: retryPolicy,
  authenticationPolicy: authenticationPolicy,
  cache: cache,
);
~~~

可注入接口：

- <code>ApiLogger</code>
- <code>ApiDebugSink</code>
- <code>ApiResponseCache</code>
- <code>ApiRetryPolicy</code>
- <code>ApiAuthenticationPolicy</code>
- <code>ApiCloudIdProvider</code>
- <code>XZseSigner</code>
- <code>MobileLoginBodyEncoder</code>

## 请求方法

| 方法 | 说明 |
| --- | --- |
| <code>get(path, query:, headers:, cacheKey:)</code> | API GET |
| <code>getUri(uri, headers:, cacheKey:)</code> | 指定 URI GET |
| <code>publicWebGet(path, query:)</code> | 公开网页 API GET |
| <code>publicLensVideoGet(videoId)</code> | Lens 视频 GET |
| <code>getSaltUri(uri)</code> | 盐选 GET |
| <code>postJson(path, query:, jsonBody:, headers:)</code> | JSON POST |
| <code>postJsonUri(uri, jsonBody:, headers:)</code> | 指定 URI JSON POST |
| <code>close()</code> | 关闭传输层 |

常量：

| 常量 | 值 |
| --- | --- |
| <code>ZhihuApiClient.apiHost</code> | <code>api.zhihu.com</code> |
| <code>ZhihuApiClient.publicWebHost</code> | <code>www.zhihu.com</code> |
| <code>ZhihuApiClient.lensHost</code> | <code>lens.zhihu.com</code> |
| <code>ZhihuApiClient.appCloudHost</code> | <code>appcloud.zhihu.com</code> |
| <code>ZhihuApiClient.maxResponseBytes</code> | 12 MiB |

## ApiResponse

字段：

| 字段 | 类型 |
| --- | --- |
| <code>uri</code> | <code>Uri</code> |
| <code>statusCode</code> | <code>int</code> |
| <code>bodyBytes</code> | <code>int</code> |
| <code>json</code> | <code>Object?</code> |
| <code>headers</code> | <code>Map&lt;String, String&gt;</code> |
| <code>rawBody</code> | <code>List&lt;int&gt;</code> |
| <code>isSuccess</code> | 2xx |
| <code>jsonMap</code> | 顶层 JSON map |
| <code>error</code> | 归一化错误 map |
| <code>businessCode</code> | 业务码字符串 |
| <code>errorName</code> | 错误名称 |
| <code>serverMessage</code> | 服务端提示 |
| <code>needLogin</code> | 是否需要登录 |
| <code>failure</code> | <code>ApiFailure</code> |
| <code>statusLabel</code> | HTTP 与业务码摘要 |

## ApiFailure

### ApiFailureKind

~~~text
transport
guestContext
networkChallenge
authentication
permission
notFound
rateLimited
server
request
invalidResponse
unknown
~~~

### 账号状态

~~~dart
final action = accountAuthenticationAction(response);

switch (action) {
  case AccountAuthenticationAction.none:
    break;
  case AccountAuthenticationAction.refresh:
    break;
  case AccountAuthenticationAction.logout:
    break;
}
~~~

## Feed、热榜和关注

| URI 方法 | HTTP | 路径 |
| --- | --- | --- |
| <code>recommendationFeedInitialUri()</code> | GET | <code>/topstory/recommend</code> |
| <code>hotListInitialUri()</code> | GET | <code>/topstory/hot-lists/total</code> |
| <code>followingFeedInitialUri(feedType:)</code> | GET | <code>/moments_v3</code> |
| <code>followingMostVisitedInitialUri()</code> | GET | <code>/moments/recent?type=raw</code> |
| <code>followingPeopleRecommendationsUri(...)</code> | GET | <code>/api/v4/moments/recommend_follow_people</code> |
| <code>userRecentActivitiesInitialUri(...)</code> | GET | <code>/moments/recent/{type}/{member}/activities</code> |

## 问题、回答和搜索

| URI 方法 | HTTP | 路径 |
| --- | --- | --- |
| <code>questionDetailUri(questionId)</code> | GET | <code>/questions/{id}</code> |
| <code>questionFeedsInitialUri(questionId)</code> | GET | <code>/questions/{id}/feeds</code> |
| <code>anonymousQuestionAnswersInitialUri(questionId)</code> | GET | <code>/v4/questions/{id}/answers</code> |
| <code>questionAnswersInitialUri(questionId)</code> | GET | 根据 session 选择上述接口 |
| <code>searchInitialUri(keyword:, type:, filters:)</code> | GET | <code>/search_v3</code> |
| <code>searchCustomizeUri()</code> | GET | <code>/search/customize</code> |
| <code>profileContentSearchInitialUri(...)</code> | GET | <code>/search_v3</code> |

## 评论

| URI/请求方法 | HTTP | 路径 |
| --- | --- | --- |
| <code>commentsInitialUri(...)</code> | GET | <code>/comment_v5/{type}/{id}/root_comment</code> |
| <code>commentListHeadersUri(...)</code> | GET | <code>/comment_v5/{type}/{id}/list-headers</code> |
| <code>commentRepliesInitialUri(commentId)</code> | GET | <code>/comment_v5/comment/{id}/child_comment</code> |
| <code>commentEmoticonGroupsUri()</code> | GET | <code>/people/self/sticker-groups/v2</code> |
| <code>commentEmoticonGroupUri(groupId)</code> | GET | <code>/sticker-groups/{id}?business=message</code> |
| <code>commentLinkParseUri(url:, scene:)</code> | GET | <code>/content/publish/parse_url</code> |
| <code>commentCreateUri(...)</code> | POST | <code>/comment_v5/{type}/{id}/comment</code> |
| <code>commentSegmentCreateUri(...)</code> | POST | <code>/comment_v5/{type}/{id}/segment/comment</code> |
| <code>commentDeleteUri(commentId)</code> | DELETE | <code>/api/v4/comment_v5/comment/{id}</code> |

表情加载：

~~~dart
final groups = await api.loadCommentEmoticonGroups();
~~~

## 评论和内容写入

| 方法 | HTTP | 路径 |
| --- | --- | --- |
| <code>createComment</code> | POST | <code>/comment_v5/{type}/{id}/comment</code> |
| <code>createSegmentComment</code> | POST | <code>/comment_v5/{type}/{id}/segment/comment</code> |
| <code>createSaltComment</code> | POST | <code>/comment_v5/{type}/{id}/comment</code> |
| <code>deleteComment</code> | DELETE | <code>/api/v4/comment_v5/comment/{id}</code> |
| <code>setCommentLiked</code> | POST/DELETE | <code>/reaction/comments/{id}/like</code> |
| <code>voteAnswer</code> | POST | <code>/answers/{id}/voters</code> |
| <code>voteContent</code> | POST | <code>/answers/{id}/voters</code> 或 <code>/articles/{id}/voters</code> |
| <code>setPinLiked</code> | POST/DELETE | <code>/pins/{id}/reactions</code> |
| <code>favoriteAnswer</code> | POST/DELETE | <code>/answers/{id}/collections_v2</code> |
| <code>favoriteContent</code> | POST/DELETE | 内容收藏路由 |
| <code>publishAnswer</code> | POST | <code>/content/drafts</code> → <code>/content/publish</code> |
| <code>deleteAnswer</code> | DELETE | <code>/answers/{id}</code> |
| <code>setQuestionFollowing</code> | POST/DELETE | <code>/questions/{id}/followers</code> |
| <code>setQuestionInvitee</code> | POST/DELETE | <code>/questions/{id}/invitees</code> |
| <code>setUserFollowing</code> | POST/DELETE | <code>/people/{id}/followers</code> |
| <code>sendTextMessage</code> | POST | <code>/messages</code> |

评论 body：

~~~dart
final body = ZhihuApiClient.buildCommentBody(
  content: '评论内容',
  replyCommentId: replyCommentId,
  sticker: sticker,
  selection: selection,
);

final response = await api.createComment(
  contentType: 'answer',
  contentId: answerId,
  content: '评论内容',
  replyCommentId: replyCommentId,
  sticker: sticker,
  selection: selection,
);
~~~

回答 body：

~~~dart
final body = ZhihuApiClient.buildAnswerEditorBody(
  questionId: questionId,
  questionTitle: questionTitle,
  content: answerContent,
);
~~~

## 用户、收藏、通知

### 用户资料

| 方法 | 路径 |
| --- | --- |
| <code>userProfileInitialUri(memberId)</code> | <code>/people/{id}/profile</code> |
| <code>userProfileDetailUri(memberId)</code> | <code>/people/{id}/profile/detail</code> |
| <code>userProfileTabsInitialUri(memberId)</code> | <code>/people/{id}/profile/tab</code> |
| <code>userFollowersInitialUri(memberId)</code> | <code>/people/{id}/followers</code> |
| <code>userFolloweesInitialUri(memberId)</code> | <code>/people/{id}/followees</code> |
| <code>userAnswersInitialUri(memberId)</code> | <code>/people/{id}/answers</code> |
| <code>userArticlesInitialUri(memberId)</code> | <code>/people/{id}/articles</code> |
| <code>userColumnsInitialUri(memberId)</code> | <code>/people/{id}/columns</code> |
| <code>userCollectionsInitialUri(memberId)</code> | <code>/people/{id}/collections_v2</code> |
| <code>collectionContentsInitialUri(collectionId)</code> | <code>/collections/{id}/contents</code> |

### 通知和私信

| 方法 | 路径 |
| --- | --- |
| <code>notificationsMessageInitialUri()</code> | <code>/notifications/v3/message/v3</code> |
| <code>notificationsUnreadUri()</code> | <code>/notifications/v3/count/v3</code> |
| <code>notificationEntryInitialUri(entryName)</code> | <code>/notifications/v3/timeline/entry/{entry}</code> |
| <code>notificationInviteInitialUri()</code> | <code>/notifications/v3/timeline/entry/invite</code> |
| <code>messagesInitialUri(senderId)</code> | <code>/messages</code> |
| <code>notificationSettingsUri()</code> | <code>/settings/new/notification</code> |

### 通知写入

- <code>markAllNotificationsRead()</code>
- <code>markNotificationEntryRead(entryName)</code>
- <code>updateNotificationSettings(...)</code>

## 手机号登录

<code>package:zhihu_api/zhihu_api_mobile_login.dart</code>：

| 方法 | 路径 |
| --- | --- |
| <code>requestLoginDigits</code> | <code>/api/account/prod/auth/digits</code> |
| <code>signInWithDigits</code> | <code>/api/account/prod/sign_in</code> |
| <code>signInWithPassword</code> | <code>/api/account/prod/sign_in</code> |
| <code>refreshAccountSession</code> | <code>/api/account/prod/sign_in</code> |
| <code>verifyNewAccountToken</code> | 账号验证接口 |
| <code>sendEncryptedLoginForm</code> | 登录表单发送接口 |

相关类型：

- <code>MobileLoginGrant</code>
- <code>MobileLoginContract</code>
- <code>MobileDigitsResult</code>
- <code>MobileSignInResult</code>
- <code>MobileLoginBodyEncoder</code>
- <code>MobileLoginBodyCipher</code>
- <code>DartMobileLoginBodyCipher</code>

## 二维码登录

<code>package:zhihu_api/zhihu_api_qr_login.dart</code>：

~~~dart
final code = await api.requestQrLoginCode();
final poll = await api.pollQrLogin(
  token: code.token,
  cookie: code.cookie,
);
final result = await api.completeQrLogin(poll);
~~~

类型：

- <code>QrLoginCode</code>
- <code>QrLoginPoll</code>
- <code>requestQrLoginCode</code>
- <code>prefetchQrLoginContext</code>
- <code>pollQrLogin</code>
- <code>completeQrLogin</code>

## 盐选接口

<code>package:zhihu_api/zhihu_api_salt.dart</code>：

### 首页、书架和书城

| 方法 | 路径 |
| --- | --- |
| <code>saltStoryHomeUri()</code> | <code>/km-vip-zhihu-web/vip_tab/svip_story</code> |
| <code>saltBookshelfUri(...)</code> | <code>/km-vip-zhihu-web/vip_tab/member/like_list</code> |
| <code>saltCloudShelfUri(...)</code> | <code>/pluton/shelves</code> |
| <code>saltShelfHomeUri()</code> | <code>/bazaar/vip_tab/shelf</code> |
| <code>saltShelfAnnotationsUri(...)</code> | <code>/km-vip-zhihu-web/vip_tab/member/list_blank</code> |
| <code>saltShelfHistoryUri(...)</code> | <code>/bazaar/learning_history</code> |
| <code>saltShelfBookListsUri(...)</code> | <code>/pluton/book_list/list</code> |
| <code>saltStoryCategoriesUri()</code> | <code>/pluton/category/story/header</code> |
| <code>saltLongStoryDiscoverUri(...)</code> | <code>/km-vip-zhihu-web/vip_tab/vip_pin/discover</code> |
| <code>saltBookCityConditionsUri()</code> | <code>/bazaar/vip_tab/book_city/conditions</code> |
| <code>saltBookCitySectionInitialUri(...)</code> | <code>/bazaar/vip_tab/book_city/section/{tagType}</code> |
| <code>saltBookCitySkuListUri(...)</code> | <code>/bazaar/vip_tab/book_city/sku_list/{tagType}</code> |
| <code>saltBookshelfMutationUri()</code> | <code>/km-indep-home-comm/member/book_shelf</code> |

### 作品、目录和正文

| 方法 | HTTP | 路径 |
| --- | --- | --- |
| <code>saltCatalogInitialUri(...)</code> | GET | <code>/km-indep-home-comm/catalog/{wellId}</code> |
| <code>saltCatalogBoundaryUri(...)</code> | GET | 同上，使用 <code>after_id</code>/<code>before_id</code> |
| <code>saltWorkSectionListUri(workId)</code> | GET | <code>/km-indep-home-comm/work/{workId}/section_list</code> |
| <code>saltProgressUri(wellId)</code> | GET | <code>/km-indep-home-comm/progress/{wellId}</code> |
| <code>saltManuCacheUri(...)</code> | GET | <code>/remix-pre-web/manuscript/{business}/{section}/manu_cache</code> |
| <code>saltManuCoreUri(...)</code> | GET | <code>/remix-pre-web/manuscript/{business}/{section}/manu_core</code> |
| <code>saltContentUri(...)</code> | GET | <code>/remix-pre-web/manuscript/{business}/{section}/content</code> |
| <code>saltArticleCodeUri()</code> | POST | <code>/remix-pre-web/manuscript/code</code> |
| <code>saltAnnotationsUri(sectionId:)</code> | GET | <code>/remix-pre-web/manuscript/annotations</code> |

### 盐选评论

| 方法 | 路径 |
| --- | --- |
| <code>saltCommentsInitialUri(...)</code> | <code>/comment_v5/{type}/{id}/root_comment</code> |
| <code>saltCommentListHeadersUri(...)</code> | <code>/comment_v5/{type}/{id}/list-headers</code> |
| <code>saltCommentCreateUri(...)</code> | <code>/comment_v5/{type}/{id}/comment</code> |
| <code>addSaltToBookshelf(...)</code> | <code>/km-indep-home-comm/member/book_shelf</code> |

## 内容和评论模型

### ContentNode

~~~dart
enum ContentNodeKind { text, image, link, sticker, video }

class ContentNode {
  const ContentNode({
    required this.id,
    required this.kind,
    this.text = '',
    this.url = '',
    this.title = '',
    this.startOffset = 0,
    this.endOffset = 0,
  });
}
~~~

字段：

- <code>id</code>
- <code>kind</code>
- <code>text</code>
- <code>url</code>
- <code>title</code>
- <code>startOffset</code>
- <code>endOffset</code>

### ContentSelection

字段：

- <code>contentType</code>
- <code>contentId</code>
- <code>nodeId</code>
- <code>paragraphId</code>
- <code>segmentIds</code>
- <code>quote</code>
- <code>startOffset</code>
- <code>endOffset</code>
- <code>source</code>

方法：

- <code>isValid</code>
- <code>hasSegmentTarget</code>
- <code>segmentId</code>
- <code>normalizedQuote</code>
- <code>toSegmentJson()</code>
- <code>toJson()</code>

### CommentReplyTarget

字段：

- <code>contentType</code>
- <code>contentId</code>
- <code>rootCommentId</code>
- <code>replyCommentId</code>
- <code>targetUserId</code>
- <code>targetUserName</code>
- <code>source</code>

属性：

- <code>isReply</code>
- <code>hint</code>
- <code>toJson()</code>

## 表情模型

### CommentEmoticon

字段：

- <code>id</code>
- <code>title</code>
- <code>groupId</code>
- <code>groupType</code>
- <code>staticImageUrl</code>
- <code>dynamicImageUrl</code>
- <code>stickerType</code>
- <code>status</code>
- <code>assetImagePath</code>

属性和方法：

- <code>isVisible</code>
- <code>isInlineEmoji</code>
- <code>isVip</code>
- <code>imageUrl</code>
- <code>submissionMarkup()</code>
- <code>CommentEmoticon.fromJson</code>
- <code>CommentEmoticon.fallback</code>

### CommentEmoticonGroup

字段：

- <code>id</code>
- <code>title</code>
- <code>type</code>
- <code>iconUrl</code>
- <code>selectedIconUrl</code>
- <code>version</code>
- <code>emoticons</code>
- <code>assetIconPath</code>
- <code>assetSelectedIconPath</code>

方法：

- <code>CommentEmoticonGroup.fromJson</code>
- <code>withDetail</code>
- <code>toJson</code>
- <code>parseList</code>
- <code>fallback</code>

## 解析器

| 函数/类型 | 用途 |
| --- | --- |
| <code>stringMap</code> | Map 类型归一化 |
| <code>plainText</code> | HTML/实体转纯文本 |
| <code>jsonInt</code> | 数字字段归一化 |
| <code>extractRows</code> | Feed 列表提取 |
| <code>extractSearchRows</code> | 搜索结果提取 |
| <code>normalizeComponentCard</code> | ComponentCard 归一化 |
| <code>contentVideosOf</code> | 视频提取 |
| <code>extractSaltStoryRows</code> | 盐选故事提取 |
| <code>extractSaltLongStoryRows</code> | 盐选长篇提取 |
| <code>extractSaltShelfRows</code> | 盐选书架提取 |
| <code>saltCatalogNavigationOf</code> | 目录合并和章节导航 |
| <code>saltParagraphAnnotationsOf</code> | 段落评论提取 |
| <code>SaltArticleCodeEnvelope</code> | 正文 code envelope |
| <code>SaltManuscriptEnvelope</code> | 正文 envelope |
| <code>SaltChapterFetchStatus</code> | 正文读取状态 |

## 测试

~~~sh
dart pub get
dart analyze
dart test
~~~

## 许可证

MIT，见 [LICENSE](https://github.com/LunaLuna111/zhihu_api/blob/main/LICENSE)。
