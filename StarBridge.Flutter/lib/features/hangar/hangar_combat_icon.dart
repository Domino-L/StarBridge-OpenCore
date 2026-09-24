import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'hangar_combat_motion.dart';
import 'hangar_combat_paths.dart';

class HangarCombatIcon extends StatefulWidget {
  const HangarCombatIcon({
    required this.sizeClass,
    required this.elapsed,
    this.active = true,
    this.dimension = 24,
    super.key,
  });
  final HangarCombatSize sizeClass;
  final Duration elapsed;
  final bool active;
  final double dimension;
  @override
  State<HangarCombatIcon> createState() => _HangarCombatIconState();
}

class _HangarCombatIconState extends State<HangarCombatIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.sizeClass.milliseconds),
      value:
          (widget.elapsed.inMicroseconds /
                  (widget.sizeClass.milliseconds * 1000))
              .clamp(0.0, 1.0),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        context.tokens.motion.surfaceEnter == Duration.zero;
    if (reduced || !widget.active) {
      _motion.stop();
      _motion.value = 1;
    } else if (!_started) {
      _motion.forward();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(covariant HangarCombatIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || oldWidget.sizeClass != widget.sizeClass) {
      _motion.stop();
      _motion.value = 1;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.dimension,
      child: CustomPaint(
        painter: HangarCombatPainter(
          sizeClass: widget.sizeClass,
          progress: _motion,
          hull: context.tokens.colors.textPrimary,
          ammunition: context.tokens.colors.danger,
        ),
      ),
    ),
  );
}

class HangarCombatPainter extends CustomPainter {
  HangarCombatPainter({
    required this.sizeClass,
    required this.progress,
    required this.hull,
    required this.ammunition,
  }) : super(repaint: progress);
  final HangarCombatSize sizeClass;
  final Animation<double> progress;
  final Color hull, ammunition;
  double get milliseconds => progress.value * sizeClass.milliseconds;

  @override
  void paint(Canvas canvas, Size size) {
    final paths = hangarCombatPaths[sizeClass.name]!;
    final ms = milliseconds;
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    // Fixed muzzle plane, behind the hull; ammunition never falls from above.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, 32, sizeClass.muzzleHeight));
    canvas.translate(0, HangarCombatMotion.ammoY(sizeClass, ms));
    canvas.drawPath(paths[3], Paint()..color = ammunition);
    canvas.restore();
    _transform(canvas, HangarCombatMotion.recoil(sizeClass, ms));
    for (final index in [0, 1, 2, 4]) {
      final part = HangarCombatMotion.part(sizeClass, index, ms);
      if (part.alpha <= 0) continue;
      canvas.save();
      _transform(canvas, part);
      canvas.drawPath(
        paths[index],
        Paint()..color = hull.withValues(alpha: hull.a * part.alpha),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  static void _transform(Canvas canvas, CombatPartFrame frame) {
    canvas.translate(frame.x + 16, frame.y + 16);
    canvas.scale(frame.sx, frame.sy);
    canvas.translate(-16, -16);
  }

  @override
  bool shouldRepaint(covariant HangarCombatPainter old) =>
      old.sizeClass != sizeClass ||
      old.progress != progress ||
      old.hull != hull ||
      old.ammunition != ammunition;
}
