import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../platform/window/native_viewport_visibility.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';

/// Approved page timings; desktop rasters remain stationary in every suite.
({Duration enter, Duration exit}) starBridgePageDurations(
  InteractionData data,
) {
  if (!data.animates) return (enter: Duration.zero, exit: Duration.zero);
  return (
    enter: switch (data.suite) {
      InteractionSuite.standard => const Duration(milliseconds: 180),
      InteractionSuite.scan => const Duration(milliseconds: 320),
      _ => const Duration(milliseconds: 220),
    },
    exit: data.motion.exit,
  );
}

/// Fixed geometry and element path: masks/edge paint carry the suite, never
/// a fractional translation or scale of the desktop-sized child raster.
class StarBridgePageTransition extends StatelessWidget {
  const StarBridgePageTransition({
    required this.animation,
    required this.child,
    this.instant = false,
    this.active = true,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final bool instant;
  final bool active;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: RepaintBoundary(child: child),
    builder: (context, child) {
      final data =
          InteractionScope.maybeOf(context) ??
          resolveStarBridgeInteraction(context);
      final leaving =
          animation.status == AnimationStatus.reverse ||
          animation.status == AnimationStatus.dismissed;
      final v = (!data.animates || instant)
          ? (leaving ? 0.0 : 1.0)
          : animation.value;
      final progress = (leaving ? SuiteMotion.exitCurve : SuiteMotion.curve)
          .transform(v.clamp(0.0, 1.0));
      final viewportActive =
          NativeViewportScope.isActive(context) && active && !leaving;
      return NativeViewportScope(
        active: viewportActive,
        child: IgnorePointer(
          ignoring: !viewportActive,
          child: ExcludeFocus(
            excluding: !viewportActive,
            child: ExcludeSemantics(
              excluding: !viewportActive,
              child: Opacity(
                opacity: data.suite == InteractionSuite.scan && !leaving
                    ? 1
                    : progress,
                child: ClipRect(
                  clipper: _PageReveal(
                    data.suite == InteractionSuite.scan && !leaving
                        ? progress
                        : 1,
                  ),
                  child: CustomPaint(
                    foregroundPainter: _PageMark(
                      data.suite,
                      data.palette.accent,
                      progress,
                      leaving,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PageReveal extends CustomClipper<Rect> {
  const _PageReveal(this.progress);
  final double progress;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * progress);
  @override
  bool shouldReclip(_PageReveal old) => progress != old.progress;
}

class _PageMark extends CustomPainter {
  const _PageMark(this.suite, this.color, this.progress, this.leaving);
  final InteractionSuite suite;
  final Color color;
  final double progress;
  final bool leaving;
  @override
  void paint(Canvas canvas, Size size) {
    if (leaving || progress >= 1 || progress <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress) * .65);
    switch (suite) {
      case InteractionSuite.standard:
        break;
      case InteractionSuite.rail:
        final end = size.width * progress;
        canvas.drawRect(
          Rect.fromLTWH(
            (end - size.width * .18).clamp(0.0, size.width),
            0,
            (size.width * .18).clamp(0.0, end),
            2,
          ),
          paint,
        );
      case InteractionSuite.scan:
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * progress - 2, size.width, 2),
          paint,
        );
      case InteractionSuite.glow:
        paint.color = color.withValues(alpha: (1 - progress) * .2);
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 3;
        canvas.drawRect((Offset.zero & size).deflate(1.5), paint);
    }
  }

  @override
  bool shouldRepaint(_PageMark old) =>
      suite != old.suite ||
      color != old.color ||
      progress != old.progress ||
      leaving != old.leaving;
}

/// Like the approved content switcher, retires the old viewport immediately.
/// Selection/leave decisions stay with the caller; only keyed UI enters here.
class StarBridgePageSwitcher extends StatefulWidget {
  const StarBridgePageSwitcher({
    required this.child,
    this.instant = false,
    super.key,
  });
  final Widget child;
  final bool instant;
  @override
  State<StarBridgePageSwitcher> createState() => _PageSwitcherState();
}

class _PageSwitcherState extends State<StarBridgePageSwitcher>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this, value: 1);
  InteractionSuite? _suite;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data =
        InteractionScope.maybeOf(context) ??
        resolveStarBridgeInteraction(context);
    if (!data.animates || (_suite != null && _suite != data.suite)) {
      _animation.value = 1;
    }
    _suite = data.suite;
  }

  @override
  void didUpdateWidget(StarBridgePageSwitcher old) {
    super.didUpdateWidget(old);
    final data =
        InteractionScope.maybeOf(context) ??
        resolveStarBridgeInteraction(context);
    if (widget.instant || !data.animates) {
      _animation.value = 1;
      return;
    }
    if (Widget.canUpdate(old.child, widget.child)) return;
    _animation.duration = starBridgePageDurations(data).enter;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgePageTransition(
    animation: _animation,
    instant: widget.instant,
    child: starBridgeInitialReadViewport(
      context,
      source: widget.instant
          ? InteractionSource.keyboard
          : InteractionSource.programmatic,
      child: widget.child,
    ),
  );
}
