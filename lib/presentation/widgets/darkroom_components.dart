import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/darkroom_theme.dart';

/// 1px Warm Rim-Light가 적용된 Darkroom 포컬 서피스.
/// UI_darkroom 규정에 따라 화면당 최대 2곳(상단 상태 필, 활성 문장 카드)에만 사용한다.
class WarmRimSurface extends StatelessWidget {
  const WarmRimSurface({
    super.key,
    required this.child,
    this.radius = DarkroomTheme.radiusCard,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = DarkroomTheme.bgSurface,
    this.enableWarmRim = true,
    this.warmIntensity = 1.0,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final bool enableWarmRim;
  final double warmIntensity;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: DarkroomTheme.shadowCard,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _WarmRimBorderPainter(
          radius: radius,
          enableWarmRim: enableWarmRim,
          warmIntensity: warmIntensity,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              if (enableWarmRim)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 24,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            DarkroomTheme.rimWash.withValues(
                              alpha: 0.05 * warmIntensity.clamp(0.0, 1.0),
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarmRimBorderPainter extends CustomPainter {
  const _WarmRimBorderPainter({
    required this.radius,
    required this.enableWarmRim,
    required this.warmIntensity,
  });

  final double radius;
  final bool enableWarmRim;
  final double warmIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);

    // 기본 1px 스페큘러 헤어라인
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = DarkroomTheme.borderSpecular;
    canvas.drawRRect(rrect, basePaint);

    if (!enableWarmRim) return;

    // 상단 1px Warm Rim-Light (Gold -> Solar Orange -> Transparent)
    final topClipRect = Rect.fromLTWH(0, 0, size.width, math.min(size.height * 0.45, radius + 4));
    canvas.save();
    canvas.clipRect(topClipRect);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: const [0.0, 0.38, 0.78, 1.0],
        colors: [
          DarkroomTheme.rimGold.withValues(alpha: 0.48 * warmIntensity),
          DarkroomTheme.rimOrange.withValues(alpha: 0.30 * warmIntensity),
          DarkroomTheme.borderSpecular,
          DarkroomTheme.borderSpecular,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRRect(rrect, rimPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WarmRimBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.enableWarmRim != enableWarmRim ||
        oldDelegate.warmIntensity != warmIntensity;
  }
}

/// 라이브 상태에만 외곽 헤일로가 3200ms 주기로 미세 호흡하는 Ember Core Dot.
class EmberCoreDot extends StatefulWidget {
  const EmberCoreDot({
    super.key,
    this.live = true,
    this.useGold = true,
    this.size = 8,
  });

  final bool live;
  final bool useGold;
  final double size;

  @override
  State<EmberCoreDot> createState() => _EmberCoreDotState();
}

class _EmberCoreDotState extends State<EmberCoreDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DarkroomTheme.motionBreath,
    );
    if (widget.live) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant EmberCoreDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live != oldWidget.live) {
      if (widget.live) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.5;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final haloColor = widget.useGold
        ? DarkroomTheme.filamentGold
        : DarkroomTheme.filamentOrange;

    if (!widget.live || reduceMotion) {
      return _buildDot(
        haloOpacity: widget.live ? 0.72 : 0.25,
        haloScale: 1.0,
        haloColor: haloColor,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = Curves.easeInOutSine.transform(_controller.value);
        final opacity = 0.55 + (0.40 * t);
        final scale = 0.94 + (0.14 * t);
        return _buildDot(
          haloOpacity: opacity,
          haloScale: scale,
          haloColor: haloColor,
        );
      },
    );
  }

  Widget _buildDot({
    required double haloOpacity,
    required double haloScale,
    required Color haloColor,
  }) {
    final boxSize = widget.size * 2.2;
    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: haloScale,
            child: Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    haloColor.withValues(alpha: 0.45 * haloOpacity),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  DarkroomTheme.emberCore,
                  haloColor,
                  DarkroomTheme.filamentOrange,
                ],
                stops: const [0.0, 0.62, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum DarkroomButtonVariant { primaryCta, ghost, subtleSurface }

/// Darkroom Filament 필 버튼 (고대비 오프화이트 CTA / 고스트 글래스 필).
class DarkroomPillButton extends StatefulWidget {
  const DarkroomPillButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = DarkroomButtonVariant.ghost,
    this.height = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.radius = DarkroomTheme.radiusPill,
    this.active = false,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final DarkroomButtonVariant variant;
  final double height;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool active;
  final String? tooltip;

  @override
  State<DarkroomPillButton> createState() => _DarkroomPillButtonState();
}

class _DarkroomPillButtonState extends State<DarkroomPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    Color bg;
    Color border;
    switch (widget.variant) {
      case DarkroomButtonVariant.primaryCta:
        bg = _pressed ? DarkroomTheme.ctaPressed : DarkroomTheme.ctaBg;
        border = Colors.transparent;
      case DarkroomButtonVariant.ghost:
        bg = _pressed || widget.active
            ? DarkroomTheme.bgElevated
            : DarkroomTheme.btnGhostBg;
        border = widget.active
            ? DarkroomTheme.borderSpecularStrong
            : DarkroomTheme.borderSpecular;
      case DarkroomButtonVariant.subtleSurface:
        bg = _pressed || widget.active
            ? DarkroomTheme.bgElevated
            : DarkroomTheme.bgSurface;
        border = widget.active
            ? DarkroomTheme.borderSpecularStrong
            : DarkroomTheme.borderSpecular;
    }

    if (!enabled) {
      bg = DarkroomTheme.bgInset;
      border = DarkroomTheme.borderSubtle;
    }

    final body = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: DarkroomTheme.motionFast,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: DarkroomTheme.motionFast,
          curve: Curves.easeOutCubic,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: border, width: 1),
          ),
          child: Center(
            widthFactor: 1.0,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.45,
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: body);
    }
    return body;
  }
}

/// 인셋(`#0E0F12`) 트랙 위 `#1E2026` 활성 필을 사용하는 세그먼트 스위처.
class DarkroomSegmentedTrack extends StatelessWidget {
  const DarkroomSegmentedTrack({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DarkroomTheme.bgInset,
        borderRadius: BorderRadius.circular(DarkroomTheme.radiusPill),
        border: Border.all(color: DarkroomTheme.borderSpecular),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: DarkroomTheme.motionBase,
                curve: Curves.easeOutQuart,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? DarkroomTheme.bgElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DarkroomTheme.radiusPill),
                  border: Border.all(
                    color: selected
                        ? DarkroomTheme.borderSpecularStrong
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? DarkroomTheme.textPrimary
                        : DarkroomTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 8% 써멀 필라멘트 스펙트럼(Gold -> Solar Orange)을 적용한 헤어라인 진행 바.
class ThermalProgressBar extends StatelessWidget {
  const ThermalProgressBar({
    super.key,
    required this.progress,
  });

  final double progress;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth = constraints.maxWidth * clamped;
        return SizedBox(
          height: 12,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: DarkroomTheme.borderSpecularStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: fillWidth,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    colors: [
                      DarkroomTheme.filamentGold,
                      DarkroomTheme.filamentOrange,
                    ],
                  ),
                ),
              ),
              if (fillWidth > 0)
                Positioned(
                  left: (fillWidth - 4).clamp(0.0, math.max(0.0, constraints.maxWidth - 8)),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: DarkroomTheme.emberCore,
                      boxShadow: [
                        BoxShadow(
                          color: DarkroomTheme.filamentOrangeBorder,
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
