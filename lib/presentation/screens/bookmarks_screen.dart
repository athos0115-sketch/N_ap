import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../audio/playback_controller.dart';
import '../../core/theme/darkroom_theme.dart';
import '../../data/models/revision_bookmark.dart';
import '../widgets/darkroom_components.dart';
import 'player_screen.dart';

/// Darkroom Filament 퇴고 북마크 로그 화면.
/// 항목을 탭하면 해당 회차와 문장 위치로 즉시 이동해 재생한다.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({
    super.key,
    required this.controller,
    this.openedFromPlayer = false,
  });

  final PlaybackController controller;
  final bool openedFromPlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '퇴고 메모',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: '전체 마크다운 복사',
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            onPressed: () => _copyAllMarkdown(context),
          ),
          IconButton(
            tooltip: 'Drive 미동기화 항목 전송',
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            onPressed: () => unawaited(controller.syncPendingBookmarks()),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final bookmarks = controller.bookmarks;
          if (bookmarks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '아직 기록된 퇴고 북마크가 없습니다\n청취 중 어색한 문장이 들리면 퇴고 북마크를 눌러 표시하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DarkroomTheme.textMuted,
                    fontSize: 13,
                    height: 1.65,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookmarks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = bookmarks[index];
              return BookmarkLogCard(
                bookmark: item,
                onTap: () => _handleJump(context, item),
                onDelete: () => unawaited(controller.deleteBookmark(item.id)),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleJump(
    BuildContext context,
    RevisionBookmark bookmark,
  ) async {
    final jumped = await controller.jumpToBookmark(bookmark);
    if (!jumped || !context.mounted) return;
    if (openedFromPlayer) {
      Navigator.of(context).pop();
    } else {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(controller: controller),
        ),
      );
    }
  }

  Future<void> _copyAllMarkdown(BuildContext context) async {
    final bookmarks = controller.bookmarks;
    if (bookmarks.isEmpty) return;
    final text = bookmarks.map((b) => b.toMarkdownLine()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴고 북마크 마크다운을 클립보드에 복사했습니다')),
      );
    }
  }
}

/// 개별 퇴고 북마크 카드 (단독 화면 및 폴드 2-Pane 좌측 패널 공용).
class BookmarkLogCard extends StatelessWidget {
  const BookmarkLogCard({
    super.key,
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  final RevisionBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${bookmark.timestamp.month.toString().padLeft(2, '0')}-'
        '${bookmark.timestamp.day.toString().padLeft(2, '0')} '
        '${bookmark.timestamp.hour.toString().padLeft(2, '0')}:'
        '${bookmark.timestamp.minute.toString().padLeft(2, '0')}';

    return InkWell(
      borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DarkroomTheme.bgSurface,
          borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
          border: Border.all(color: DarkroomTheme.borderSpecular),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bookmark.syncedToDrive
                        ? DarkroomTheme.filamentGoldBg
                        : DarkroomTheme.filamentNeutralBg,
                    borderRadius: BorderRadius.circular(DarkroomTheme.radiusXs),
                    border: Border.all(
                      color: bookmark.syncedToDrive
                          ? DarkroomTheme.filamentGoldBorder
                          : DarkroomTheme.filamentNeutralBorder,
                    ),
                  ),
                  child: Text(
                    bookmark.syncedToDrive ? 'Synced' : 'Local',
                    style: TextStyle(
                      color: bookmark.syncedToDrive
                          ? DarkroomTheme.filamentGold
                          : DarkroomTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${bookmark.episodeTitle} · #${bookmark.sentenceIndex + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DarkroomTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  ts,
                  style: const TextStyle(
                    color: DarkroomTheme.textMuted,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(
                    Icons.close,
                    size: 15,
                    color: DarkroomTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bookmark.sentenceText,
              style: const TextStyle(
                color: DarkroomTheme.textPrimary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2-Pane 좌측 패널용 컴팩트 퇴고 로그 리스트.
class InlineBookmarksPane extends StatelessWidget {
  const InlineBookmarksPane({
    super.key,
    required this.controller,
  });

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final bookmarks = controller.bookmarks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '기록 ${bookmarks.length}건',
                  style: const TextStyle(
                    color: DarkroomTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              DarkroomPillButton(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onPressed: bookmarks.isEmpty
                    ? null
                    : () => unawaited(controller.syncPendingBookmarks()),
                child: const Text(
                  'Drive 동기화',
                  style: TextStyle(
                    color: DarkroomTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: bookmarks.isEmpty
              ? const Center(
                  child: Text(
                    '퇴고 메모가 없습니다',
                    style: TextStyle(
                      color: DarkroomTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = bookmarks[index];
                    return BookmarkLogCard(
                      bookmark: item,
                      onTap: () => unawaited(controller.jumpToBookmark(item)),
                      onDelete: () =>
                          unawaited(controller.deleteBookmark(item.id)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
