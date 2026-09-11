import 'dart:convert';
import 'dart:typed_data';

import 'api_response.dart';
import 'bangcle_laes_cipher.dart';
import 'x_zse_signer.dart';

/// Encodes the encrypted form body used by mobile account routes.
///
/// The wire body is not a form containing one encrypted field. The client
/// first produces an ordinary form, then replaces the entire body with
/// `Base64(LAES(formBytes))` while retaining the form content type.
class MobileLoginBodyEncoder {
  MobileLoginBodyEncoder({MobileLoginBodyCipher? cipher})
    : _cipher = cipher ?? DartMobileLoginBodyCipher();

  final MobileLoginBodyCipher _cipher;

  Future<Uint8List> encode(Map<String, String> fields) async {
    if (fields.isEmpty) {
      throw const ApiTransportException('登录表单不能为空');
    }
    final plain = Uint8List.fromList(utf8.encode(formEncode(fields)));
    final key = XZseSigner.decodedEncryptKey();
    final encrypted = await _cipher.encryptBytes(
      input: plain,
      key: key,
      iv: Uint8List.fromList(ascii.encode(XZseSigner.ivAscii)),
    );
    if (encrypted.isEmpty) {
      throw const ApiTransportException('登录正文 LAES 返回空结果');
    }
    return Uint8List.fromList(ascii.encode(base64.encode(encrypted)));
  }

  static String formEncode(Map<String, String> fields) => fields.entries
      .map((entry) => '${_component(entry.key)}=${_component(entry.value)}')
      .join('&');

  static String _component(String value) =>
      Uri.encodeQueryComponent(value).replaceAll('%20', '+');
}

abstract class MobileLoginBodyCipher {
  Future<Uint8List> encryptBytes({
    required Uint8List input,
    required String key,
    required Uint8List iv,
  });
}

class DartMobileLoginBodyCipher implements MobileLoginBodyCipher {
  @override
  Future<Uint8List> encryptBytes({
    required Uint8List input,
    required String key,
    required Uint8List iv,
  }) async {
    return BangcleLaesCipher.encrypt(input, encodedScheduleHex: key, iv: iv);
  }
}
