import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/services/edge_tts_service.dart';

/// 현재 문장 + 다음 3문장(총 4문장 윈도우)만 RAM에 유지하고
/// 재생 완료된 청크는 즉시 폐기하는 무캐시 슬라이딩 버퍼 매니저.
class SlidingBufferManager {
  SlidingBufferManager({
    required this._ttsService,
    this.prefetchWindow = 3,
    this._voice = EdgeTtsService.defaultFemaleVoice,
    this._speed = 1.0,
    this._basePitchHz = 0,
    this._enableNuance = true,
  });

  final EdgeTtsService _ttsService;
  final int prefetchWindow;

  List<String> _sentences = const [];
  String _voice;
  double _speed;
  int _basePitchHz;
  bool _enableNuance;

  /// 세대(generation) 카운터: 에피소드/음성/배속 변경 시 이전 비동기 합성 결과 폐기용
  int _generation = 0;

  final Map<int, Uint8List> _ramBuffer = {};
  final Map<int, Future<Uint8List>> _inFlight = {};

  /// UI 및 진단용 현재 RAM 버퍼에 적재된 문장 인덱스 스냅샷
  final ValueNotifier<Set<int>> bufferedIndicesNotifier = ValueNotifier(
    const <int>{},
  );

  List<String> get sentences => _sentences;
  String get voice => _voice;
  double get speed => _speed;
  int get basePitchHz => _basePitchHz;

  /// 새 에피소드 문장 목록을 적재하고 기존 RAM 버퍼를 전부 비운다.
  /// 선행 합성된 문장 바이트 맵(`preSynthesized`)이 있으면 즉시 RAM 버퍼에 시드한다.
  void loadSentences(
    List<String> sentences, {
    Map<int, Uint8List>? preSynthesized,
  }) {
    _generation++;
    _sentences = List<String>.unmodifiable(sentences);
    _ramBuffer.clear();
    _inFlight.clear();
    if (preSynthesized != null) {
      for (final entry in preSynthesized.entries) {
        if (entry.key >= 0 &&
            entry.key < _sentences.length &&
            entry.value.isNotEmpty) {
          _ramBuffer[entry.key] = entry.value;
        }
      }
    }
    _publishBufferedIndices();
  }

  /// 음성, 배속, 기본 피치, 뉘앙스 설정을 갱신하고 기존 선행 버퍼를 무효화한다.
  void updateVoiceSettings({
    String? voice,
    double? speed,
    int? basePitchHz,
    bool? enableNuance,
  }) {
    final nextVoice = voice ?? _voice;
    final nextSpeed = (speed ?? _speed).clamp(0.8, 2.0);
    final nextPitch = (basePitchHz ?? _basePitchHz).clamp(-6, 6);
    final nextNuance = enableNuance ?? _enableNuance;

    if (nextVoice == _voice &&
        nextSpeed == _speed &&
        nextPitch == _basePitchHz &&
        nextNuance == _enableNuance) {
      return;
    }

    _voice = nextVoice;
    _speed = nextSpeed;
    _basePitchHz = nextPitch;
    _enableNuance = nextNuance;
    clearBuffer();
  }

  /// 현재 인덱스 이전의 재생 완료된 문장 오디오를 즉시 RAM에서 폐기한다.
  void evictBefore(int currentIndex) {
    final keysToRemove = _ramBuffer.keys
        .where((index) => index < currentIndex)
        .toList(growable: false);
    if (keysToRemove.isEmpty) return;

    for (final key in keysToRemove) {
      _ramBuffer.remove(key);
    }
    _publishBufferedIndices();
  }

  /// 특정 문장의 오디오를 가져오고, 다음 `prefetchWindow`(3) 문장을 백그라운드로 선행 합성한다.
  Future<Uint8List> getAudioForSentence(int index) async {
    if (index < 0 || index >= _sentences.length) {
      throw RangeError.index(index, _sentences, 'index');
    }

    evictBefore(index);
    final bytes = await _fetchOrGet(index);
    schedulePrefetch(index);
    return bytes;
  }

  /// 현재 문장 이후 최대 `prefetchWindow`개 문장을 백그라운드에서 미리 RAM에 올린다.
  void schedulePrefetch(int currentIndex) {
    if (_sentences.isEmpty) return;
    final maxIndex = (currentIndex + prefetchWindow).clamp(
      0,
      _sentences.length - 1,
    );

    for (var i = currentIndex + 1; i <= maxIndex; i++) {
      if (_ramBuffer.containsKey(i) || _inFlight.containsKey(i)) {
        continue;
      }
      unawaited(
        _fetchOrGet(i).catchError((Object _) => Uint8List(0)),
      );
    }
  }

  Future<Uint8List> _fetchOrGet(int index) {
    final cached = _ramBuffer[index];
    if (cached != null) {
      return Future<Uint8List>.value(cached);
    }

    final existingFuture = _inFlight[index];
    if (existingFuture != null) {
      return existingFuture;
    }

    final captureGeneration = _generation;
    final sentence = _sentences[index];

    final future = _ttsService
        .synthesizeSentence(
          text: sentence,
          voice: _voice,
          speed: _speed,
          basePitchHz: _basePitchHz,
          enableNuance: _enableNuance,
        )
        .then((bytes) {
          _inFlight.remove(index);
          if (captureGeneration == _generation && bytes.isNotEmpty) {
            _ramBuffer[index] = bytes;
            _publishBufferedIndices();
          }
          return bytes;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _inFlight.remove(index);
          throw error;
        });

    _inFlight[index] = future;
    return future;
  }

  void clearBuffer() {
    _generation++;
    _ramBuffer.clear();
    _inFlight.clear();
    _publishBufferedIndices();
  }

  void _publishBufferedIndices() {
    bufferedIndicesNotifier.value = Set<int>.unmodifiable(_ramBuffer.keys);
  }

  void dispose() {
    clearBuffer();
    bufferedIndicesNotifier.dispose();
  }
}
