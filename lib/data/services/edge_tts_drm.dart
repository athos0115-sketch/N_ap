import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Microsoft Edge Read Aloud v2 DRM (`Sec-MS-GEC` v2) 토큰 생성 및 Clock Skew 보정 모듈.
class EdgeTtsDrm {
  EdgeTtsDrm._();

  static const String trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String chromiumFullVersion = '143.0.3650.75';
  static const String chromiumMajorVersion = '143';
  static const String secMsGecVersion = '2-$chromiumFullVersion';

  static const int _winEpochSeconds = 11644473600;
  static const double _secondsTo100Ns = 1e7;
  static const int _u32Mask = 0xFFFFFFFF;

  static double clockSkewSeconds = 0.0;

  static const List<int> _sha256Initial = [
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
  ];

  static const List<int> _sha256State = [
    0xFD9FBEA2,
    0x91243CE7,
    0xBE499094,
    0xCD2E1E0A,
    0x6C006F49,
    0x04BD35AB,
    0xFEB0A7E4,
    0x03EFFBD2,
  ];

  static const List<int> _sha256Schedule = [
    0xEB24BF9E,
    0x1558691F,
    0xA0C09EE2,
    0x0CFA32BA,
    0xA622EE8C,
    0xD1DD9491,
    0xC0DD25A0,
    0xF9E70AB6,
    0xF0C31573,
    0x7058CE4E,
    0x7188E606,
    0x00E5AB33,
    0xD258B060,
    0x72766564,
  ];

  static const List<int> _sha256RoundConstants = [
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ];

  static const int _sha256Adjustment = 0xC9DC06A7;
  static const int _sha256Sigma0Adjustment = 0x059C0B80;
  static const int _sha256Sigma1Adjustment = 0x000B92C0;

  static final List<int> _sha256BlockConstants = [
    ..._sha256RoundConstants.sublist(0, 14),
    _sha256Adjustment,
    ..._sha256RoundConstants.sublist(15),
  ];

  static const List<(int, int)> _cs64Coefficients = [
    (0xE82E91B1, 0xB32700D0),
    (0x44DE24C6, 0x88DFF51D),
    (0x3BEB65BC, 0x29514038),
    (0xC89C5933, 0xB328CBDF),
    (0x8D1EC211, 0xD405B4D5),
    (0x314EF5D5, 0x26E55F3C),
    (0xE92491B1, 0x607801C6),
    (0xF0A5B9D5, 0x82B2C1FB),
    (0x06064CF3, 0xFA51A3DA),
    (0xDA79FA60, 0x207CC464),
    (0xBED20560, 0x3C3C74F3),
    (0x89F9C9F8, 0xD2D14B61),
    (0x35FA38C6, 0xBB04A2C1),
    (0xCB49E3C6, 0xC5626167),
  ];

  static const int _cs64Factor = 0x82893933;
  static const int _cs64Adjustment0 = 0xF2F90B1A;
  static const int _cs64Adjustment1 = 0x0B1A0000;

  static final Random _secureRandom = _createRandom();

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static double getUnixTimestamp() {
    return DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0 +
        clockSkewSeconds;
  }

  /// 403 응답 등의 서버 Date 헤더로 클라이언트-서버 시간 오차를 보정한다.
  static void adjustClockSkewFromDate(DateTime serverUtcDate) {
    final serverSeconds = serverUtcDate.toUtc().millisecondsSinceEpoch / 1000.0;
    final currentSeconds = getUnixTimestamp();
    clockSkewSeconds += serverSeconds - currentSeconds;
  }

  /// 무작위 32자리 16진수 MUID 쿠키 값을 생성한다.
  static String generateMuid() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      final byte = _secureRandom.nextInt(256);
      buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }

  /// v2 `Sec-MS-GEC` 보안 토큰 (`<16자리 CS64>-<64자리 변형 SHA256>`)을 생성한다.
  static String generateSecMsGecV2({double? unixTimestamp}) {
    var ticks = unixTimestamp ?? getUnixTimestamp();
    ticks += _winEpochSeconds;
    ticks -= ticks % 300;
    ticks *= _secondsTo100Ns;
    final strToHash = '${ticks.toStringAsFixed(0)}$trustedClientToken';
    final data = Uint8List.fromList(ascii.encode(strToHash));

    final digest = _sha256Digest(data);
    final cs64Bytes = _cs64DigestBytes(data, digest);
    return '${_toUpperHex(cs64Bytes)}-${_toUpperHex(digest)}';
  }

  static int _rotr32(int value, int shift) {
    final v = value & _u32Mask;
    return ((v >>> shift) | (v << (32 - shift))) & _u32Mask;
  }

  static int _rol16(int value) {
    final v = value & _u32Mask;
    return ((v << 16) | (v >>> 16)) & _u32Mask;
  }

  /// 32비트 부호 없는 곱셈의 하위 32비트를 안전하게 계산한다.
  static int _mul32(int a, int b) {
    final ua = a & _u32Mask;
    final ub = b & _u32Mask;
    final lo = (ua & 0xFFFF) * ub;
    final hi = (((ua >>> 16) & 0xFFFF) * ub) << 16;
    return (lo + hi) & _u32Mask;
  }

  static int _sigma0(int value) {
    final v = value & _u32Mask;
    return (_rotr32(v, 7) ^ _rotr32(v, 18) ^ (v >>> 3)) & _u32Mask;
  }

  static int _sigma1(int value) {
    final v = value & _u32Mask;
    return (_rotr32(v, 17) ^ _rotr32(v, 19) ^ (v >>> 10)) & _u32Mask;
  }

  static List<int> _sha256Rounds(
    List<int> state,
    List<int> words, {
    int firstRound = 0,
  }) {
    var a = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];
    var f = state[5];
    var g = state[6];
    var h = state[7];
    final constants =
        firstRound == 14 ? _sha256BlockConstants : _sha256RoundConstants;

    for (var i = firstRound; i < 64; i++) {
      final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final ch = g ^ (e & (f ^ g));
      final t1 = (h + s1 + ch + constants[i] + words[i]) & _u32Mask;
      final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final maj = (a & b) | (c & (a | b));
      final t2 = (s0 + maj) & _u32Mask;

      h = g;
      g = f;
      f = e;
      e = (d + t1) & _u32Mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _u32Mask;
    }

    return [a, b, c, d, e, f, g, h];
  }

  static void _expandSha256Schedule(List<int> words, {int firstWord = 16}) {
    for (var i = firstWord; i < 64; i++) {
      final s1 = _sigma1(words[i - 2]);
      final s0 = _sigma0(words[i - 15]);
      words.add((s1 + words[i - 7] + s0 + words[i - 16]) & _u32Mask);
    }
  }

  static List<int> _sha256Init(Uint8List prefix7) {
    final w14 = (prefix7[0] << 16) | (prefix7[1] << 8) | prefix7[2];
    final w15 = (prefix7[3] << 24) |
        (prefix7[4] << 16) |
        (prefix7[5] << 8) |
        prefix7[6];
    final words = List<int>.filled(14, 0, growable: true)
      ..add(w14)
      ..add(w15);

    for (var i = 16; i < 30; i++) {
      var value = _sha256Schedule[i - 16];
      if (i - 2 >= 14) {
        final s1 = _sigma1(words[i - 2]);
        value += i == 16 ? (s1 ^ _sha256Sigma1Adjustment) : s1;
      }
      if (i - 7 >= 14) {
        value += words[i - 7];
      }
      if (i - 15 >= 14) {
        final s0 = _sigma0(words[i - 15]);
        value += i == 29 ? (s0 ^ _sha256Sigma0Adjustment) : s0;
      }
      words.add(value & _u32Mask);
    }

    words.add(
      (_sigma1(words[28]) +
              words[23] +
              _sigma0(words[15]) +
              words[14] +
              _sha256Adjustment -
              _sha256RoundConstants[14]) &
          _u32Mask,
    );
    _expandSha256Schedule(words, firstWord: 31);
    final working = _sha256Rounds(_sha256State, words, firstRound: 14);
    return List<int>.generate(
      8,
      (i) => (_sha256Initial[i] + working[i]) & _u32Mask,
    );
  }

  static Uint8List _sha256Digest(Uint8List data) {
    if (data.length < 7) {
      throw ArgumentError('Token data must contain at least 7 bytes.');
    }
    final length = 57 + data.length;
    final zeroPadLen = (55 - length) % 64;
    final tailLen = data.length - 7;
    final padded = Uint8List(tailLen + 1 + zeroPadLen + 8);

    padded.setRange(0, tailLen, data, 7);
    padded[tailLen] = 0x80;

    final bitLength = length * 8;
    final bd = ByteData.sublistView(padded);
    bd.setUint64(padded.length - 8, bitLength, Endian.big);

    var state = _sha256Init(data.sublist(0, 7));
    for (var offset = 0; offset < padded.length; offset += 64) {
      final words = List<int>.generate(
        16,
        (i) => bd.getUint32(offset + i * 4, Endian.big),
        growable: true,
      );
      _expandSha256Schedule(words);
      final working = _sha256Rounds(state, words);
      state = List<int>.generate(8, (i) => (state[i] + working[i]) & _u32Mask);
    }

    final out = Uint8List(32);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      outBd.setUint32(i * 4, state[i], Endian.big);
    }
    return out;
  }

  static List<int> _wordsLe4Even(Uint8List data) {
    final rem = (-data.length) % 4;
    final padded = Uint8List(data.length + rem);
    padded.setRange(0, data.length, data);
    if (padded.isEmpty) return const [];

    final bd = ByteData.sublistView(padded);
    final words = List<int>.generate(
      padded.length ~/ 4,
      (i) => bd.getUint32(i * 4, Endian.little),
      growable: true,
    );
    if (words.length.isOdd) {
      words.add(0);
    }
    return words;
  }

  static Uint8List _cs64DigestBytes(Uint8List data, Uint8List digest) {
    final digestBd = ByteData.sublistView(digest);
    final keyA = digestBd.getUint32(0, Endian.little) | 1;
    final keyB = digestBd.getUint32(4, Endian.little) | 1;

    final factorA = _mul32(keyA, _cs64Factor);
    final factorB = _mul32(keyB, _cs64Factor);

    final terms = <int>[];
    final offsets = <int>[];
    for (var i = 0; i < _cs64Coefficients.length; i++) {
      final (coeff, offset) = _cs64Coefficients[i];
      terms.add(_mul32(coeff, i.isEven ? factorA : factorB));
      offsets.add(offset);
    }

    final prefixed = Uint8List(data.length + 1);
    prefixed.setRange(1, prefixed.length, data);
    final dataWords = _wordsLe4Even(prefixed);

    for (var i = 0; i < dataWords.length; i++) {
      final word = dataWords[i];
      var term = _mul32(word, i.isEven ? keyA : keyB);
      var offset = _mul32(
        _rol16(word),
        i.isEven ? 0xEF0569FB : 0xC31713DB,
      );
      if (i == 0) {
        term = (term + _mul32(_cs64Adjustment0, factorA)) & _u32Mask;
        offset = (offset + _cs64Adjustment1) & _u32Mask;
      }
      terms.add(term);
      offsets.add(offset);
    }

    var swapAcc = 0;
    var swapLast = 0;
    var state = 0;
    var acc = 0;

    for (var i = 0; i < terms.length; i += 2) {
      final x = terms[i];
      final y = terms[i + 1];

      var t = _rol16((offsets[i] + x) & _u32Mask);
      var q = _mul32(t, 0x76F50F34);
      swapAcc = (swapAcc + _mul32(_rol16(q), 0xC3EFEA97) + q) & _u32Mask;

      t = _rol16((offsets[i + 1] + y) & _u32Mask);
      q = _mul32(t, 0x1881CE3C);
      swapLast = (_mul32(_rol16(q), 0x35BD1EC9) + q) & _u32Mask;
      swapAcc = (swapAcc + swapLast) & _u32Mask;

      state = (_mul32(state, keyA) + x) & _u32Mask;
      state = _mul32(_rol16(state), 0xCF98B111);
      state = _mul32(_rol16(state), 0x87085B9F);
      state = _mul32(_rol16(state), 0x12CEB96D);
      state = _mul32(_rol16(state), 0x257E1D83);
      acc = (acc + state) & _u32Mask;

      t = (_mul32(state, keyB) + y) & _u32Mask;
      t = _mul32(_rol16(t), 0xA27416F5);
      t = _mul32(_rol16(t), 0xD38396FF);
      state = _mul32(_rol16(_mul32(_rol16(t), 0x7C932B89)), 0xBFA49F69);
      acc = (acc + state) & _u32Mask;
    }

    final out = Uint8List(8);
    final outBd = ByteData.sublistView(out);
    outBd.setUint32(0, (swapLast ^ state) & _u32Mask, Endian.little);
    outBd.setUint32(4, (swapAcc ^ acc) & _u32Mask, Endian.little);
    return out;
  }

  static String _toUpperHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }
}
