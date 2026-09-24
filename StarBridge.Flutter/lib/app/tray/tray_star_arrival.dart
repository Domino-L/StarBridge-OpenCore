import 'package:flutter/material.dart';

/// Approved V2: a white star travels to the actual logo, revealing the menu.
/// This does not use the rejected star-shaped clipping experiment.
class TrayStarArrival extends StatefulWidget {
  const TrayStarArrival({
    required this.child,
    required this.logoKey,
    this.reduceMotion = false,
    this.keyboard = false,
    super.key,
  });
  final Widget child;
  final GlobalKey logoKey;
  final bool reduceMotion, keyboard;
  @override
  State<TrayStarArrival> createState() => _TrayStarArrivalState();
}

class _TrayStarArrivalState extends State<TrayStarArrival>
    with SingleTickerProviderStateMixin {
  final _frame = GlobalKey();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Offset? _landing;
  bool _started = false;
  bool get _instant =>
      widget.reduceMotion ||
      widget.keyboard ||
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  void _finish() {
    if (_animation.value != 1) _animation.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_instant) {
      _finish();
      return;
    }
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final frame = _frame.currentContext?.findRenderObject();
      final logo = widget.logoKey.currentContext?.findRenderObject();
      if (frame is RenderBox && logo is RenderBox) {
        _landing = frame.globalToLocal(
          logo.localToGlobal(logo.size.center(Offset.zero)),
        );
        _animation.forward();
      } else {
        _finish();
      }
    });
  }

  @override
  void didUpdateWidget(TrayStarArrival old) {
    super.didUpdateWidget(old);
    if (_instant) _finish();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _finish(),
    child: Focus(
      onKeyEvent: (_, _) {
        _finish();
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _animation,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final t = const Cubic(.2, .65, .3, 1).transform(_animation.value);
          return Stack(
            key: _frame,
            children: [
              Opacity(opacity: t, alwaysIncludeSemantics: true, child: child),
              if (t < 1 && _landing != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _ArrivalStar(t, _landing!)),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _ArrivalStar extends CustomPainter {
  const _ArrivalStar(this.progress, this.target);
  final double progress;
  final Offset target;
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width - 22, size.height - 22);
    final center = Offset.lerp(start, target, progress)!;
    final radius = 15 - 3 * progress;
    final path = Path()
      ..moveTo(0, -radius)
      ..cubicTo(
        radius * .08,
        -radius * .12,
        radius * .12,
        -radius * .08,
        radius,
        0,
      )
      ..cubicTo(
        radius * .12,
        radius * .08,
        radius * .08,
        radius * .12,
        0,
        radius,
      )
      ..cubicTo(
        -radius * .08,
        radius * .12,
        -radius * .12,
        radius * .08,
        -radius,
        0,
      )
      ..cubicTo(
        -radius * .12,
        -radius * .08,
        -radius * .08,
        -radius * .12,
        0,
        -radius,
      )
      ..close();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(
          alpha: ((1 - progress) / .14).clamp(0, 1),
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArrivalStar old) =>
      old.progress != progress || old.target != target;
}
