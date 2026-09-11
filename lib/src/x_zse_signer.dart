import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'api_response.dart';
import 'bangcle_laes_cipher.dart';

class XZseSigner {
  XZseSigner({XZseCipher? cipher}) : _cipher = cipher ?? DartXZseCipher();

  static const encryptVersion = '101_1_1.0';
  static const signaturePrefix = '1.0_';
  static const ivAscii = 'f0551856aa575faa';
  static const keySha256 =
      '2ec2d0acc665cf5b51cfa90ce22e6b233499fa224b06fe5f5f272f75242a0e8a';
  static const selfTestMd5Lower = '00000000000000000000000000000000';

  static const _encodedEncryptKey =
      'G3CD7841BEC31FE71BF58964AF7E3C7843CD28C4BE833F37BB35FC31AAAE491843F82821FB932AD7BB10AC04EF3E19B8531D0D01CEA69AE2FB6599149A1BD95D36B818718EE36A82BE40FC11EA5B490826DD6824FE767FC2BE75EC218A7E493856FD3D41BBC62AF7AB757C51FF0E694D139D18D1FBB65F371BE0AC44AF0E0958E6C87834DE968AE2FE55FC549F0B293846D80851CEB60FD2BB55EC110A6B0C28768D58119B963A87DB4599310A0BD948739D68618BB67A928B059C219A4B19AD43A828C1BBC31F32AB50DC319A5B493D63F81D04FBC35FC78E35AC610A4BD97853ED0871EE663FA7DE258C811AAE6C0846F87D61BEF67FE2DE45AC64CA3E6C0D13A82821CE632F979B05FC54EA6E490873A808048EC65A92DB65C931DF1E1C08030D2D018EE62F82BBF0AC94EA5E094856CDA804EBB35F82BE50C961FF6B6928339D5811BEE35A82CE259C84CA3B695803087854EEF34AF7DB656C01EA6B5C7863180864DBD32AF2C';
  static const _secneoKeystreamHex = '09e3b57adf50cb49866ef0289285a3b7';
  static final String _decodedEncryptKey = _recoverAndValidateEncryptKey();

  final XZseCipher _cipher;

  Future<Map<String, String>> signHeaders({
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final normalized = Map<String, String>.of(headers);
    final preimage = buildPreimage(uri: uri, headers: normalized, body: body);
    final md5Lower = md5.convert(utf8.encode(preimage)).toString();
    final key = decodedEncryptKey();
    final cipherBytes = await _cipher.encryptMd5Hex(
      md5Lower: md5Lower,
      key: key,
      iv: Uint8List.fromList(ascii.encode(ivAscii)),
    );
    if (cipherBytes.length != 48) {
      throw ApiTransportException('X-Zse cipher length=${cipherBytes.length}');
    }
    _removeHeader(normalized, 'X-Zse-96');
    _removeHeader(normalized, 'X-Zse-93');
    normalized['X-Zse-96'] = signaturePrefix + base64.encode(cipherBytes);
    normalized['X-Zse-93'] = encryptVersion;
    return normalized;
  }

  Future<XZseSelfTestResult> selfTest() async {
    try {
      final cipherBytes = await _cipher.encryptMd5Hex(
        md5Lower: selfTestMd5Lower,
        key: decodedEncryptKey(),
        iv: Uint8List.fromList(ascii.encode(ivAscii)),
      );
      return XZseSelfTestResult(
        available: true,
        cipherBytes: cipherBytes.length,
        signatureBytes:
            signaturePrefix.length + base64.encode(cipherBytes).length,
        cipherSha256: sha256.convert(cipherBytes).toString(),
      );
    } catch (error) {
      return XZseSelfTestResult(
        available: false,
        cipherBytes: 0,
        signatureBytes: 0,
        cipherSha256: '',
        error: error.runtimeType.toString(),
      );
    }
  }

  static String buildPreimage({
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) {
    // The preimage starts with the configured protocol version rather than an
    // arbitrary caller-supplied header. The same value is written back as the
    // X-Zse-93 field.
    final fields = <String>[encryptVersion, encodedRequestTarget(uri)];
    // x-app-version participates in the preimage. The similarly named
    // x-api-version header does not.
    final appVersion = headerValue(headers, 'x-app-version');
    if (appVersion != null) fields.add(appVersion);
    final authorization = headerValue(headers, 'Authorization');
    if (authorization != null) fields.add(authorization);
    final udid = headerValue(headers, 'x-udid');
    if (udid != null) fields.add(udid);
    if (body != null && body.isNotEmpty && body.length <= 4096) {
      fields.add(utf8.decode(body, allowMalformed: false));
    }
    return fields.join('+');
  }

  static String encodedRequestTarget(Uri uri) {
    final serialized = uri.toString();
    final prefix = '${uri.scheme}://${uri.authority}';
    final target = serialized.startsWith(prefix)
        ? serialized.substring(prefix.length)
        : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
    final fragmentStart = target.indexOf('#');
    final withoutFragment = fragmentStart >= 0
        ? target.substring(0, fragmentStart)
        : target;
    return withoutFragment.isEmpty ? '/' : withoutFragment;
  }

  static String? headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static String decodedEncryptKey() => _decodedEncryptKey;

  static String _recoverAndValidateEncryptKey() {
    final encoded = _encodedEncryptKey.substring(1);
    final keyBytes = _hexToBytes(_secneoKeystreamHex);
    final cipherBytes = _hexToBytes(encoded);
    final decoded = Uint8List(cipherBytes.length);
    for (var index = 0; index < cipherBytes.length; index++) {
      decoded[index] = cipherBytes[index] ^ keyBytes[index % keyBytes.length];
    }
    final key = ascii.decode(decoded);
    if (sha256.convert(ascii.encode(key)).toString() != keySha256) {
      throw const ApiTransportException('X-Zse key hash mismatch');
    }
    return key;
  }

  static void _removeHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    final matches = headers.keys
        .where((key) => key.toLowerCase() == lower)
        .toList();
    for (final key in matches) {
      headers.remove(key);
    }
  }

  static Uint8List _hexToBytes(String value) {
    if (value.length.isOdd) {
      throw FormatException('odd hex length: ${value.length}');
    }
    final output = Uint8List(value.length ~/ 2);
    for (var index = 0; index < value.length; index += 2) {
      final high = _hexNibble(value.codeUnitAt(index));
      final low = _hexNibble(value.codeUnitAt(index + 1));
      output[index ~/ 2] = (high << 4) | low;
    }
    return output;
  }

  static int _hexNibble(int code) {
    if (code >= 0x30 && code <= 0x39) return code - 0x30;
    if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
    if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
    throw FormatException('non-hex byte: $code');
  }
}

abstract class XZseCipher {
  Future<Uint8List> encryptMd5Hex({
    required String md5Lower,
    required String key,
    required Uint8List iv,
  });
}

class DartXZseCipher implements XZseCipher {
  static final RegExp _md5LowerPattern = RegExp(r'^[0-9a-f]{32}$');

  @override
  Future<Uint8List> encryptMd5Hex({
    required String md5Lower,
    required String key,
    required Uint8List iv,
  }) async {
    if (!_md5LowerPattern.hasMatch(md5Lower)) {
      throw const ApiTransportException('X-Zse MD5 format error');
    }
    return BangcleLaesCipher.encrypt(
      Uint8List.fromList(ascii.encode(md5Lower)),
      encodedScheduleHex: key,
      iv: iv,
    );
  }
}

class XZseSelfTestResult {
  const XZseSelfTestResult({
    required this.available,
    required this.cipherBytes,
    required this.signatureBytes,
    required this.cipherSha256,
    this.error,
  });

  final bool available;
  final int cipherBytes;
  final int signatureBytes;
  final String cipherSha256;
  final String? error;
}
