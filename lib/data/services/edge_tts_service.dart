import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../core/utils/ssml_parser.dart';
import 'edge_tts_drm.dart';

/// Edge Neural TTS 선택 가능 한국어/다국어 음성 모델 정보.
class EdgeVoiceOption {
  const EdgeVoiceOption({
    required this.id,
    required this.shortLabel,
    required this.label,
    required this.gender,
  });

  final String id;
  final String shortLabel;
  final String label;
  final String gender;
}

/// Microsoft Edge Neural TTS WebSocket 스트리밍 클라이언트.
/// 디스크에 파일을 저장하지 않고 순수 MP3 바이트(`Uint8List`)를 RAM으로 반환한다.
class EdgeTtsService {
  EdgeTtsService({
    this.maxRetries = 3,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  static const String defaultMaleVoice = 'ko-KR-InJoonNeural';
  static const String defaultFemaleVoice = 'ko-KR-SunHiNeural';

  /// 실시간 한국어 합성이 검증된 6종 음성 (여성 4종 · 남성 2종).
  static const List<EdgeVoiceOption> availableKoreanVoices = [
    EdgeVoiceOption(
      id: defaultFemaleVoice,
      shortLabel: 'SunHi',
      label: '선희 (한국어 · 선명한 여성)',
      gender: 'Female',
    ),
    EdgeVoiceOption(
      id: 'en-US-AvaMultilingualNeural',
      shortLabel: 'Ava',
      label: '에이바 (다국어 · 따뜻한 여성)',
      gender: 'Female',
    ),
    EdgeVoiceOption(
      id: 'en-US-EmmaMultilingualNeural',
      shortLabel: 'Emma',
      label: '엠마 (다국어 · 맑고 차분한 여성)',
      gender: 'Female',
    ),
    EdgeVoiceOption(
      id: 'fr-FR-VivienneMultilingualNeural',
      shortLabel: 'Vivienne',
      label: '비비안 (다국어 · 부드러운 여성)',
      gender: 'Female',
    ),
    EdgeVoiceOption(
      id: defaultMaleVoice,
      shortLabel: 'InJoon',
      label: '인준 (한국어 · 차분한 남성)',
      gender: 'Male',
    ),
    EdgeVoiceOption(
      id: 'ko-KR-HyunsuMultilingualNeural',
      shortLabel: 'Hyunsu',
      label: '현수 (다국어 · 부드러운 남성)',
      gender: 'Male',
    ),
  ];

  static String shortLabelFor(String voiceId) {
    for (final v in availableKoreanVoices) {
      if (v.id == voiceId) return v.shortLabel;
    }
    if (voiceId == 'ko-KR-HyunsuNeural') return 'Hyunsu';
    return 'Voice';
  }

  /// 구버전 저장 음성 ID(`ko-KR-HyunsuNeural`)를 공식 ID로 정규화한다.
  static String normalizeVoiceId(String voiceId) {
    if (voiceId == 'ko-KR-HyunsuNeural') {
      return 'ko-KR-HyunsuMultilingualNeural';
    }
    for (final v in availableKoreanVoices) {
      if (v.id == voiceId) return voiceId;
    }
    return defaultFemaleVoice;
  }

  static const String _wssBaseUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const String _outputFormat = 'audio-24khz-48kbitrate-mono-mp3';

  final int maxRetries;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Random _random = Random();

  /// 단일 문장 또는 텍스트 청크를 Edge Neural TTS로 합성해 RAM 바이트로 반환한다.
  Future<Uint8List> synthesizeSentence({
    required String text,
    String voice = defaultMaleVoice,
    double speed = 1.0,
    int basePitchHz = 0,
    bool enableNuance = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Synthesize text must not be empty.');
    }

    final ssmlBatch = SsmlParser.buildSsmlBatch(
      text: trimmed,
      voice: voice,
      speed: speed,
      basePitchHz: basePitchHz,
      enableNuance: enableNuance,
    );

    final combinedAudio = BytesBuilder(copy: false);
    for (final ssml in ssmlBatch) {
      final chunkBytes = await _synthesizeWithRetry(ssml);
      combinedAudio.add(chunkBytes);
    }
    return combinedAudio.takeBytes();
  }

  Future<Uint8List> _synthesizeWithRetry(String ssml) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _synthesizeOnce(ssml);
      } catch (e) {
        lastError = e;
        final is403 = e is WebSocketException && e.message.contains('403');
        if (is403) {
          await _tryAdjustClockSkew();
        }
        if (attempt < maxRetries - 1) {
          final delayMs = 400 * pow(2, attempt).toInt();
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    throw EdgeTtsException(
      'Edge TTS 합성에 실패했습니다 ($maxRetries회 재시도 초과): $lastError',
      cause: lastError,
    );
  }

  Future<Uint8List> _synthesizeOnce(String ssml) async {
    final connectionId = _generateHexUuid();
    final secMsGec = EdgeTtsDrm.generateSecMsGecV2();
    final uri = Uri.parse(
      '$_wssBaseUrl?TrustedClientToken=${EdgeTtsDrm.trustedClientToken}'
      '&ConnectionId=$connectionId'
      '&Sec-MS-GEC=$secMsGec'
      '&Sec-MS-GEC-Version=${EdgeTtsDrm.secMsGecVersion}',
    );

    final headers = <String, dynamic>{
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/${EdgeTtsDrm.chromiumMajorVersion}.0.0.0 '
          'Safari/537.36 Edg/${EdgeTtsDrm.chromiumMajorVersion}.0.0.0',
      'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
      'Cookie': 'muid=${EdgeTtsDrm.generateMuid()};',
    };

    // dart:io 기본 HttpClient는 'Dart/x.x' User-Agent를 전송해 403을 유발하므로 비활성화한다.
    final client = HttpClient()
      ..userAgent = null
      ..connectionTimeout = connectTimeout;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
        customClient: client,
      ).timeout(connectTimeout);

      final timestamp = _formatJsUtcDate(DateTime.now().toUtc());
      final configPayload =
          'X-Timestamp:$timestamp\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{'
          '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
          '"outputFormat":"$_outputFormat"}}}}\r\n';
      socket.add(configPayload);

      final requestId = _generateHexUuid();
      final ssmlPayload =
          'X-RequestId:$requestId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${timestamp}Z\r\n'
          'Path:ssml\r\n\r\n'
          '$ssml';
      socket.add(ssmlPayload);

      final audioBuilder = BytesBuilder(copy: false);
      final completer = Completer<Uint8List>();

      late final StreamSubscription<dynamic> subscription;
      subscription = socket
          .timeout(receiveTimeout)
          .listen(
            (dynamic event) {
              if (completer.isCompleted) return;
              if (event is String) {
                final headerEnd = event.indexOf('\r\n\r\n');
                final headerText =
                    headerEnd >= 0 ? event.substring(0, headerEnd) : event;
                final parsedHeaders = _parseHeaders(headerText);
                final path = parsedHeaders['Path'];
                if (path == 'turn.end') {
                  if (audioBuilder.isEmpty) {
                    completer.completeError(
                      const EdgeTtsException('수신된 오디오 데이터가 없습니다.'),
                    );
                  } else {
                    completer.complete(audioBuilder.takeBytes());
                  }
                }
              } else if (event is List<int>) {
                if (event.length < 2) return;
                final headerLength = (event[0] << 8) | event[1];
                final dataStart = 2 + headerLength;
                if (dataStart > event.length) return;

                final headerText = utf8.decode(
                  event.sublist(2, dataStart),
                  allowMalformed: true,
                );
                final parsedHeaders = _parseHeaders(headerText);
                final path = parsedHeaders['Path'];
                final contentType = parsedHeaders['Content-Type'];

                if (path == 'audio' &&
                    contentType == 'audio/mpeg' &&
                    dataStart < event.length) {
                  audioBuilder.add(event.sublist(dataStart));
                }
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!completer.isCompleted) {
                completer.completeError(error, stackTrace);
              }
            },
            onDone: () {
              if (!completer.isCompleted) {
                if (audioBuilder.isNotEmpty) {
                  completer.complete(audioBuilder.takeBytes());
                } else {
                  completer.completeError(
                    const EdgeTtsException('turn.end 이전에 WebSocket 연결이 종료되었습니다.'),
                  );
                }
              }
            },
            cancelOnError: true,
          );

      final result = await completer.future;
      await subscription.cancel();
      return result;
    } finally {
      await socket?.close();
      client.close(force: true);
    }
  }

  Future<void> _tryAdjustClockSkew() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.headUrl(
        Uri.parse('https://speech.platform.bing.com/'),
      );
      final response = await request.close();
      final dateHeader = response.headers.value(HttpHeaders.dateHeader);
      await response.drain<void>();
      if (dateHeader != null) {
        final serverDate = HttpDate.parse(dateHeader);
        EdgeTtsDrm.adjustClockSkewFromDate(serverDate);
      }
    } catch (_) {
      // Clock skew 보정 실패 시 기존 타임스탬프로 재시도
    } finally {
      client.close(force: true);
    }
  }

  Map<String, String> _parseHeaders(String headerText) {
    final headers = <String, String>{};
    for (final line in headerText.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      headers[key] = value;
    }
    return headers;
  }

  String _generateHexUuid() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _formatJsUtcDate(DateTime utc) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final w = weekdays[utc.weekday - 1];
    final m = months[utc.month - 1];
    final d = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '$w $m $d ${utc.year} $hh:$mm:$ss GMT+0000 (Coordinated Universal Time)';
  }
}

class EdgeTtsException implements Exception {
  const EdgeTtsException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'EdgeTtsException: $message';
}
