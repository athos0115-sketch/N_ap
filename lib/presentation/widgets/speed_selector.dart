import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../audio/playback_controller.dart';
import '../../core/theme/darkroom_theme.dart';
import '../../data/services/edge_tts_service.dart';
import 'darkroom_components.dart';

/// Darkroom Filament 오디오 · 음성 · 피치 · 뉘앙스 · 글자 크기 · 취침 타이머 통합 설정 시트.
class SpeedAndVoiceSheet extends StatelessWidget {
  const SpeedAndVoiceSheet({
    super.key,
    required this.controller,
  });

  final PlaybackController controller;

  static const List<double> _speedPresets = [0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0];

  static Future<void> show(
    BuildContext context, {
    required PlaybackController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DarkroomTheme.bgSurface,
      barrierColor: DarkroomTheme.backdropPalette,
      builder: (_) => SpeedAndVoiceSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = controller.audioHandler;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: DarkroomTheme.borderSpecularStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    '음성 및 청취 설정',
                    style: TextStyle(
                      color: DarkroomTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('Edge Neural TTS 음성 (여성 4 · 남성 2)'),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: handler.voiceNotifier,
                    builder: (_, currentVoice, _) {
                      return ValueListenableBuilder<String?>(
                        valueListenable: handler.previewingVoiceIdNotifier,
                        builder: (_, previewingId, _) {
                          return Column(
                            children: EdgeTtsService.availableKoreanVoices.map((
                              option,
                            ) {
                              final selected = option.id == currentVoice;
                              final isPreviewing = previewingId == option.id;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? DarkroomTheme.bgElevated
                                        : DarkroomTheme.bgInset,
                                    borderRadius: BorderRadius.circular(
                                      DarkroomTheme.radiusItem,
                                    ),
                                    border: Border.all(
                                      color: selected
                                          ? DarkroomTheme.borderSpecularStrong
                                          : DarkroomTheme.borderSpecular,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            DarkroomTheme.radiusItem,
                                          ),
                                          onTap: () => unawaited(
                                            controller.setVoice(option.id),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 11,
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 18,
                                                  child: selected
                                                      ? const EmberCoreDot(
                                                          live: true,
                                                          useGold: true,
                                                          size: 7,
                                                        )
                                                      : const SizedBox.shrink(),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    option.label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: selected
                                                          ? DarkroomTheme
                                                                .textPrimary
                                                          : DarkroomTheme
                                                                .textSecondary,
                                                      fontSize: 13,
                                                      fontWeight: selected
                                                          ? FontWeight.w500
                                                          : FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: DarkroomPillButton(
                                          height: 30,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          active: isPreviewing,
                                          onPressed: () {
                                            if (isPreviewing) {
                                              unawaited(
                                                handler.stopVoicePreview(),
                                              );
                                            } else {
                                              unawaited(
                                                handler.previewVoice(option.id),
                                              );
                                            }
                                          },
                                          child: isPreviewing
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 1.5,
                                                        color: DarkroomTheme
                                                            .filamentGold,
                                                      ),
                                                )
                                              : const Text(
                                                  '미리듣기',
                                                  style: TextStyle(
                                                    color: DarkroomTheme
                                                        .textSecondary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: handler.speedNotifier,
                    builder: (_, speed, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const _SectionLabel('재생 배속'),
                              Text(
                                '${speed.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  color: DarkroomTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _speedPresets.map((preset) {
                              final selected = (speed - preset).abs() < 0.05;
                              return SizedBox(
                                width: 62,
                                child: DarkroomPillButton(
                                  height: 34,
                                  padding: EdgeInsets.zero,
                                  variant: selected
                                      ? DarkroomButtonVariant.primaryCta
                                      : DarkroomButtonVariant.ghost,
                                  onPressed: () =>
                                      unawaited(controller.setSpeed(preset)),
                                  child: Text(
                                    '${preset.toStringAsFixed(1)}x',
                                    style: TextStyle(
                                      color: selected
                                          ? DarkroomTheme.ctaText
                                          : DarkroomTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          Slider(
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            value: speed.clamp(0.8, 2.0),
                            onChanged: (v) => unawaited(controller.setSpeed(v)),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: handler.pitchNotifier,
                    builder: (_, pitch, _) {
                      final label = pitch > 0 ? '+${pitch}Hz' : '${pitch}Hz';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const _SectionLabel('기본 톤 (피치 조절)'),
                              Row(
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: DarkroomTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  if (pitch != 0) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () =>
                                          unawaited(controller.setPitch(0)),
                                      child: const Text(
                                        '초기화',
                                        style: TextStyle(
                                          color: DarkroomTheme.filamentGold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          Slider(
                            min: -6,
                            max: 6,
                            divisions: 12,
                            value: pitch.toDouble(),
                            onChanged: (v) =>
                                unawaited(controller.setPitch(v.round())),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: handler.nuanceEnabledNotifier,
                    builder: (_, enabled, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: DarkroomTheme.bgInset,
                          borderRadius: BorderRadius.circular(
                            DarkroomTheme.radiusItem,
                          ),
                          border: Border.all(
                            color: DarkroomTheme.borderSpecular,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '대사 · 독백 SSML 뉘앙스',
                                    style: TextStyle(
                                      color: DarkroomTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '대사(+2Hz)와 괄호 독백(-3Hz, -5% 속도) 자동 구분',
                                    style: TextStyle(
                                      color: DarkroomTheme.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: enabled,
                              activeThumbColor: DarkroomTheme.ctaBg,
                              activeTrackColor: DarkroomTheme.filamentOrange,
                              inactiveThumbColor: DarkroomTheme.textSecondary,
                              inactiveTrackColor: DarkroomTheme.bgElevated,
                              onChanged: (v) =>
                                  unawaited(controller.setNuanceEnabled(v)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('원고 글자 크기'),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: controller.fontSizeLevelNotifier,
                    builder: (_, level, _) {
                      return DarkroomSegmentedTrack(
                        labels: const ['작게 (S)', '보통 (M)', '크게 (L)'],
                        selectedIndex: level,
                        onChanged: (i) =>
                            unawaited(controller.setFontSizeLevel(i)),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('취침 타이머'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SleepChip(
                        label: '꺼짐',
                        selected:
                            controller.sleepTimerMode == SleepTimerMode.off,
                        onTap: () =>
                            controller.setSleepTimer(SleepTimerMode.off),
                      ),
                      _SleepChip(
                        label: '15분',
                        selected:
                            controller.sleepTimerMode ==
                            SleepTimerMode.minutes15,
                        onTap: () =>
                            controller.setSleepTimer(SleepTimerMode.minutes15),
                      ),
                      _SleepChip(
                        label: '30분',
                        selected:
                            controller.sleepTimerMode ==
                            SleepTimerMode.minutes30,
                        onTap: () =>
                            controller.setSleepTimer(SleepTimerMode.minutes30),
                      ),
                      _SleepChip(
                        label: '60분',
                        selected:
                            controller.sleepTimerMode ==
                            SleepTimerMode.minutes60,
                        onTap: () =>
                            controller.setSleepTimer(SleepTimerMode.minutes60),
                      ),
                      _SleepChip(
                        label: '현재 화 종료',
                        selected:
                            controller.sleepTimerMode ==
                            SleepTimerMode.endOfEpisode,
                        onTap: () => controller.setSleepTimer(
                          SleepTimerMode.endOfEpisode,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: DarkroomTheme.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _SleepChip extends StatelessWidget {
  const _SleepChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: DarkroomPillButton(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        variant: selected
            ? DarkroomButtonVariant.primaryCta
            : DarkroomButtonVariant.ghost,
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? DarkroomTheme.ctaText
                : DarkroomTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
