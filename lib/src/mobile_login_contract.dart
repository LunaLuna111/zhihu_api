import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Value-level contract for mobile account authentication.
///
enum MobileLoginGrant { digits, password, refreshToken }

class MobileLoginContract {
  const MobileLoginContract._();

  static const captchaPath = '/captcha';
  static const requestDigitsPath = '/api/account/prod/auth/digits';
  static const signInPath = '/api/account/prod/sign_in';
  static const environmentPath = '/api/account/prod/sign_in/environment';
  static const logoutPath = '/api/account/prod/client_logout';
  static const accountPath = '/api/account/prod/account';
  static const source = 'com.zhihu.android';
  static const clientId = '8d5227e0aaaa4797a763ac64e0c3b8';
  static const clientSecret = 'ecbefbf6b17e47ecb9035107866380';
  static const apiVersion = '3.0.93';
  static const encryptVersion = '101_1_1.0';

  /// Header names supported by the authorized mobile request profile.
  /// `content-length` and `accept-encoding` are owned by the HTTP transport.
  static const observedRequestHeaderNames = <String>{
    'accept-encoding',
    'authorization',
    'content-length',
    'content-type',
    'cookie',
    'user-agent',
    'x-ad',
    'x-api-version',
    'x-app-build',
    'x-app-bundleid',
    'x-app-flavor',
    'x-app-version',
    'x-app-za',
    'x-b3-traceid',
    'x-client-ri',
    'x-ms-id',
    'x-network-type',
    'x-page-id',
    'x-suger',
    'x-udid',
    'x-zse-93',
    'x-zst-81',
    'x-zst-82',
  };

  /// These values are produced by device/telemetry subsystems and are not
  /// constants or logical login form fields. The client forwards them when
  /// its own runtime has a value, but never copies identifiers from the
  /// official App process.
  static const optionalRuntimeHeaderNames = <String>{
    'x-ad',
    'x-ms-id',
    'x-page-id',
    'x-suger',
    'x-zst-81',
    'x-zst-82',
  };

  static const requestDigitsFields = <String>{
    'username',
    'sms_type',
    'client_id',
  };

  static const signInBaseFields = <String>{
    'grant_type',
    'client_id',
    'source',
    'timestamp',
    'signature',
  };

  static String grantValue(MobileLoginGrant grant) => switch (grant) {
    MobileLoginGrant.digits => 'digits',
    MobileLoginGrant.password => 'password',
    MobileLoginGrant.refreshToken => 'refresh_token',
  };

  static String normalizeUsername(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?[0-9]{6,20}$').hasMatch(normalized)) {
      throw const FormatException('请输入含国家/地区代码的有效手机号');
    }
    return normalized;
  }

  /// Password login accepts the same international phone form as SMS login,
  /// and the email identifier shown by the official account form.
  static String normalizePasswordUsername(String value) {
    final trimmed = value.trim();
    final phone = trimmed.replaceAll(RegExp(r'[\s()-]'), '');
    if (RegExp(r'^\+?[0-9]{6,20}$').hasMatch(phone)) return phone;
    if (RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return trimmed;
    }
    throw const FormatException('请输入有效的手机号或邮箱');
  }

  static String normalizeDigits(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(normalized)) {
      throw const FormatException('验证码应为 6 位数字');
    }
    return normalized;
  }

  static Map<String, String> buildRequestDigitsFields({
    required String username,
    required String clientId,
    String smsType = 'text',
  }) {
    final normalizedClientId = _required(clientId, 'client_id');
    final normalizedSmsType = smsType.trim().toLowerCase();
    if (normalizedSmsType != 'text' && normalizedSmsType != 'voice') {
      throw const FormatException('sms_type 只允许 text 或 voice');
    }
    return {
      'username': normalizeUsername(username),
      'sms_type': normalizedSmsType,
      'client_id': normalizedClientId,
    };
  }

  /// Builds the signed fields used by the account authorization exchange.
  ///
  /// Signature preimage:
  ///   grant_type + client_id + source + epoch_seconds
  /// and the HMAC-SHA1 key is the configured client secret.
  static Map<String, String> buildSignInFields({
    required MobileLoginGrant grant,
    required String username,
    required String credential,
    required String clientId,
    required String clientSecret,
    required int epochSeconds,
  }) {
    if (epochSeconds <= 0) {
      throw const FormatException('timestamp 必须是正整数秒');
    }
    final normalizedClientId = _required(clientId, 'client_id');
    final normalizedSecret = _required(clientSecret, 'client_secret');
    final grantType = grantValue(grant);
    final timestamp = epochSeconds.toString();
    final preimage = '$grantType$normalizedClientId$source$timestamp';
    final signature = Hmac(
      sha1,
      utf8.encode(normalizedSecret),
    ).convert(utf8.encode(preimage)).toString();
    final fields = <String, String>{
      'grant_type': grantType,
      'client_id': normalizedClientId,
      'source': source,
      'timestamp': timestamp,
      'signature': signature,
    };
    switch (grant) {
      case MobileLoginGrant.digits:
        fields['username'] = normalizeUsername(username);
        fields['digits'] = normalizeDigits(credential);
        break;
      case MobileLoginGrant.password:
        fields['username'] = normalizePasswordUsername(username);
        fields['password'] = _required(credential, 'password');
        break;
      case MobileLoginGrant.refreshToken:
        fields['refresh_token'] = _required(credential, 'refresh_token');
        break;
    }
    return fields;
  }

  static String _required(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.contains('\r') ||
        normalized.contains('\n')) {
      throw FormatException('$label 不能为空或包含换行');
    }
    return normalized;
  }
}
