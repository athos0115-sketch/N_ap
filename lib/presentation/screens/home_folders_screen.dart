import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../audio/playback_controller.dart';
import '../../core/theme/darkroom_theme.dart';
import '../../data/models/novel_folder.dart';
import '../widgets/darkroom_components.dart';
import 'bookmarks_screen.dart';
import 'player_screen.dart';

/// Darkroom Filament 홈 화면: Google Drive 계정 연결, 소설 폴더 등록/관리,
/// 및 하단 미니 플레이어 바를 제공한다.
class HomeFoldersScreen extends StatefulWidget {
  const HomeFoldersScreen({
    super.key,
    required this.controller,
  });

  final PlaybackController controller;

  @override
  State<HomeFoldersScreen> createState() => _HomeFoldersScreenState();
}

class _HomeFoldersScreenState extends State<HomeFoldersScreen> {
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
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'N_ap',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '퇴고 메모',
            icon: const Icon(Icons.bookmarks_outlined, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BookmarksScreen(controller: controller),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Google OAuth 설정',
            icon: const Icon(Icons.tune_outlined, size: 20),
            onPressed: _showOAuthConfigDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDriveAccountCard(),
                    const SizedBox(height: 16),
                    _buildFolderActionsRow(),
                    const SizedBox(height: 24),
                    const Text(
                      '등록된 소설 폴더',
                      style: TextStyle(
                        color: DarkroomTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (controller.folders.isEmpty)
                      _buildEmptyFoldersCard()
                    else
                      ...controller.folders.map(_buildFolderTile),
                  ],
                );
              },
            ),
          ),
          _buildMiniPlayerBar(),
        ],
      ),
    );
  }

  Widget _buildDriveAccountCard() {
    final drive = widget.controller.driveService;

    return ValueListenableBuilder(
      valueListenable: drive.currentUserNotifier,
      builder: (context, user, _) {
        final signedIn = user != null;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DarkroomTheme.bgSurface,
            borderRadius: BorderRadius.circular(DarkroomTheme.radiusCard),
            border: Border.all(color: DarkroomTheme.borderSpecular),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: EmberCoreDot(
                  live: signedIn,
                  useGold: true,
                  size: 8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn
                          ? (user.displayName ?? user.email)
                          : 'Google Drive 미연결',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DarkroomTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      signedIn
                          ? user.email
                          : '원고 폴더 조회와 퇴고 메모 동기화를 위해 계정을 연결하세요',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DarkroomTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DarkroomPillButton(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                variant: signedIn
                    ? DarkroomButtonVariant.ghost
                    : DarkroomButtonVariant.primaryCta,
                onPressed: () {
                  if (signedIn) {
                    unawaited(widget.controller.signOutGoogle());
                  } else {
                    unawaited(widget.controller.signInGoogle());
                  }
                },
                child: Text(
                  signedIn ? '연결 해제' : '계정 연결',
                  style: TextStyle(
                    color: signedIn
                        ? DarkroomTheme.textSecondary
                        : DarkroomTheme.ctaText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderActionsRow() {
    return Row(
      children: [
        Expanded(
          child: DarkroomPillButton(
            height: 44,
            variant: DarkroomButtonVariant.primaryCta,
            onPressed: _openDriveFolderBrowser,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.create_new_folder_outlined,
                  size: 17,
                  color: DarkroomTheme.ctaText,
                ),
                SizedBox(width: 8),
                Text(
                  'Drive 폴더 탐색',
                  style: TextStyle(
                    color: DarkroomTheme.ctaText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DarkroomPillButton(
            height: 44,
            variant: DarkroomButtonVariant.ghost,
            onPressed: _showAddByIdDialog,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.link_outlined,
                  size: 17,
                  color: DarkroomTheme.textSecondary,
                ),
                SizedBox(width: 8),
                Text(
                  'URL · ID 등록',
                  style: TextStyle(
                    color: DarkroomTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyFoldersCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DarkroomTheme.bgSurface,
        borderRadius: BorderRadius.circular(DarkroomTheme.radiusCard),
        border: Border.all(color: DarkroomTheme.borderSpecular),
      ),
      child: const Text(
        '등록된 소설 폴더가 없습니다\n상단의 Drive 폴더 탐색으로 원고가 담긴 폴더를 추가하세요\n(.txt · .md · Google Docs 자연 정렬 지원)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: DarkroomTheme.textMuted,
          fontSize: 13,
          height: 1.65,
        ),
      ),
    );
  }

  Widget _buildFolderTile(NovelFolder folder) {
    final isActive = widget.controller.activeFolder?.id == folder.id;
    final resumeLabel = folder.lastFileName != null
        ? '최근: ${folder.lastFileName} · #${folder.lastSentenceIndex + 1}문장'
        : '재생 기록 없음';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
        onTap: () => _openFolderPlayer(folder),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? DarkroomTheme.bgElevated : DarkroomTheme.bgSurface,
            borderRadius: BorderRadius.circular(DarkroomTheme.radiusItem),
            border: Border.all(
              color: isActive
                  ? DarkroomTheme.borderSpecularStrong
                  : DarkroomTheme.borderSpecular,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: isActive
                    ? const EmberCoreDot(live: true, useGold: true, size: 7)
                    : const Icon(
                        Icons.folder_outlined,
                        color: DarkroomTheme.textMuted,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DarkroomTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      resumeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DarkroomTheme.textSecondary,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '폴더 삭제',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: DarkroomTheme.textMuted,
                ),
                onPressed: () =>
                    unawaited(widget.controller.removeFolder(folder.id)),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: DarkroomTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 폴더 목록 화면에서도 재생 상태를 확인하고 제어할 수 있는 하단 미니 플레이어 바.
  Widget _buildMiniPlayerBar() {
    final handler = widget.controller.audioHandler;

    return ValueListenableBuilder<List<String>>(
      valueListenable: handler.sentencesNotifier,
      builder: (context, sentences, _) {
        if (sentences.isEmpty) return const SizedBox.shrink();

        return ValueListenableBuilder<int>(
          valueListenable: handler.currentIndexNotifier,
          builder: (context, index, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: handler.isPlayingNotifier,
              builder: (context, isPlaying, _) {
                final epTitle =
                    widget.controller.activeEpisode?.displayTitle ??
                    handler.episodeTitleNotifier.value;
                final safeIdx = index.clamp(0, sentences.length - 1);
                final preview = sentences[safeIdx];

                return SafeArea(
                  top: false,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlayerScreen(controller: widget.controller),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: DarkroomTheme.bgSidebar,
                        border: Border(
                          top: BorderSide(color: DarkroomTheme.borderSpecular),
                        ),
                      ),
                      child: Row(
                        children: [
                          EmberCoreDot(live: isPlaying, useGold: true, size: 7),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$epTitle · ${safeIdx + 1}/${sentences.length}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: DarkroomTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: DarkroomTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          DarkroomPillButton(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            variant: DarkroomButtonVariant.primaryCta,
                            onPressed: () {
                              if (isPlaying) {
                                unawaited(handler.pause());
                              } else {
                                unawaited(handler.play());
                              }
                            },
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: DarkroomTheme.ctaText,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openFolderPlayer(NovelFolder folder) async {
    unawaited(widget.controller.openFolder(folder, autoLoadLastEpisode: true));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _openDriveFolderBrowser() async {
    if (!widget.controller.driveService.isSignedIn) {
      final ok = await widget.controller.signInGoogle();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: DarkroomTheme.backdropPalette,
      builder: (_) => _DriveFolderPickerSheet(controller: widget.controller),
    );
  }

  Future<void> _showAddByIdDialog() async {
    final textController = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Drive 폴더 URL 또는 ID 등록',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'https://drive.google.com/drive/folders/...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (submitted != null && submitted.trim().isNotEmpty) {
      await widget.controller.registerFolderByInput(submitted);
    }
  }

  Future<void> _showOAuthConfigDialog() async {
    final initial = widget.controller.storageService.loadServerClientId() ?? '';
    final textController = TextEditingController(text: initial);
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Google OAuth Web Client ID',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'google-services.json 없이 Android Credential Manager로 Google Drive를 연결할 때 필요한 Web Client ID입니다',
              style: TextStyle(
                color: DarkroomTheme.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: 'xxxx.apps.googleusercontent.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (submitted != null) {
      await widget.controller.updateServerClientId(submitted);
    }
  }
}

class _DriveFolderPickerSheet extends StatefulWidget {
  const _DriveFolderPickerSheet({required this.controller});

  final PlaybackController controller;

  @override
  State<_DriveFolderPickerSheet> createState() =>
      _DriveFolderPickerSheetState();
}

class _DriveFolderPickerSheetState extends State<_DriveFolderPickerSheet> {
  final List<NovelFolder> _breadcrumbs = [
    const NovelFolder(id: 'root', name: '내 드라이브'),
  ];
  List<NovelFolder> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCurrent());
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parentId = _breadcrumbs.last.id;
      final list = await widget.controller.driveService.listFolders(
        parentId: parentId,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _breadcrumbs.last;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                if (_breadcrumbs.length > 1)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () {
                      _breadcrumbs.removeLast();
                      unawaited(_loadCurrent());
                    },
                  ),
                Expanded(
                  child: Text(
                    current.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DarkroomTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (current.id != 'root')
                  DarkroomPillButton(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    variant: DarkroomButtonVariant.primaryCta,
                    onPressed: () async {
                      await widget.controller.registerFolder(current);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text(
                      '현재 폴더 등록',
                      style: TextStyle(
                        color: DarkroomTheme.ctaText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: DarkroomTheme.statusDangerText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : _items.isEmpty
                ? const Center(
                    child: Text(
                      '하위 폴더가 없습니다',
                      style: TextStyle(color: DarkroomTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final folder = _items[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: DarkroomTheme.bgInset,
                          borderRadius: BorderRadius.circular(
                            DarkroomTheme.radiusItem,
                          ),
                          border: Border.all(
                            color: DarkroomTheme.borderSpecular,
                          ),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.folder_outlined,
                            color: DarkroomTheme.textSecondary,
                            size: 20,
                          ),
                          title: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: DarkroomTheme.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () {
                            _breadcrumbs.add(folder);
                            unawaited(_loadCurrent());
                          },
                          trailing: DarkroomPillButton(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: () async {
                              await widget.controller.registerFolder(folder);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text(
                              '등록',
                              style: TextStyle(
                                color: DarkroomTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
