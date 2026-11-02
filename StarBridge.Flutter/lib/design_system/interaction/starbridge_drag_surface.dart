import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';
import '../tokens/starbridge_tokens.dart';

/// Paint-only drag feedback. The caller retains gesture, geometry and commit
/// ownership. Native Draggable feedback can outlive its source until pointer-up;
/// [isCurrent] retires that ghost without changing the physical drag gesture.
class StarBridgeDragSurface extends StatefulWidget {
  const StarBridgeDragSurface({required this.child, this.isCurrent, super.key});

  final Widget child;
  final bool Function()? isCurrent;

  @override
  State<StarBridgeDragSurface> createState() => _StarBridgeDragSurfaceState();
}

class _StarBridgeDragSurfaceState extends State<StarBridgeDragSurface>
    with SingleTickerProviderStateMixin {
  late final _cue = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  InteractionData? _data;
  bool _retired = false;
  bool _checkQueued = false;

  @override
  void initState() {
    super.initState();
    _checkCurrent();
  }

  void _checkCurrent() {
    if (_checkQueued || widget.isCurrent == null || _retired) return;
    _checkQueued = true;
    // Observe frames that already exist; never request idle frames to poll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (!mounted || _retired) return;
      if (!(widget.isCurrent?.call() ?? true)) {
        _cue.stop();
        setState(() => _retired = true);
      } else {
        _checkCurrent();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data =
        InteractionScope.maybeOf(context) ??
        resolveStarBridgeInteraction(context);
    final previous = _data;
    _data = data;
    if (!data.animates || data.suite == InteractionSuite.standard || _retired) {
      _cue.value = 1;
    } else if (previous == null || previous.suite != data.suite) {
      _cue.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant StarBridgeDragSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkCurrent();
  }

  @override
  void dispose() {
    _cue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _cue,
            child: widget.child,
            builder: (context, child) => CustomPaint(
              foregroundPainter: _DragPainter(
                _data!,
                _cue.value,
                context.tokens.shape.medium,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DragPainter extends CustomPainter {
  const _DragPainter(this.data, this.progress, this.radius);
  final InteractionData data;
  final double progress;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(1);
    final p = data.palette;
    final rrect =
        (data.suite == InteractionSuite.scan ? BorderRadius.zero : radius)
            .toRRect(rect);
    final c = SuiteMotion.curve.transform(progress.clamp(0, 1));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.focusRing,
    );
    switch (data.suite) {
      case InteractionSuite.standard:
        break;
      case InteractionSuite.rail:
        paintSideBar(canvas, rect, p.edge(), inset: 3, width: 2.5);
        final guide = Rect.fromLTWH(
          rect.center.dx - rect.width * c / 2,
          rect.top + 3,
          rect.width * c,
          2,
        );
        canvas.drawRect(guide, Paint()..color = p.edge());
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.deflate(2 + (data.animates ? 6 * (1 - c) : 0)),
          color: p.edge(),
          length: 8,
        );
      case InteractionSuite.glow:
        paintSideGlow(canvas, rrect, p.accent, 0.25);
        if (p.isDark) paintGlowStrokes(canvas, rrect, p.accent, 0.35);
    }
  }

  @override
  bool shouldRepaint(_DragPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.progress != progress ||
      oldDelegate.radius != radius;
}
