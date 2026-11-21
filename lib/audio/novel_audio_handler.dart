import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/services/edge_tts_service.dart';
import 'memory_audio_source.dart';
import 'sliding_buffer_manager.dart';

/// 오디오 포커스를 절대 요청하거나 양보하지 않고(`just_audio` + `audio_service`),
/// 잠금화면/백그라운드에서도 Edge Neural TTS 문장 스트리밍을 유지하는 오디오 핸들러.
class NovelAudioHandler extends BaseAudioHandler {
  NovelAudioHandler({
    EdgeTtsService? ttsService,
    SlidingBufferManager? bufferManager,
  }) : _ttsService = ttsService ?? EdgeTtsService() {
    _bufferManager =
        bufferManager ?? SlidingBufferManager(ttsService: _ttsService);

    // GEMINI.md 2.1: 타 앱(유튜브, 게임, 인터넷 방송 등) 소리와 동시 재생을 위해
    // audio_session 활성화, 인터럽션 중단, Android AudioAttributes 적용을 모두 비활성화한다.
    _player = AudioPlayer(
      handleInterruptions: false,
      androidApplyAudioAttributes: false,
      handleAudioSessionActivation: false,
    );

    _playerStateSubscription = _player.playerStateStream.listen(
      _onPlayerStateChanged,
    );
    _broadcastState(playing: false, processingState: AudioProcessingState.idle);
  }

  static const String customActionBookmark = 'bookmark';

  final EdgeTtsService _ttsService;
  late final SlidingBufferManager _bufferManager;
  late final AudioPlayer _player;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  MemoryAudioSource? _activeSource;

  final ValueNotifier<int> currentIndexNotifier = ValueNotifier(0);
  final ValueNotifier<List<String>> sentencesNotifier = ValueNotifier(
    const <String>[],
  );
  final ValueNotifier<String> episodeTitleNotifier = ValueNotifier('미선택');
  final ValueNotifier<String> novelTitleNotifier = ValueNotifier('N_ap');
  final ValueNotifier<String> voiceNotifier = ValueNotifier(
    EdgeTtsService.defaultFemaleVoice,
  );
  final ValueNotifier<double> speedNotifier = ValueNotifier(1.0);
  final ValueNotifier<int> pitchNotifier = ValueNotifier(0);
  final ValueNotifier<bool> nuanceEnabledNotifier = ValueNotifier(true);
  final ValueNotifier<String?> previewingVoiceIdNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingSentenceNotifier = ValueNotifier(false);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  AudioPlayer? _previewPlayer;

  final StreamController<void> _episodeCompletedController =
      StreamController<void>.broadcast();
  final StreamController<BookmarkTriggerEvent> _bookmarkController =
      StreamController<BookmarkTriggerEvent>.broadcast();

  Stream<void> get onEpisodeCompleted => _episodeCompletedController.stream;
  Stream<BookmarkTriggerEvent> get onBookmarkTriggered =>
      _bookmarkController.stream;
  ValueNotifier<Set<int>> get bufferedIndicesNotifier =>
      _bufferManager.bufferedIndicesNotifier;
  EdgeTtsService get ttsService => _ttsService;

  bool _isTransitioning = false;
  int _playRequestToken = 0;

  /// 에피소드 문장 목록을 로드한다. `autoPlay`가 true면 `startIndex`부터 즉시 재생한다.
  Future<void> loadEpisode({
    required String novelTitle,
    required String episodeTitle,
    required List<String> sentences,
    int startIndex = 0,
    bool autoPlay = false,
    Map<int, Uint8List>? preSynthesized,
  }) async {
    _playRequestToken++;
    await _player.stop();
    _releaseActiveSource();

    novelTitleNotifier.value = novelTitle;
    episodeTitleNotifier.value = episodeTitle;
    sentencesNotifier.value = List<String>.unmodifiable(sentences);
    _bufferManager.loadSentences(sentences, preSynthesized: preSynthesized);
    errorMessageNotifier.value = null;

    if (sentences.isEmpty) {
      currentIndexNotifier.value = 0;
      isPlayingNotifier.value = false;
      _broadcastState(
        playing: false,
        processingState: AudioProcessingState.idle,
      );
      return;
    }

    final safeIndex = startIndex.clamp(0, sentences.length - 1);
    currentIndexNotifier.value = safeIndex;
    _updateMediaItem(safeIndex);

    if (autoPlay) {
      await _playSentenceAt(safeIndex);
    } else {
      _bufferManager.schedulePrefetch(safeIndex - 1);
      isPlayingNotifier.value = false;
      _broadcastState(
        playing: false,
        processingState: AudioProcessingState.ready,
      );
    }
  }

  /// 다음 화 제목 안내 등 1회성 RAM 오디오 바이트를 재생하고 완료될 때까지 대기한다.
  Future<void> playAnnouncementBytes(
    Uint8List audioBytes, {
    required String title,
  }) async {
    final token = ++_playRequestToken;
    _isTransitioning = true;
    isLoadingSentenceNotifier.value = true;
    isPlayingNotifier.value = true;

    mediaItem.add(
      MediaItem(
        id: 'announcement_${DateTime.now().millisecondsSinceEpoch}',
        album: novelTitleNotifier.value,
        title: title,
        artist: '다음 화 자동 전환 안내',
      ),
    );
    _broadcastState(
      playing: true,
      processingState: AudioProcessingState.ready,
    );

    try {
      _releaseActiveSource();
      final source = MemoryAudioSource(audioBytes, tag: 'announcement');
      _activeSource = source;
      await _player.setAudioSource(source, preload: true);
      if (token != _playRequestToken) return;

      isLoadingSentenceNotifier.value = false;
      final completedFuture = _player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
      unawaited(_player.play());
      await completedFuture;
    } finally {
      _releaseActiveSource();
      if (token == _playRequestToken) {
        _isTransitioning = false;
      }
    }
  }

  Future<void> _playSentenceAt(int index) async {
    final sentences = sentencesNotifier.value;
    if (index < 0 || index >= sentences.length) {
      return;
    }

    final token = ++_playRequestToken;
    _isTransitioning = true;
    currentIndexNotifier.value = index;
    errorMessageNotifier.value = null;
    isLoadingSentenceNotifier.value = true;
    _updateMediaItem(index);
    _broadcastState(
      playing: true,
      processingState: AudioProcessingState.buffering,
    );

    try {
      final audioBytes = await _bufferManager.getAudioForSentence(index);
      if (token != _playRequestToken) return;

      _releaseActiveSource();
      final source = MemoryAudioSource(audioBytes, tag: 'sentence_$index');
      _activeSource = source;

      await _player.setAudioSource(source, preload: true);
      if (token != _playRequestToken) return;

      isLoadingSentenceNotifier.value = false;
      isPlayingNotifier.value = true;
      _broadcastState(
        playing: true,
        processingState: AudioProcessingState.ready,
      );
      unawaited(_player.play());
    } catch (e) {
      if (token != _playRequestToken) return;
      isLoadingSentenceNotifier.value = false;
      isPlayingNotifier.value = false;
      errorMessageNotifier.value = e.toString();
      _broadcastState(
        playing: false,
        processingState: AudioProcessingState.error,
      );
    } finally {
      if (token == _playRequestToken) {
        _isTransitioning = false;
      }
    }
  }

  void _onPlayerStateChanged(PlayerState state) {
    if (_isTransitioning) return;

    if (state.processingState == ProcessingState.completed) {
      unawaited(_handleSentenceCompleted());
    }
  }

  Future<void> _handleSentenceCompleted() async {
    final sentences = sentencesNotifier.value;
    if (sentences.isEmpty) return;

    final nextIndex = currentIndexNotifier.value + 1;
    // 방금 완료된 문장 오디오는 RAM에서 즉시 해제
    _releaseActiveSource();
    _bufferManager.evictBefore(nextIndex);

    if (nextIndex < sentences.length) {
      await _playSentenceAt(nextIndex);
    } else {
      isPlayingNotifier.value = false;
      _broadcastState(
        playing: false,
        processingState: AudioProcessingState.completed,
      );
      _episodeCompletedController.add(null);
    }
  }

  @override
  Future<void> play() async {
    final sentences = sentencesNotifier.value;
    if (sentences.isEmpty) return;

    if (_activeSource != null &&
        _player.processingState == ProcessingState.ready) {
      isPlayingNotifier.value = true;
      _broadcastState(
        playing: true,
        processingState: AudioProcessingState.ready,
      );
      unawaited(_player.play());
    } else {
      await _playSentenceAt(currentIndexNotifier.value);
    }
  }

  @override
  Future<void> pause() async {
    _playRequestToken++;
    isLoadingSentenceNotifier.value = false;
    isPlayingNotifier.value = false;
    await _player.pause();
    _broadcastState(
      playing: false,
      processingState: AudioProcessingState.ready,
    );
  }

  @override
  Future<void> stop() async {
    _playRequestToken++;
    isLoadingSentenceNotifier.value = false;
    isPlayingNotifier.value = false;
    await _player.stop();
    _releaseActiveSource();
    _bufferManager.clearBuffer();
    _broadcastState(
      playing: false,
      processingState: AudioProcessingState.idle,
    );
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final sentences = sentencesNotifier.value;
    if (sentences.isEmpty) return;
    final nextIndex = currentIndexNotifier.value + 1;
    if (nextIndex >= sentences.length) return;
    await _playSentenceAt(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    final sentences = sentencesNotifier.value;
    if (sentences.isEmpty) return;
    final prevIndex = (currentIndexNotifier.value - 1).clamp(
      0,
      sentences.length - 1,
    );
    await _playSentenceAt(prevIndex);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final sentences = sentencesNotifier.value;
    if (index < 0 || index >= sentences.length) return;
    await _playSentenceAt(index);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == customActionBookmark) {
      triggerBookmark();
      return true;
    }
    return super.customAction(name, extras);
  }

  /// 현재 재생 중인 문장에 대해 퇴고 북마크 이벤트를 발생시킨다.
  void triggerBookmark() {
    final sentences = sentencesNotifier.value;
    final index = currentIndexNotifier.value;
    if (sentences.isEmpty || index < 0 || index >= sentences.length) return;

    _bookmarkController.add(
      BookmarkTriggerEvent(
        timestamp: DateTime.now(),
        episodeTitle: episodeTitleNotifier.value,
        sentenceIndex: index,
        sentenceText: sentences[index],
      ),
    );
  }

  /// 음성을 변경한다. 재생 중이었다면 현재 문장부터 새 음성으로 즉시 이어서 재생한다.
  Future<void> setVoice(String voiceId) async {
    if (voiceNotifier.value == voiceId) return;
    final wasPlaying = isPlayingNotifier.value || isLoadingSentenceNotifier.value;
    voiceNotifier.value = voiceId;
    _bufferManager.updateVoiceSettings(voice: voiceId);
    _releaseActiveSource();

    if (wasPlaying && sentencesNotifier.value.isNotEmpty) {
      await _playSentenceAt(currentIndexNotifier.value);
    } else if (sentencesNotifier.value.isNotEmpty) {
      _bufferManager.schedulePrefetch(currentIndexNotifier.value - 1);
    }
  }

  /// 배속(`0.8x` ~ `2.0x`)을 변경한다. 재생 중이었다면 현재 문장부터 새 배속으로 이어서 재생한다.
  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = double.parse(speed.clamp(0.8, 2.0).toStringAsFixed(2));
    if (speedNotifier.value == clamped) return;
    final wasPlaying = isPlayingNotifier.value || isLoadingSentenceNotifier.value;
    speedNotifier.value = clamped;
    _bufferManager.updateVoiceSettings(speed: clamped);
    _releaseActiveSource();

    if (wasPlaying && sentencesNotifier.value.isNotEmpty) {
      await _playSentenceAt(currentIndexNotifier.value);
    } else if (sentencesNotifier.value.isNotEmpty) {
      _bufferManager.schedulePrefetch(currentIndexNotifier.value - 1);
    }
  }

  /// 기본 피치(`-6Hz` ~ `+6Hz`)를 변경한다.
  Future<void> setBasePitch(int pitchHz) async {
    final clamped = pitchHz.clamp(-6, 6);
    if (pitchNotifier.value == clamped) return;
    final wasPlaying = isPlayingNotifier.value || isLoadingSentenceNotifier.value;
    pitchNotifier.value = clamped;
    _bufferManager.updateVoiceSettings(basePitchHz: clamped);
    _releaseActiveSource();

    if (wasPlaying && sentencesNotifier.value.isNotEmpty) {
      await _playSentenceAt(currentIndexNotifier.value);
    } else if (sentencesNotifier.value.isNotEmpty) {
      _bufferManager.schedulePrefetch(currentIndexNotifier.value - 1);
    }
  }

  /// 대사/독백 SSML 뉘앙스 적용 여부를 변경한다.
  Future<void> setNuanceEnabled(bool enabled) async {
    if (nuanceEnabledNotifier.value == enabled) return;
    final wasPlaying = isPlayingNotifier.value || isLoadingSentenceNotifier.value;
    nuanceEnabledNotifier.value = enabled;
    _bufferManager.updateVoiceSettings(enableNuance: enabled);
    _releaseActiveSource();

    if (wasPlaying && sentencesNotifier.value.isNotEmpty) {
      await _playSentenceAt(currentIndexNotifier.value);
    } else if (sentencesNotifier.value.isNotEmpty) {
      _bufferManager.schedulePrefetch(currentIndexNotifier.value - 1);
    }
  }

  /// 지정된 음성으로 짧은 한국어 샘플 문장을 RAM에서 즉시 미리듣기 재생한다.
  Future<void> previewVoice(String voiceId) async {
    await stopVoicePreview();
    previewingVoiceIdNotifier.value = voiceId;
    final previewPlayer = AudioPlayer(
      handleInterruptions: false,
      androidApplyAudioAttributes: false,
      handleAudioSessionActivation: false,
    );
    _previewPlayer = previewPlayer;
    MemoryAudioSource? previewSource;

    try {
      final bytes = await _ttsService.synthesizeSentence(
        text: '새벽 비가 창문을 두드렸다. 이 목소리로 원고를 읽어드릴까요?',
        voice: voiceId,
        speed: speedNotifier.value,
        basePitchHz: pitchNotifier.value,
        enableNuance: nuanceEnabledNotifier.value,
      );
      if (_previewPlayer != previewPlayer) return;

      previewSource = MemoryAudioSource(bytes, tag: 'preview_$voiceId');
      await previewPlayer.setAudioSource(previewSource, preload: true);
      if (_previewPlayer != previewPlayer) return;

      final done = previewPlayer.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
      unawaited(previewPlayer.play());
      await done;
    } finally {
      previewSource?.release();
      if (_previewPlayer == previewPlayer) {
        _previewPlayer = null;
        previewingVoiceIdNotifier.value = null;
      }
      await previewPlayer.dispose();
    }
  }

  Future<void> stopVoicePreview() async {
    final existing = _previewPlayer;
    _previewPlayer = null;
    previewingVoiceIdNotifier.value = null;
    if (existing != null) {
      await existing.stop();
      await existing.dispose();
    }
  }

  void _updateMediaItem(int index) {
    final sentences = sentencesNotifier.value;
    final sentencePreview =
        (index >= 0 && index < sentences.length) ? sentences[index] : '';

    mediaItem.add(
      MediaItem(
        id: '${episodeTitleNotifier.value}_$index',
        album: novelTitleNotifier.value,
        title: episodeTitleNotifier.value,
        artist: '${index + 1}/${sentences.length} · $sentencePreview',
      ),
    );
  }

  void _broadcastState({
    required bool playing,
    required AudioProcessingState processingState,
  }) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          const MediaControl(
            androidIcon: 'drawable/ic_bookmark_action',
            label: '퇴고 북마크',
            action: MediaAction.custom,
            customAction: CustomMediaAction(name: customActionBookmark),
          ),
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        speed: speedNotifier.value,
        queueIndex: currentIndexNotifier.value,
      ),
    );
  }

  void _releaseActiveSource() {
    _activeSource?.release();
    _activeSource = null;
  }

  Future<void> disposeHandler() async {
    _playRequestToken++;
    await stopVoicePreview();
    await _playerStateSubscription?.cancel();
    await _player.dispose();
    _releaseActiveSource();
    _bufferManager.dispose();
    await _episodeCompletedController.close();
    await _bookmarkController.close();
    currentIndexNotifier.dispose();
    sentencesNotifier.dispose();
    episodeTitleNotifier.dispose();
    novelTitleNotifier.dispose();
    voiceNotifier.dispose();
    speedNotifier.dispose();
    pitchNotifier.dispose();
    nuanceEnabledNotifier.dispose();
    previewingVoiceIdNotifier.dispose();
    isLoadingSentenceNotifier.dispose();
    errorMessageNotifier.dispose();
    isPlayingNotifier.dispose();
  }
}

/// 잠금화면 또는 UI에서 발생한 퇴고 북마크 트리거 이벤트.
class BookmarkTriggerEvent {
  const BookmarkTriggerEvent({
    required this.timestamp,
    required this.episodeTitle,
    required this.sentenceIndex,
    required this.sentenceText,
  });

  final DateTime timestamp;
  final String episodeTitle;
  final int sentenceIndex;
  final String sentenceText;
}
