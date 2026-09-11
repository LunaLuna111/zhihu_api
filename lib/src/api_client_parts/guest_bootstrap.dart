import 'dart:async';
import 'dart:convert';

import '../api_client.dart';

extension ZhihuApiClientGuestBootstrap on ZhihuApiClient {
  Future<void> bootstrapGuestContext() async {
    await loadLocalMsId(stage: 'pre-init');
    final initDeviceInfo = await cloudIdProvider.deviceInfo();
    final initBodyFields = buildCloudIdBodyFields(initDeviceInfo);
    final initBodyText = ZhihuCloudProtocol.formEncode(initBodyFields);
    debugLogCloudIdBody('init', initBodyFields, initBodyText);
    final initResponse = await requestInitialUdid(initBodyText);
    final initJson = initResponse.jsonMap;
    debugLogBootstrap('init-final', initResponse, initJson);
    if (!initResponse.isSuccess || initJson == null) {
      throw ApiTransportException('Guest 初始化失败：${initResponse.statusLabel}');
    }
    final udid = ZhihuApiClient.stringValue(initJson, 'udid');
    if (udid == null || udid.isEmpty) {
      throw const ApiTransportException('Guest 初始化失败：响应缺少 udid');
    }
    final headerUdid = udid;
    debugPrint(
      'guest udid rawLen=${udid.length} shape=${ZhihuApiClient.valueShape(udid)}',
    );
    final inlineGuest = initJson['guest'];
    Map<String, dynamic>? guest;
    if (inlineGuest is Map<String, dynamic> &&
        ZhihuApiClient.stringValue(inlineGuest, 'access_token') != null) {
      guest = inlineGuest;
      debugPrint('guest using inline init token');
      try {
        guest = await requestGuestToken(headerUdid);
        debugPrint('guest token refresh after inline init succeeded');
      } on ApiTransportException catch (error) {
        debugPrint(
          'guest token refresh after inline init skipped=${error.message}',
        );
      }
    } else {
      guest = await requestGuestToken(headerUdid);
      debugPrint('guest token refresh after init succeeded');
    }
    final selectedGuest = guest;
    if (selectedGuest == null) {
      throw const ApiTransportException('Guest 初始化失败：未取得 guest token');
    }
    await saveGuest(udid: headerUdid, guest: selectedGuest);
    await loadLocalMsId(stage: 'post-init');
    await putAppCloudDeviceIfEligible();
    await warmGuestAccount();
  }

  Map<String, Object?> buildCloudIdBodyFields(
    Map<String, Object?> deviceInfo,
  ) => <String, Object?>{
    ...deviceInfo,
    'app_version': '11.4.0',
    'app_build': '40408',
    'app_ticket': 'fetch empty',
    'bundle_id': 'com.zhihu.android',
    'pre_install': 'undefined',
    'tz_of': PrivacyDeviceProfile.timezoneOffsetSeconds,
  };

  Future<void> loadLocalMsId({required String stage}) async {
    try {
      final value = await cloudIdProvider.localMsId();
      if (value.isNotEmpty) {
        await session.saveMsId(value);
      }
      debugPrint(
        'guest msid $stage len=${value.length} shape=${ZhihuApiClient.valueShape(value)}',
      );
    } on ApiTransportException catch (error) {
      debugPrint('guest msid $stage invalid=${error.message}');
    } on Object catch (error) {
      debugPrint('guest msid $stage unavailable=${error.runtimeType}');
    }
  }

  Future<ApiResponse> requestInitialUdid(String bodyText) async {
    final checkResponse = await sendCloudIdInitPost(
      '/api/account/prod/init/new_flow_check',
      bodyText,
    );
    final checkJson = checkResponse.jsonMap;
    debugLogBootstrap('new-flow-check', checkResponse, checkJson);
    if (checkResponse.isSuccess && checkJson != null) {
      final split = checkJson['split_udid_guest_api'] == true;
      if (split) {
        final udidResponse = await sendCloudIdInitPost(
          '/api/account/prod/init/udid',
          bodyText,
        );
        debugLogBootstrap('init-udid', udidResponse, udidResponse.jsonMap);
        if (udidResponse.isSuccess) return udidResponse;
        debugPrint(
          'guest init/udid fallback status=${udidResponse.statusLabel}',
        );
      }
    } else {
      debugPrint(
        'guest new_flow_check fallback status=${checkResponse.statusLabel}',
      );
    }
    final legacyResponse = await sendCloudIdInitPost(
      '/api/account/prod/init/udid_guest',
      bodyText,
    );
    debugLogBootstrap('init-legacy', legacyResponse, legacyResponse.jsonMap);
    return legacyResponse;
  }

  Future<ApiResponse> sendCloudIdInitPost(String path, String bodyText) async {
    final requestTimestamp = ZhihuApiClient.epochSeconds();
    final cloudSignature = await cloudIdProvider.sign(
      body: bodyText,
      requestTimestamp: requestTimestamp,
    );
    return sendMobileRaw(
      'POST',
      apiUri(path),
      headers: {
        'Authorization': ZhihuCloudProtocol.oauthAuthorization,
        'User-Agent': ZhihuApiClient.appUserAgent,
        'content-type': 'application/x-www-form-urlencoded',
        'x-req-ts': requestTimestamp,
        'x-app-id': ZhihuCloudProtocol.appId,
        'x-sign-version': ZhihuCloudProtocol.signVersion,
        if (session.msId.isNotEmpty) 'X-MS-ID': session.msId,
        'x-req-signature': cloudSignature,
      },
      body: utf8.encode(bodyText),
    );
  }

  Future<void> putAppCloudDeviceIfEligible() async {
    if (session.udid.isEmpty) {
      debugPrint('guest appcloud device PUT skip=empty-udid');
      return;
    }
    try {
      // The official client rebuilds DeviceInfo after CloudID has been stored
      // (CloudIDHelper.m128839Z -> m128842f), so values populated by the
      // asynchronous device SDKs are reflected in the PUT body.  Reusing the
      // pre-init form would produce a different body and therefore a different
      // x-req-signature on devices where OAID/ZXID becomes available meanwhile.
      final updateDeviceInfo = await cloudIdProvider.deviceInfo();
      final updateBodyFields = buildCloudIdBodyFields(updateDeviceInfo);
      final updateBodyText = ZhihuCloudProtocol.formEncode(updateBodyFields);
      debugLogCloudIdBody('appcloud-put', updateBodyFields, updateBodyText);
      final oaid = updateDeviceInfo['oaid']?.toString().trim() ?? '';
      final huaweiOaid =
          updateDeviceInfo['additional_oaid']?.toString().trim() ?? '';
      if (oaid.isEmpty && huaweiOaid.isEmpty) {
        debugPrint('guest appcloud device PUT skip=empty-oaid');
        return;
      }
      final requestTimestamp = ZhihuApiClient.epochSeconds();
      final cloudSignature = await cloudIdProvider.sign(
        body: updateBodyText,
        requestTimestamp: requestTimestamp,
        udid: session.udid,
      );
      final response = await sendMobileRaw(
        'PUT',
        Uri.https(ZhihuApiClient.appCloudHost, '/v1/device'),
        headers: {
          'User-Agent': ZhihuApiClient.appUserAgent,
          'content-type': 'application/x-www-form-urlencoded',
          'x-req-ts': requestTimestamp,
          'x-app-id': ZhihuCloudProtocol.appId,
          'x-sign-version': ZhihuCloudProtocol.signVersion,
          'x-udid': session.udid,
          if (session.msId.isNotEmpty) 'X-MS-ID': session.msId,
          'x-req-signature': cloudSignature,
        },
        body: utf8.encode(updateBodyText),
      );
      debugPrint('guest appcloud device PUT ${response.statusLabel}');
    } on ApiTransportException catch (error) {
      debugPrint('guest appcloud device PUT failed=${error.message}');
    } on Object catch (error) {
      debugPrint('guest appcloud device PUT failed=${error.runtimeType}');
    }
  }

  Future<Map<String, dynamic>> requestGuestToken(String udid) async {
    const bodyText = 'source=com.zhihu.android';
    final response = await sendMobileRaw(
      'POST',
      apiUri('/api/account/prod/guests/token'),
      headers: {
        'Authorization': ZhihuCloudProtocol.oauthAuthorization,
        'x-udid': udid,
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: utf8.encode(bodyText),
    );
    final json = response.jsonMap;
    debugLogBootstrap('token', response, json);
    if (!response.isSuccess || json == null) {
      throw ApiTransportException('Guest token 获取失败：${response.statusLabel}');
    }
    return json;
  }

  Future<void> saveGuest({
    required String udid,
    required Map<String, dynamic> guest,
  }) async {
    final accessToken = ZhihuApiClient.stringValue(guest, 'access_token');
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiTransportException('Guest token 响应缺少 access_token');
    }
    final cookie = guest['cookie'];
    final zCookie = cookie is Map<String, dynamic>
        ? (ZhihuApiClient.stringValue(cookie, 'z_c0') ?? '')
        : '';
    await session.saveGuestSession(
      accessToken: accessToken,
      udid: udid,
      zCookie: zCookie,
    );
    // A clean anonymous account can answer /guest/self immediately while a
    // content edge still returns 40353 for a short propagation window. Only
    // idempotent GETs with that exact code receive this bounded retry budget.
    freshGuestRetryDeadline = DateTime.now().add(const Duration(seconds: 20));
    freshGuestRetryRemaining = retryPolicy.freshGuestMaxAttempts;
    freshGuestRetryAttempt = 0;
    debugPrint(
      'guest saved authLen=${session.authorization.length} '
      'udidLen=${session.udid.length} cookieLen=${session.cookie.length}',
    );
  }

  Future<void> warmGuestAccount() async {
    try {
      final response = await sendMobileRaw(
        'GET',
        apiUri('/guest/self'),
        headers: {
          'Authorization': session.authorization,
          'x-udid': session.udid,
          if (session.cookie.isNotEmpty) 'Cookie': session.cookie,
        },
        body: null,
      );
      debugPrint('guest warmup /guest/self ${response.statusLabel}');
    } on ApiTransportException catch (error) {
      debugPrint('guest warmup /guest/self failed=${error.message}');
    }
  }
}
