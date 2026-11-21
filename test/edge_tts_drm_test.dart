import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:n_ap/audio/memory_audio_source.dart';
import 'package:n_ap/audio/sliding_buffer_manager.dart';
import 'package:n_ap/data/services/edge_tts_drm.dart';
import 'package:n_ap/data/services/edge_tts_service.dart';

class _FakeEdgeTtsService extends EdgeTtsService {
  final List<String> requestedTexts = [];

  @override
  Future<Uint8List> synthesizeSentence({
    required String text,
    String voice = EdgeTtsService.defaultMaleVoice,
    double speed = 1.0,
    int basePitchHz = 0,
    bool enableNuance = true,
  }) async {
    requestedTexts.add('$voice|$speed|$basePitchHz|$enableNuance|$text');
    return Uint8List.fromList(text.codeUnits);
  }
}

void main() {
  group('EdgeTtsDrm', () {
    test('generates valid v2 Sec-MS-GEC format (<16 hex>-<64 hex>)', () {
      final token = EdgeTtsDrm.generateSecMsGecV2(
        unixTimestamp: 1763740800.0,
      );
      expect(
        RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$').hasMatch(token),
        isTrue,
        reason: 'Unexpected Sec-MS-GEC format: $token',
      );

      // 동일 5분 윈도우 내 타임스탬프는 같은 토큰을 생성해야 함
      final sameWindowToken = EdgeTtsDrm.generateSecMsGecV2(
        unixTimestamp: 1763740900.0,
      );
      expect(sameWindowToken, equals(token));
    });
  });

  group('MemoryAudioSource', () {
    test('serves range requests from RAM and releases bytes cleanly', () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final source = MemoryAudioSource(bytes);

      final response = await source.request(1, 4);
      expect(response.sourceLength, 5);
      expect(response.contentLength, 3);
      expect(response.offset, 1);
      expect(response.contentType, 'audio/mpeg');
      final collected = await response.stream.expand((e) => e).toList();
      expect(collected, [20, 30, 40]);

      source.release();
      expect(source.byteLength, 0);
      expect(() => source.request(), throwsStateError);
    });
  });

  group('SlidingBufferManager', () {
    test('keeps current + next 3 sentences in RAM and evicts past sentences', () async {
      final fakeTts = _FakeEdgeTtsService();
      final manager = SlidingBufferManager(
        ttsService: fakeTts,
        prefetchWindow: 3,
      );
      manager.loadSentences(['s0', 's1', 's2', 's3', 's4', 's5']);

      await manager.getAudioForSentence(0);
      await Future<void>.delayed(Duration.zero);
      expect(manager.bufferedIndicesNotifier.value, {0, 1, 2, 3});

      await manager.getAudioForSentence(2);
      await Future<void>.delayed(Duration.zero);
      expect(manager.bufferedIndicesNotifier.value, {2, 3, 4, 5});
    });

    test('invalidates buffer when voice or speed changes', () async {
      final fakeTts = _FakeEdgeTtsService();
      final manager = SlidingBufferManager(ttsService: fakeTts);
      manager.loadSentences(['s0', 's1']);

      await manager.getAudioForSentence(0);
      await Future<void>.delayed(Duration.zero);
      expect(manager.bufferedIndicesNotifier.value, {0, 1});

      manager.updateVoiceSettings(
        voice: EdgeTtsService.defaultFemaleVoice,
        speed: 1.3,
      );
      expect(manager.bufferedIndicesNotifier.value, isEmpty);
    });
  });
}
