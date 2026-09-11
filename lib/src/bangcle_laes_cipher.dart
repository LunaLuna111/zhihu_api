import 'dart:convert';
import 'dart:typed_data';

import 'bangcle_laes_encrypt_tables.dart';

/// Pure Dart implementation of the LAES encryption wrapper used by the
/// mobile account protocol.
///
/// This includes the Java wrapper's adjacent-bit transforms, the native
/// padding convention and the fixed white-box block primitive. It has no
/// native-runtime dependency.
abstract final class BangcleLaesCipher {
  static String? _cachedScheduleSource;
  static Uint8List? _cachedSchedule;

  static final Uint8List _initial = _table(
    BangcleLaesEncryptTables.initial,
    256,
  );
  static final Uint8List _roundXor = _table(
    BangcleLaesEncryptTables.roundXor,
    256,
  );
  static final Uint8List _finalXor = _table(
    BangcleLaesEncryptTables.finalXor,
    256,
  );
  static final Uint8List _table0 = _table(
    BangcleLaesEncryptTables.table0,
    1024,
  );
  static final Uint8List _table1 = _table(
    BangcleLaesEncryptTables.table1,
    1024,
  );
  static final Uint8List _table2 = _table(
    BangcleLaesEncryptTables.table2,
    1024,
  );
  static final Uint8List _table3 = _table(
    BangcleLaesEncryptTables.table3,
    1024,
  );
  static final Uint8List _finalSubstitution = _table(
    BangcleLaesEncryptTables.finalSubstitution,
    256,
  );

  /// Mirrors `C3920b -> laesEncryptByteArr -> C3920b` byte for byte.
  static Uint8List encrypt(
    Uint8List input, {
    required String encodedScheduleHex,
    required Uint8List iv,
  }) {
    if (iv.length != 16) {
      throw ArgumentError.value(iv.length, 'iv.length', 'must be 16');
    }
    final schedule = _decodeSchedule(encodedScheduleHex);
    final padding = 16 - (input.length % 16);
    final output = Uint8List(input.length + padding);
    // The JNI layer adds PKCS#7 after C3920b has transformed the caller's
    // bytes. Its LAES padding helper applies that same affine input encoding
    // to synthetic padding bytes.
    final transformedPadding = _swapAdjacentBits(padding) ^ 0xbb;
    final previous = Uint8List(16);
    final mixed = Uint8List(16);
    final stateA = Uint8List(16);
    final stateB = Uint8List(16);
    final encrypted = Uint8List(16);
    for (var i = 0; i < previous.length; i++) {
      previous[i] = _swapAdjacentBits(iv[i]);
    }
    for (var offset = 0; offset < output.length; offset += 16) {
      for (var i = 0; i < 16; i++) {
        final inputIndex = offset + i;
        final transformedByte = inputIndex < input.length
            ? _swapAdjacentBits(input[inputIndex]) ^ 0xbb
            : transformedPadding;
        mixed[i] = transformedByte ^ previous[i];
      }
      _encryptBlock(mixed, schedule, stateA, stateB, encrypted);
      for (var i = 0; i < 16; i++) {
        final byte = encrypted[i];
        previous[i] = byte;
        output[offset + i] = _swapAdjacentBits(byte);
      }
    }
    return output;
  }

  static void _encryptBlock(
    Uint8List input,
    Uint8List schedule,
    Uint8List stateA,
    Uint8List stateB,
    Uint8List output,
  ) {
    for (var i = 0; i < 16; i++) {
      stateA[i] = _combine(_initial, input[i], schedule[i]);
    }

    const groups = <List<int>>[
      [0, 5, 10, 15],
      [4, 9, 14, 3],
      [8, 13, 2, 7],
      [12, 1, 6, 11],
    ];
    var state = stateA;
    var next = stateB;
    for (var round = 1; round <= 9; round++) {
      for (var column = 0; column < 4; column++) {
        final group = groups[column];
        for (var byte = 0; byte < 4; byte++) {
          final wordByte = 3 - byte;
          final value01 = _combine(
            _roundXor,
            _table0[state[group[0]] * 4 + wordByte],
            _table1[state[group[1]] * 4 + wordByte],
          );
          final value23 = _combine(
            _roundXor,
            _table2[state[group[2]] * 4 + wordByte],
            _table3[state[group[3]] * 4 + wordByte],
          );
          final position = column * 4 + byte;
          next[position] = _combine(
            _roundXor,
            _combine(_roundXor, value01, value23),
            schedule[round * 16 + position],
          );
        }
      }
      final previousState = state;
      state = next;
      next = previousState;
    }

    const permutation = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11];
    for (var i = 0; i < 16; i++) {
      output[i] = _combine(
        _finalXor,
        _finalSubstitution[state[permutation[i]]],
        schedule[160 + i],
      );
    }
  }

  static Uint8List _decodeSchedule(String value) {
    final cached = _cachedSchedule;
    if (cached != null && _cachedScheduleSource == value) return cached;
    if (value.length != 360) {
      throw FormatException('LAES schedule must contain 360 hex characters');
    }
    final encoded = Uint8List(180);
    for (var i = 0; i < encoded.length; i++) {
      final offset = i * 2;
      encoded[i] =
          (_hexNibble(value.codeUnitAt(offset)) << 4) |
          _hexNibble(value.codeUnitAt(offset + 1));
    }
    final schedule = Uint8List(176);
    for (var i = 4; i < encoded.length; i++) {
      schedule[i - 4] = encoded[i] ^ encoded[i % 3];
    }
    _cachedScheduleSource = value;
    _cachedSchedule = schedule;
    return schedule;
  }

  static int _hexNibble(int code) {
    if (code >= 0x30 && code <= 0x39) return code - 0x30;
    if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
    if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
    throw const FormatException('Invalid LAES schedule hex');
  }

  static int _swapAdjacentBits(int value) =>
      (((value & 0x55) << 1) | ((value & 0xaa) >> 1)) & 0xff;

  static int _combine(Uint8List table, int first, int second) =>
      (table[(first & 0xf0) | (second >> 4)] & 0xf0) |
      (table[((first << 4) & 0xf0) ^ (second & 0x0f)] >> 4);

  static Uint8List _table(String value, int expectedLength) {
    final result = Uint8List.fromList(base64Decode(value));
    if (result.length != expectedLength) {
      throw StateError('Invalid embedded LAES encryption table length.');
    }
    return result;
  }
}
