import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../audio/playback_controller.dart';
import '../../core/theme/darkroom_theme.dart';
import '../../data/models/episode_item.dart';
import '../../data/services/edge_tts_service.dart';
import '../widgets/darkroom_components.dart';
import '../widgets/manuscript_viewer.dart';
import '../widgets/speed_selector.dart';
import 'bookmarks_screen.dart';

/// Darkroom Filament v1.1 (Quiet Pro) 적응형 플레이어 화면.
/// - Expanded (`width >= 600dp`): Galaxy Z Fold 펼침 2-Pane 레이아웃
/// - Compact (`width < 600dp`): 커버/단일 화면 원핸드 플레이어
/// - 1px Warm Rim-Light는 상단 상태 필과 활성 문장 카드 2곳에만 절제 적용
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
  });

  final PlaybackController controller;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int _leftPaneTab = 0; // 0: 회차, 1: 퇴고 메모
  bool _isManuscriptTouchLocked = false;
  StreamSubscription<UiNotice>? _noticeSub;

  @override
  void initState() {
    super.initState();
    _noticeSub = widget.controller.notices.listen((notice) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notice.message,
            style: TextStyle(
              color: notice.isError
                  ? DarkroomTheme.statusDangerText
                  : DarkroomTheme.textPrimary,
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_noticeSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: DarkroomTheme.bgCanvas,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 600) {
                  return _buildExpandedSplitLayout();
                }
                return _buildCompactLayout();
              },
            ),
          ),
        );
      },
    );
  }

  /// Expanded / Unfolded Screen (`width >= 600dp`): 2-Pane Darkroom Layout
  Widget _buildExpandedSplitLayout() {
    final controller = widget.controller;
    final folderName = controller.activeFolder?.name ?? '소설 프로젝트';

    return Row(
      children: [
        Container(
          width: 288,
          decoration: const BoxDecoration(
            color: DarkroomTheme.bgSidebar,
            border: Border(
              right: BorderSide(color: DarkroomTheme.borderSpecular),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '폴더 목록',
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: DarkroomTheme.textSecondary,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'N_ap',
                      style: TextStyle(
                        color: DarkroomTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '회차 새로고침',
                      icon: const Icon(
                        Icons.refresh,
                        size: 18,
                        color: DarkroomTheme.textSecondary,
                      ),
                      onPressed: () =>
                          unawaited(controller.refreshActiveFolder()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DarkroomTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DarkroomSegmentedTrack(
                  labels: const ['회차', '퇴고 메모'],
                  selectedIndex: _leftPaneTab,
                  onChanged: (i) => setState(() => _leftPaneTab = i),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _leftPaneTab == 0
                    ? _buildEpisodeList()
                    : InlineBookmarksPane(controller: controller),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Expanded(child: _buildTopStatusPill(isCompact: false)),
                    const SizedBox(width: 10),
                    _buildTouchLockButton(),
                  ],
                ),
              ),
              _buildErrorOrStatusLine(),
              Expanded(child: _buildManuscriptSection()),
              _buildPlaybackDock(isCompact: false),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact / Cover Screen (`width < 600dp`): One-handed Darkroom Player
  Widget _buildCompactLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '폴더 목록',
                icon: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: DarkroomTheme.textSecondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(child: _buildTopStatusPill(isCompact: true)),
              IconButton(
                tooltip: '퇴고 메모',
                icon: const Icon(
                  Icons.bookmarks_outlined,
                  size: 19,
                  color: DarkroomTheme.textSecondary,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BookmarksScreen(
                      controller: widget.controller,
                      openedFromPlayer: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildErrorOrStatusLine(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DarkroomPillButton(
                  height: 34,
                  onPressed: _showEpisodesBottomSheet,
                  child: Text(
                    '회차 목록 (${widget.controller.episodes.length})',
                    style: const TextStyle(
                      color: DarkroomTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildTouchLockButton(),
            ],
          ),
        ),
        Expanded(child: _buildManuscriptSection()),
        _buildPlaybackDock(isCompact: true),
      ],
    );
  }

  Widget _buildTouchLockButton() {
    return DarkroomPillButton(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      active: _isManuscriptTouchLocked,
      tooltip: _isManuscriptTouchLocked ? '터치 잠금 해제' : '원고 창 터치 잠금',
      onPressed: () => setState(
        () => _isManuscriptTouchLocked = !_isManuscriptTouchLocked,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isManuscriptTouchLocked
                ? Icons.lock_outline_rounded
                : Icons.lock_open_rounded,
            size: 14,
            color: _isManuscriptTouchLocked
                ? DarkroomTheme.filamentGold
                : DarkroomTheme.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            _isManuscriptTouchLocked ? '잠금 중' : '터치 잠금',
            style: TextStyle(
              color: _isManuscriptTouchLocked
                  ? DarkroomTheme.filamentGold
                  : DarkroomTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 포컬 요소 #1: 상단 1px Warm Rim-Light 상태 필
  Widget _buildTopStatusPill({required bool isCompact}) {
    final handler = widget.controller.audioHandler;
    final episodeTitle =
        widget.controller.activeEpisode?.displayTitle ??
        handler.episodeTitleNotifier.value;

    return ValueListenableBuilder<List<String>>(
      valueListenable: handler.sentencesNotifier,
      builder: (_, sentences, _) {
        return ValueListenableBuilder<int>(
          valueListenable: handler.currentIndexNotifier,
          builder: (_, index, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: handler.isPlayingNotifier,
              builder: (_, isPlaying, _) {
                return ValueListenableBuilder<Set<int>>(
                  valueListenable: handler.bufferedIndicesNotifier,
                  builder: (_, buffered, _) {
                    return ValueListenableBuilder<Duration?>(
                      valueListenable: widget.controller.sleepRemainingNotifier,
                      builder: (_, sleepRem, _) {
                        final countLabel = sentences.isEmpty
                            ? '0/0'
                            : '${index + 1}/${sentences.length}';
                        final sleepText = _formatSleepChip(sleepRem);

                        return WarmRimSurface(
                          radius: DarkroomTheme.radiusPill,
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 14 : 18,
                            vertical: 9,
                          ),
                          enableWarmRim: true,
                          warmIntensity: isPlaying ? 1.0 : 0.6,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$episodeTitle · $countLabel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: DarkroomTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              if (sleepText != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  sleepText,
                                  style: const TextStyle(
                                    color: DarkroomTheme.filamentOrangeText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              EmberCoreDot(
                                live: isPlaying,
                                useGold: true,
                                size: 7,
                              ),
                              if (!isCompact) ...[
                                const SizedBox(width: 6),
                                Text(
                                  isPlaying
                                      ? 'Live · RAM ${buffered.length}/4'
                                      : 'Standby · RAM ${buffered.length}/4',
                                  style: const TextStyle(
                                    color: DarkroomTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String? _formatSleepChip(Duration? rem) {
    if (widget.controller.sleepTimerMode == SleepTimerMode.endOfEpisode) {
      return '화 종료 정지';
    }
    if (rem == null) return null;
    final mm = rem.inMinutes.toString().padLeft(2, '0');
    final ss = (rem.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _buildErrorOrStatusLine() {
    final handler = widget.controller.audioHandler;

    return ValueListenableBuilder<String?>(
      valueListenable: handler.errorMessageNotifier,
      builder: (_, audioErr, _) {
        final msg = widget.controller.statusMessage ?? audioErr;
        if (msg == null || msg.isEmpty) return const SizedBox.shrink();
        final isError = audioErr != null && widget.controller.statusMessage == null;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isError
                ? DarkroomTheme.filamentRedBg
                : DarkroomTheme.filamentGoldBg,
            borderRadius: BorderRadius.circular(DarkroomTheme.radiusSm),
            border: Border.all(
              color: isError
                  ? DarkroomTheme.filamentRedBorder
                  : DarkroomTheme.filamentGoldBorder,
            ),
          ),
          child: Text(
            msg,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isError
                  ? DarkroomTheme.statusDangerText
                  : DarkroomTheme.filamentGold,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeList() {
    final controller = widget.controller;
    if (controller.isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.episodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '폴더 내 지원 원고(.txt · .md · Google Docs)가 없습니다',
            textAlign: TextAlign.center,
            style: TextStyle(color: DarkroomTheme.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: controller.audioHandler.isPlayingNotifier,
      builder: (_, isPlaying, _) {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: controller.episodes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final ep = controller.episodes[index];
            final isActive = controller.activeEpisode?.id == ep.id;
            return _EpisodeRow(
              episode: ep,
              isActive: isActive,
              isPlaying: isPlaying,
              onTap: () => unawaited(
                controller.loadEpisodeItem(ep, autoPlay: true),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildManuscriptSection() {
    final handler = widget.controller.audioHandler;
    if (widget.controller.isLoadingEpisodeText) {
      return const Center(child: CircularProgressIndicator());
    }

    return ValueListenableBuilder<List<String>>(
      valueListenable: handler.sentencesNotifier,
      builder: (_, sentences, _) {
        return ValueListenableBuilder<int>(
          valueListenable: handler.currentIndexNotifier,
          builder: (_, currentIndex, _) {
            return ValueListenableBuilder<Set<int>>(
              valueListenable: handler.bufferedIndicesNotifier,
              builder: (_, buffered, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: widget.controller.fontSizeLevelNotifier,
                  builder: (_, fontLevel, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: handler.isPlayingNotifier,
                      builder: (_, isPlaying, _) {
                        return ManuscriptViewer(
                          sentences: sentences,
                          currentIndex: currentIndex,
                          bufferedIndices: buffered,
                          fontSizeLevel: fontLevel,
                          isPlaying: isPlaying,
                          touchLocked: _isManuscriptTouchLocked,
                          onTapSentence: (idx) => unawaited(
                            _confirmAndPlayFromSentence(idx, sentences[idx]),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmAndPlayFromSentence(
    int index,
    String sentenceText,
  ) async {
    if (_isManuscriptTouchLocked) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: DarkroomTheme.backdropPalette,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '여기서부터 재생하시겠습니까?',
          style: TextStyle(
            color: DarkroomTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '#${index + 1} · $sentenceText',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DarkroomTheme.textSecondary,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '아니오',
              style: TextStyle(color: DarkroomTheme.textSecondary),
            ),
          ),
          DarkroomPillButton(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            variant: DarkroomButtonVariant.primaryCta,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '예',
              style: TextStyle(
                color: DarkroomTheme.ctaText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.controller.audioHandler.skipToQueueItem(index);
    }
  }

  /// 하단 Darkroom 재생 콘솔: 써멀 진행 바 + 오프화이트 필 CTA + 고스트 보조 필
  Widget _buildPlaybackDock({required bool isCompact}) {
    final handler = widget.controller.audioHandler;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 20,
        10,
        isCompact ? 16 : 20,
        16,
      ),
      decoration: const BoxDecoration(
        color: DarkroomTheme.bgCanvas,
        border: Border(
          top: BorderSide(color: DarkroomTheme.borderSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<List<String>>(
            valueListenable: handler.sentencesNotifier,
            builder: (_, sentences, _) {
              return ValueListenableBuilder<int>(
                valueListenable: handler.currentIndexNotifier,
                builder: (_, index, _) {
                  final progress = sentences.isEmpty
                      ? 0.0
                      : (index + 1) / sentences.length;
                  return ThermalProgressBar(progress: progress);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 42,
                child: DarkroomPillButton(
                  height: 42,
                  padding: EdgeInsets.zero,
                  tooltip: '이전 문장',
                  onPressed: () => unawaited(handler.skipToPrevious()),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    color: DarkroomTheme.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: DarkroomPillButton(
                  height: 42,
                  padding: EdgeInsets.zero,
                  tooltip: '다음 문장',
                  onPressed: () => unawaited(handler.skipToNext()),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: DarkroomTheme.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: isCompact ? 68 : 82,
                child: ValueListenableBuilder<bool>(
                  valueListenable: handler.isPlayingNotifier,
                  builder: (_, isPlaying, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: handler.isLoadingSentenceNotifier,
                      builder: (_, isLoading, _) {
                        return DarkroomPillButton(
                          height: 48,
                          padding: EdgeInsets.zero,
                          variant: DarkroomButtonVariant.primaryCta,
                          tooltip: isPlaying ? '일시정지' : '재생',
                          onPressed: () {
                            if (isPlaying) {
                              unawaited(handler.pause());
                            } else {
                              unawaited(handler.play());
                            }
                          },
                          child: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DarkroomTheme.ctaText,
                                  ),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: DarkroomTheme.ctaText,
                                  size: 28,
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              DarkroomPillButton(
                height: 42,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 16,
                ),
                tooltip: '퇴고 북마크',
                onPressed: handler.triggerBookmark,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bookmark_rounded,
                      size: 16,
                      color: DarkroomTheme.filamentGold,
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '퇴고 북마크',
                        style: TextStyle(
                          color: DarkroomTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<double>(
                valueListenable: handler.speedNotifier,
                builder: (_, speed, _) {
                  return ValueListenableBuilder<String>(
                    valueListenable: handler.voiceNotifier,
                    builder: (_, voiceId, _) {
                      final shortVoice = EdgeTtsService.shortLabelFor(voiceId);
                      final label = isCompact
                          ? '${speed.toStringAsFixed(1)}x'
                          : '${speed.toStringAsFixed(1)}x · $shortVoice';
                      return DarkroomPillButton(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tooltip: '음성 · 배속 · 타이머 설정',
                        onPressed: () => SpeedAndVoiceSheet.show(
                          context,
                          controller: widget.controller,
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: DarkroomTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEpisodesBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: DarkroomTheme.backdropPalette,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.68,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '회차 목록',
                style: TextStyle(
                  color: DarkroomTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildEpisodeList()),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
  });

  final EpisodeItem episode;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? DarkroomTheme.bgElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
          border: Border.all(
            color: isActive
                ? DarkroomTheme.borderSpecularStrong
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: isActive
                  ? EmberCoreDot(live: isPlaying, useGold: true, size: 7)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                episode.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive
                      ? DarkroomTheme.textPrimary
                      : DarkroomTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              episode.typeBadge,
              style: const TextStyle(
                color: DarkroomTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
