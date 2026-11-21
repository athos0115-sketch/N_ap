import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/ssml_parser.dart';
import '../data/models/episode_item.dart';
import '../data/models/novel_folder.dart';
import '../data/models/revision_bookmark.dart';
import '../data/services/drive_service.dart';
import '../data/services/storage_service.dart';
import 'novel_audio_handler.dart';

/// 취침 타이머 모드.
enum SleepTimerMode { off, minutes15, minutes30, minutes60, endOfEpisode }

/// 비침습적 토스트/스낵바 알림 모델.
class UiNotice {
  const UiNotice(this.message, {this.isError = false});

  final String message;
  final bool isError;
}

class _PrefetchedNextEpisode {
  const _PrefetchedNextEpisode({
    required this.episode,
    required this.sentences,
    required this.preSynthesized,
    this.announcementBytes,
  });

  final EpisodeItem episode;
  final List<String> sentences;
  final Map<int, Uint8List> preSynthesized;
  final Uint8List? announcementBytes;
}

/// Google Drive 폴더/회차 관리, 진도 저장, 다음 화 2초 대기 자동 전환,
/// 및 퇴고 북마크 동기화를 총괄하는 컨트롤러.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.audioHandler,
    required this.driveService,
    required this.storageService,
  });

  final NovelAudioHandler audioHandler;
  final DriveService driveService;
  final StorageService storageService;

  final StreamController<UiNotice> _noticeController =
      StreamController<UiNotice>.broadcast();
  Stream<UiNotice> get notices => _noticeController.stream;

  List<NovelFolder> _folders = const [];
  NovelFolder? _activeFolder;
  List<EpisodeItem> _episodes = const [];
  EpisodeItem? _activeEpisode;
  List<RevisionBookmark> _bookmarks = const [];

  bool _isLoadingEpisodes = false;
  bool _isLoadingEpisodeText = false;
  bool _isTransitioningNextEpisode = false;
  String? _statusMessage;

  Future<_PrefetchedNextEpisode?>? _prefetchNextFuture;
  String? _prefetchSourceEpisodeId;
  int _episodeLoadToken = 0;

  StreamSubscription<void>? _completedSub;
  StreamSubscription<BookmarkTriggerEvent>? _bookmarkSub;

  SleepTimerMode _sleepTimerMode = SleepTimerMode.off;
  Timer? _sleepTimer;
  final ValueNotifier<Duration?> sleepRemainingNotifier = ValueNotifier(null);
  final ValueNotifier<int> fontSizeLevelNotifier = ValueNotifier(1);

  List<NovelFolder> get folders => _folders;
  NovelFolder? get activeFolder => _activeFolder;
  List<EpisodeItem> get episodes => _episodes;
  EpisodeItem? get activeEpisode => _activeEpisode;
  List<RevisionBookmark> get bookmarks => _bookmarks;
  bool get isLoadingEpisodes => _isLoadingEpisodes;
  bool get isLoadingEpisodeText => _isLoadingEpisodeText;
  bool get isTransitioningNextEpisode => _isTransitioningNextEpisode;
  String? get statusMessage => _statusMessage;
  SleepTimerMode get sleepTimerMode => _sleepTimerMode;

  Future<void> initialize() async {
    _folders = storageService.loadFolders();
    _bookmarks = storageService.loadBookmarks();
    fontSizeLevelNotifier.value = storageService.loadFontSizeLevel();

    final savedVoice = storageService.loadVoice();
    final savedSpeed = storageService.loadSpeed();
    final savedPitch = storageService.loadPitchHz();
    final savedNuance = storageService.loadNuanceEnabled();
    await audioHandler.setVoice(savedVoice);
    await audioHandler.setPlaybackSpeed(savedSpeed);
    await audioHandler.setBasePitch(savedPitch);
    await audioHandler.setNuanceEnabled(savedNuance);

    audioHandler.currentIndexNotifier.addListener(_onSentenceIndexChanged);
    _completedSub = audioHandler.onEpisodeCompleted.listen((_) {
      unawaited(_handleEpisodeCompleted());
    });
    _bookmarkSub = audioHandler.onBookmarkTriggered.listen((event) {
      unawaited(_recordBookmarkFromEvent(event));
    });

    await driveService.initialize(
      serverClientId: storageService.loadServerClientId(),
    );

    final lastFolderId = storageService.loadLastFolderId();
    if (lastFolderId != null) {
      final found = _folders.where((f) => f.id == lastFolderId).firstOrNull;
      if (found != null) {
        _activeFolder = found;
      }
    }
    notifyListeners();
  }

  // --- Google Drive 인증 및 설정 ---

  Future<void> updateServerClientId(String? clientId) async {
    await storageService.saveServerClientId(clientId);
    await driveService.initialize(serverClientId: clientId);
    _emitNotice('Google OAuth Client ID 설정을 저장했습니다.');
    notifyListeners();
  }

  Future<bool> signInGoogle() async {
    try {
      await driveService.signInAndAuthorize();
      _emitNotice('Google Drive 계정에 연결되었습니다.');
      if (_activeFolder != null && _episodes.isEmpty) {
        await openFolder(_activeFolder!, autoLoadLastEpisode: false);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _emitNotice('Google 로그인 실패: $e', isError: true);
      return false;
    }
  }

  Future<void> signOutGoogle() async {
    await driveService.signOut();
    _emitNotice('Google 계정 연결을 해제했습니다.');
    notifyListeners();
  }

  // --- 폴더 등록 및 탐색 ---

  Future<void> registerFolder(NovelFolder folder) async {
    final existingIdx = _folders.indexWhere((f) => f.id == folder.id);
    if (existingIdx >= 0) {
      _emitNotice('"${folder.name}" 폴더는 이미 등록되어 있습니다.');
      return;
    }
    _folders = [..._folders, folder];
    await storageService.saveFolders(_folders);
    _emitNotice('"${folder.name}" 폴더를 등록했습니다.');
    notifyListeners();
  }

  Future<void> registerFolderByInput(String idOrUrl) async {
    try {
      final folder = await driveService.resolveFolder(idOrUrl);
      await registerFolder(folder);
    } catch (e) {
      _emitNotice(e.toString(), isError: true);
    }
  }

  Future<void> removeFolder(String folderId) async {
    _folders = _folders.where((f) => f.id != folderId).toList(growable: false);
    await storageService.saveFolders(_folders);
    if (_activeFolder?.id == folderId) {
      _activeFolder = null;
      _episodes = const [];
      _activeEpisode = null;
      await storageService.saveLastFolderId(null);
    }
    notifyListeners();
  }

  Future<void> openFolder(
    NovelFolder folder, {
    bool autoLoadLastEpisode = true,
  }) async {
    _activeFolder = folder;
    await storageService.saveLastFolderId(folder.id);
    _isLoadingEpisodes = true;
    _statusMessage = '원고 목록을 불러오는 중...';
    notifyListeners();

    try {
      final list = await driveService.listEpisodesInFolder(folder.id);
      _episodes = list;
      _isLoadingEpisodes = false;
      _statusMessage = null;
      notifyListeners();

      if (autoLoadLastEpisode && list.isNotEmpty) {
        EpisodeItem target = list.first;
        var resumeSentence = 0;
        if (folder.lastFileId != null) {
          final matched = list
              .where((e) => e.id == folder.lastFileId)
              .firstOrNull;
          if (matched != null) {
            target = matched;
            resumeSentence = folder.lastSentenceIndex;
          }
        }
        await loadEpisodeItem(
          target,
          startIndex: resumeSentence,
          autoPlay: false,
        );
      }
    } catch (e) {
      _isLoadingEpisodes = false;
      _statusMessage = null;
      _emitNotice(e.toString(), isError: true);
      notifyListeners();
    }
  }

  Future<void> refreshActiveFolder() async {
    final folder = _activeFolder;
    if (folder == null) return;
    await openFolder(folder, autoLoadLastEpisode: false);
  }

  // --- 에피소드 로드 및 재생 ---

  Future<void> loadEpisodeItem(
    EpisodeItem episode, {
    int startIndex = 0,
    bool autoPlay = true,
    Map<int, Uint8List>? preSynthesized,
    List<String>? preParsedSentences,
  }) async {
    final token = ++_episodeLoadToken;
    _isTransitioningNextEpisode = false;
    _prefetchNextFuture = null;
    _prefetchSourceEpisodeId = null;

    _activeEpisode = episode;
    _isLoadingEpisodeText = true;
    _statusMessage = '${episode.displayTitle} 원고 추출 중...';
    notifyListeners();

    try {
      final sentences =
          preParsedSentences ??
          SsmlParser.splitIntoSentences(
            await driveService.downloadEpisodeText(episode),
          );
      if (token != _episodeLoadToken) return;

      _isLoadingEpisodeText = false;
      _statusMessage = null;
      notifyListeners();

      if (sentences.isEmpty) {
        _emitNotice('${episode.displayTitle}에 읽을 수 있는 문장이 없습니다.', isError: true);
        return;
      }

      final folderName = _activeFolder?.name ?? 'N_ap';
      await audioHandler.loadEpisode(
        novelTitle: folderName,
        episodeTitle: episode.displayTitle,
        sentences: sentences,
        startIndex: startIndex,
        autoPlay: autoPlay,
        preSynthesized: preSynthesized,
      );

      await _persistFolderProgress(episode: episode, sentenceIndex: startIndex);
      if (startIndex >= sentences.length - 1) {
        _triggerPrefetchNextEpisode(episode);
      }
    } catch (e) {
      if (token != _episodeLoadToken) return;
      _isLoadingEpisodeText = false;
      _statusMessage = null;
      _emitNotice('원고 로드 실패: $e', isError: true);
      notifyListeners();
    }
  }

  void _onSentenceIndexChanged() {
    final episode = _activeEpisode;
    final sentences = audioHandler.sentencesNotifier.value;
    final index = audioHandler.currentIndexNotifier.value;
    if (episode == null || sentences.isEmpty) return;

    unawaited(_persistFolderProgress(episode: episode, sentenceIndex: index));

    // GEMINI.md 4.3: 마지막 문장 재생 시 다음 화 텍스트 및 첫 3문장 선행 준비
    if (index >= sentences.length - 1) {
      _triggerPrefetchNextEpisode(episode);
    }
  }

  EpisodeItem? _findNextEpisode(EpisodeItem current) {
    final idx = _episodes.indexWhere((e) => e.id == current.id);
    if (idx < 0 || idx + 1 >= _episodes.length) return null;
    return _episodes[idx + 1];
  }

  void _triggerPrefetchNextEpisode(EpisodeItem currentEpisode) {
    if (_prefetchSourceEpisodeId == currentEpisode.id &&
        _prefetchNextFuture != null) {
      return;
    }
    final nextEp = _findNextEpisode(currentEpisode);
    if (nextEp == null) return;

    _prefetchSourceEpisodeId = currentEpisode.id;
    _prefetchNextFuture = _prefetchEpisodeData(nextEp);
  }

  Future<_PrefetchedNextEpisode?> _prefetchEpisodeData(
    EpisodeItem nextEp,
  ) async {
    try {
      final rawText = await driveService.downloadEpisodeText(nextEp);
      final sentences = SsmlParser.splitIntoSentences(rawText);
      if (sentences.isEmpty) return null;

      final voice = audioHandler.voiceNotifier.value;
      final speed = audioHandler.speedNotifier.value;
      final pitch = audioHandler.pitchNotifier.value;
      final nuance = audioHandler.nuanceEnabledNotifier.value;
      final tts = audioHandler.ttsService;

      // 안내 음성 + 다음 화 첫 3문장 병렬 선행 합성
      final announcementFuture = tts
          .synthesizeSentence(
            text: '다음 화, ${nextEp.displayTitle}를 재생합니다.',
            voice: voice,
            speed: speed,
            basePitchHz: pitch,
            enableNuance: false,
          )
          .catchError((Object _) => Uint8List(0));

      final count = sentences.length < 3 ? sentences.length : 3;
      final preMap = <int, Uint8List>{};
      await Future.wait(
        List.generate(count, (i) async {
          try {
            final bytes = await tts.synthesizeSentence(
              text: sentences[i],
              voice: voice,
              speed: speed,
              basePitchHz: pitch,
              enableNuance: nuance,
            );
            if (bytes.isNotEmpty) {
              preMap[i] = bytes;
            }
          } catch (_) {
            // 개별 문장 선행 실패 시 재생 시점에 재시도됨
          }
        }),
      );

      final announcementBytes = await announcementFuture;
      return _PrefetchedNextEpisode(
        episode: nextEp,
        sentences: sentences,
        preSynthesized: preMap,
        announcementBytes: announcementBytes.isEmpty ? null : announcementBytes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleEpisodeCompleted() async {
    if (_sleepTimerMode == SleepTimerMode.endOfEpisode) {
      setSleepTimer(SleepTimerMode.off);
      await audioHandler.pause();
      _emitNotice('현재 화가 끝나 취침 타이머로 재생을 멈췄습니다');
      return;
    }

    final current = _activeEpisode;
    if (current == null) return;

    final nextEp = _findNextEpisode(current);
    if (nextEp == null) {
      _emitNotice('폴더 내 마지막 화까지 재생을 완료했습니다.');
      return;
    }

    final token = _episodeLoadToken;
    _isTransitioningNextEpisode = true;
    _statusMessage = '2초 후 다음 화(${nextEp.displayTitle})로 전환합니다...';
    notifyListeners();

    final prefetchedFuture =
        _prefetchNextFuture ?? _prefetchEpisodeData(nextEp);

    // GEMINI.md 4.3: 2초 일시정지 후 다음 화 제목 안내 및 자동 연속 재생
    await Future<void>.delayed(const Duration(seconds: 2));
    if (token != _episodeLoadToken) return;

    try {
      final prefetched = await prefetchedFuture;
      if (token != _episodeLoadToken) return;

      Uint8List? announcementBytes = prefetched?.announcementBytes;
      announcementBytes ??= await audioHandler.ttsService
          .synthesizeSentence(
            text: '다음 화, ${nextEp.displayTitle}를 재생합니다.',
            voice: audioHandler.voiceNotifier.value,
            speed: audioHandler.speedNotifier.value,
          )
          .catchError((Object _) => Uint8List(0));

      if (token != _episodeLoadToken) return;

      if (announcementBytes.isNotEmpty) {
        await audioHandler.playAnnouncementBytes(
          announcementBytes,
          title: nextEp.displayTitle,
        );
      }
      if (token != _episodeLoadToken) return;

      await loadEpisodeItem(
        nextEp,
        startIndex: 0,
        autoPlay: true,
        preSynthesized: prefetched?.preSynthesized,
        preParsedSentences: prefetched?.sentences,
      );
    } catch (e) {
      if (token != _episodeLoadToken) return;
      _isTransitioningNextEpisode = false;
      _statusMessage = null;
      _emitNotice('다음 화 자동 전환 중 오류: $e', isError: true);
      notifyListeners();
    }
  }

  // --- TTS, 글자 크기 및 취침 타이머 설정 ---

  Future<void> setVoice(String voiceId) async {
    await storageService.saveVoice(voiceId);
    _prefetchNextFuture = null;
    await audioHandler.setVoice(voiceId);
  }

  Future<void> setSpeed(double speed) async {
    await storageService.saveSpeed(speed);
    _prefetchNextFuture = null;
    await audioHandler.setPlaybackSpeed(speed);
  }

  Future<void> setPitch(int pitchHz) async {
    await storageService.savePitchHz(pitchHz);
    _prefetchNextFuture = null;
    await audioHandler.setBasePitch(pitchHz);
  }

  Future<void> setNuanceEnabled(bool enabled) async {
    await storageService.saveNuanceEnabled(enabled);
    _prefetchNextFuture = null;
    await audioHandler.setNuanceEnabled(enabled);
  }

  Future<void> setFontSizeLevel(int level) async {
    final clamped = level.clamp(0, 2);
    fontSizeLevelNotifier.value = clamped;
    await storageService.saveFontSizeLevel(clamped);
  }

  void setSleepTimer(SleepTimerMode mode) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerMode = mode;

    Duration? initialDuration;
    switch (mode) {
      case SleepTimerMode.off:
        sleepRemainingNotifier.value = null;
      case SleepTimerMode.minutes15:
        initialDuration = const Duration(minutes: 15);
      case SleepTimerMode.minutes30:
        initialDuration = const Duration(minutes: 30);
      case SleepTimerMode.minutes60:
        initialDuration = const Duration(minutes: 60);
      case SleepTimerMode.endOfEpisode:
        sleepRemainingNotifier.value = null;
        _emitNotice('취침 타이머: 현재 화 종료 후 자동 정지');
    }

    if (initialDuration != null) {
      var remaining = initialDuration;
      sleepRemainingNotifier.value = remaining;
      _emitNotice('취침 타이머: ${initialDuration.inMinutes}분 후 자동 정지');
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        remaining -= const Duration(seconds: 1);
        if (remaining <= Duration.zero) {
          timer.cancel();
          _sleepTimer = null;
          _sleepTimerMode = SleepTimerMode.off;
          sleepRemainingNotifier.value = null;
          unawaited(audioHandler.pause());
          _emitNotice('취침 타이머가 종료되어 재생을 멈췄습니다');
          notifyListeners();
        } else {
          sleepRemainingNotifier.value = remaining;
        }
      });
    }
    notifyListeners();
  }

  /// 퇴고 북마크 항목의 회차와 문장 위치로 즉시 이동해 재생한다.
  Future<bool> jumpToBookmark(RevisionBookmark bookmark) async {
    final targetFolder = _folders
        .where((f) => f.id == bookmark.folderId)
        .firstOrNull;

    if (targetFolder != null && _activeFolder?.id != targetFolder.id) {
      await openFolder(targetFolder, autoLoadLastEpisode: false);
    }

    if (_activeEpisode?.id == bookmark.episodeId &&
        audioHandler.sentencesNotifier.value.isNotEmpty) {
      final safeIdx = bookmark.sentenceIndex.clamp(
        0,
        audioHandler.sentencesNotifier.value.length - 1,
      );
      await audioHandler.skipToQueueItem(safeIdx);
      return true;
    }

    final matchedEp = _episodes
        .where((e) => e.id == bookmark.episodeId)
        .firstOrNull;
    if (matchedEp == null) {
      _emitNotice('해당 회차를 찾을 수 없습니다. 폴더를 먼저 열어 주세요', isError: true);
      return false;
    }

    await loadEpisodeItem(
      matchedEp,
      startIndex: bookmark.sentenceIndex,
      autoPlay: true,
    );
    return true;
  }

  Future<void> _persistFolderProgress({
    required EpisodeItem episode,
    required int sentenceIndex,
  }) async {
    final folder = _activeFolder;
    if (folder == null) return;

    final updated = folder.copyWith(
      lastFileId: episode.id,
      lastFileName: episode.name,
      lastSentenceIndex: sentenceIndex,
      updatedAtIso: DateTime.now().toIso8601String(),
    );
    _activeFolder = updated;
    _folders = _folders
        .map((f) => f.id == updated.id ? updated : f)
        .toList(growable: false);
    await storageService.saveFolders(_folders);
    notifyListeners();
  }

  // --- 퇴고 북마크 저장 및 Google Drive 메모 동기화 ---

  Future<void> _recordBookmarkFromEvent(BookmarkTriggerEvent event) async {
    unawaited(HapticFeedback.mediumImpact());

    final folderId = _activeFolder?.id ?? 'local';
    final folderName = _activeFolder?.name ?? audioHandler.novelTitleNotifier.value;
    final episodeId = _activeEpisode?.id ?? 'local_episode';

    var bookmark = RevisionBookmark(
      id: '${event.timestamp.microsecondsSinceEpoch}',
      folderId: folderId,
      folderName: folderName,
      episodeId: episodeId,
      episodeTitle: event.episodeTitle,
      sentenceIndex: event.sentenceIndex,
      sentenceText: event.sentenceText,
      timestamp: event.timestamp,
      syncedToDrive: false,
    );

    _bookmarks = [bookmark, ..._bookmarks];
    await storageService.saveBookmarks(_bookmarks);
    notifyListeners();

    if (_activeFolder != null &&
        driveService.isSignedIn &&
        driveService.hasDriveFilePermissionNotifier.value) {
      try {
        await driveService.appendRevisionBookmark(
          folderId: _activeFolder!.id,
          bookmark: bookmark,
        );
        bookmark = bookmark.copyWith(syncedToDrive: true);
        _bookmarks = _bookmarks
            .map((b) => b.id == bookmark.id ? bookmark : b)
            .toList(growable: false);
        await storageService.saveBookmarks(_bookmarks);
        _emitNotice('퇴고 북마크 저장 & N_ap_퇴고메모.md 동기화 완료');
        notifyListeners();
        return;
      } catch (e) {
        _emitNotice('로컬에 저장됨 (Drive 동기화 보류: $e)', isError: true);
        return;
      }
    }

    _emitNotice('퇴고 북마크를 로컬 로그에 저장했습니다 (#${event.sentenceIndex + 1}).');
  }

  Future<void> syncPendingBookmarks() async {
    if (!driveService.isSignedIn) {
      _emitNotice('Google 계정 연결 후 동기화할 수 있습니다.', isError: true);
      return;
    }

    var syncedCount = 0;
    final updated = <RevisionBookmark>[];
    for (final b in _bookmarks) {
      if (b.syncedToDrive || b.folderId == 'local') {
        updated.add(b);
        continue;
      }
      try {
        await driveService.appendRevisionBookmark(
          folderId: b.folderId,
          bookmark: b,
        );
        updated.add(b.copyWith(syncedToDrive: true));
        syncedCount++;
      } catch (e) {
        updated.add(b);
        _emitNotice('북마크 동기화 실패: $e', isError: true);
      }
    }
    _bookmarks = updated;
    await storageService.saveBookmarks(_bookmarks);
    if (syncedCount > 0) {
      _emitNotice('$syncedCount건의 퇴고 북마크를 Drive에 동기화했습니다.');
    } else {
      _emitNotice('동기화할 미전송 북마크가 없습니다.');
    }
    notifyListeners();
  }

  Future<void> deleteBookmark(String id) async {
    _bookmarks = _bookmarks.where((b) => b.id != id).toList(growable: false);
    await storageService.saveBookmarks(_bookmarks);
    notifyListeners();
  }

  void _emitNotice(String message, {bool isError = false}) {
    if (!_noticeController.isClosed) {
      _noticeController.add(UiNotice(message, isError: isError));
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    sleepRemainingNotifier.dispose();
    fontSizeLevelNotifier.dispose();
    audioHandler.currentIndexNotifier.removeListener(_onSentenceIndexChanged);
    unawaited(_completedSub?.cancel());
    unawaited(_bookmarkSub?.cancel());
    unawaited(_noticeController.close());
    super.dispose();
  }
}
