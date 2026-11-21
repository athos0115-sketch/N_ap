import 'package:material_ui/material_ui.dart';

import '../../core/theme/darkroom_theme.dart';
import 'darkroom_components.dart';

/// Darkroom Filament v1.1 원고 뷰어.
/// 현재 재생 문장에만 1px Warm Rim-Light를 적용하고, 나머지 문장은 정숙한 모노크롬 위계로 표시한다.
class ManuscriptViewer extends StatefulWidget {
  const ManuscriptViewer({
    super.key,
    required this.sentences,
    required this.currentIndex,
    required this.bufferedIndices,
    required this.fontSizeLevel,
    required this.isPlaying,
    required this.onTapSentence,
    this.touchLocked = false,
  });

  final List<String> sentences;
  final int currentIndex;
  final Set<int> bufferedIndices;
  final int fontSizeLevel; // 0: S, 1: M, 2: L
  final bool isPlaying;
  final ValueChanged<int> onTapSentence;
  final bool touchLocked;

  static double activeFontSizeFor(int level) {
    return switch (level) {
      0 => 14.5,
      2 => 19.0,
      _ => 16.5,
    };
  }

  static double inactiveFontSizeFor(int level) {
    return switch (level) {
      0 => 13.5,
      2 => 17.5,
      _ => 15.0,
    };
  }

  @override
  State<ManuscriptViewer> createState() => _ManuscriptViewerState();
}

class _ManuscriptViewerState extends State<ManuscriptViewer> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant ManuscriptViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentences != widget.sentences) {
      _itemKeys.clear();
    }
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.sentences != widget.sentences) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!mounted || widget.sentences.isEmpty) return;
    final key = _itemKeys[widget.currentIndex];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
      );
      return;
    }
    // 아직 화면 밖에 있어 렌더되지 않은 문장인 경우 대략적 위치로 먼저 점프 후 정밀 정렬
    if (_scrollController.hasClients && widget.currentIndex > 0) {
      final ratio = widget.currentIndex / widget.sentences.length;
      final approxOffset =
          (_scrollController.position.maxScrollExtent * ratio).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );
      _scrollController.jumpTo(approxOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final mountedCtx = _itemKeys[widget.currentIndex]?.currentContext;
        if (mountedCtx != null) {
          Scrollable.ensureVisible(
            mountedCtx,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: 0.34,
          );
        }
      });
    }
  }

  GlobalKey _keyForIndex(int index) {
    return _itemKeys.putIfAbsent(index, GlobalKey.new);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sentences.isEmpty) {
      return const Center(
        child: Text(
          '재생할 원고가 선택되지 않았습니다\n좌측 목록이나 폴더 화면에서 화를 선택해 주세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DarkroomTheme.textMuted,
            fontSize: 13,
            height: 1.65,
          ),
        ),
      );
    }

    final activeSize = ManuscriptViewer.activeFontSizeFor(widget.fontSizeLevel);
    final inactiveSize = ManuscriptViewer.inactiveFontSizeFor(
      widget.fontSizeLevel,
    );

    return AbsorbPointer(
      absorbing: widget.touchLocked,
      child: ListView.builder(
        controller: _scrollController,
        physics: widget.touchLocked
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        itemCount: widget.sentences.length,
      itemBuilder: (context, index) {
        final isActive = index == widget.currentIndex;
        final isBuffered = widget.bufferedIndices.contains(index);
        final text = widget.sentences[index];

        if (isActive) {
          return Padding(
            key: _keyForIndex(index),
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => widget.onTapSentence(index),
              child: WarmRimSurface(
                radius: DarkroomTheme.radiusCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                backgroundColor: DarkroomTheme.bgSurface,
                enableWarmRim: true,
                warmIntensity: widget.isPlaying ? 1.0 : 0.65,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: DarkroomTheme.filamentGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: DarkroomTheme.textPrimary,
                          fontSize: activeSize,
                          fontWeight: FontWeight.w500,
                          height: 1.72,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 비활성 문장은 박스·테두리 없이 캔버스 배경 위에 정숙한 텍스트로만 배치
        return Padding(
          key: _keyForIndex(index),
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onTapSentence(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: DarkroomTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (isBuffered)
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: DarkroomTheme.filamentGoldBorder,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: DarkroomTheme.textSecondary,
                        fontSize: inactiveSize,
                        fontWeight: FontWeight.w400,
                        height: 1.68,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      ),
    );
  }
}
