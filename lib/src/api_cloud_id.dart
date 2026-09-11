import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Device information and CloudID signing are injectable because Android's
/// OAID/MS-ID provider is platform-specific.
abstract interface class ApiCloudIdProvider {
  Future<Map<String, Object?>> deviceInfo();

  Future<String> appInfo();

  Future<String> localMsId();

  Future<String> sign({
    required String body,
    required String requestTimestamp,
    String udid,
    String fallbackUdid,
  });
}

abstract final class ZhihuCloudProtocol {
  static const appId = '1355';
  static const appSecret = 'dd49a835-56e7-4a0f-95b5-efd51ea5397f';
  static const oauthAuthorization = 'oauth 8d5227e0aaaa4797a763ac64e0c3b8';
  static const signVersion = '2';

  static String formEncode(Map<String, Object?> source) {
    final keys = source.keys.toList()..sort();
    final parts = <String>[];
    for (final key in keys) {
      final value = source[key];
      if (value == null || value is String && value.isEmpty) continue;
      parts.add(
        '${Uri.encodeQueryComponent(key)}='
        '${Uri.encodeQueryComponent(value.toString())}',
      );
    }
    return parts.join('&');
  }

  static String? wrapCloudIdForHeader(String raw) {
    if (raw.isEmpty) return null;
    var checksum = 0;
    for (final code in raw.codeUnits) {
      checksum = (checksum + code) % ((code % 8) + 4);
    }
    final marker = (checksum + raw.length) % 64;
    final first = marker & 0xff;
    final last = (marker + 1 + first) & 0xff;
    if (first == 0x0a || first == 0x0d || last == 0x0a || last == 0x0d) {
      return null;
    }
    return String.fromCharCode(first) + raw + String.fromCharCode(last);
  }
}

class DefaultApiCloudIdProvider implements ApiCloudIdProvider {
  const DefaultApiCloudIdProvider();

  @override
  Future<Map<String, Object?>> deviceInfo() =>
      Future<Map<String, Object?>>.value(const {});

  @override
  Future<String> appInfo() => Future<String>.value('');

  @override
  Future<String> localMsId() => Future<String>.value('');

  @override
  Future<String> sign({
    required String body,
    required String requestTimestamp,
    String udid = '',
    String fallbackUdid = '',
  }) async {
    final preimage =
        '${ZhihuCloudProtocol.appId}${ZhihuCloudProtocol.signVersion}'
        '$body$udid$requestTimestamp';
    return Hmac(
      sha1,
      utf8.encode(ZhihuCloudProtocol.appSecret),
    ).convert(utf8.encode(preimage)).toString();
  }
}

Uint8List copyBytes(List<int> values) => Uint8List.fromList(values);
