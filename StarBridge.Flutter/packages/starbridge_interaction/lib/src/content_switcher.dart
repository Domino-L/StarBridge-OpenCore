import 'package:flutter/material.dart';

import 'suite.dart';

/// Swaps page or panel content. Give each content a distinct key.
///
/// Rail slides the new content in a short way from the leading side; scan
/// reveals it top to bottom behind a scan line; glow fades it in from a
/// hair below full scale. Standard cross-fades. The old content leaves
/// immediately (it is never kept interactive), so the new page is usable
/// from the first frame. Keyboard, back navigation ([instant]) and reduced
/// motion swap without animation.
class SuiteContentSwitcher extends StatefulWidget {
  const SuiteContentSwitcher({
    required this.child,
    this.instant = false,
    super.key,
  });

  final Widget child;

  /// Set for keyboard-initiated or back navigation.
  final bool instant;

  @override
  State<SuiteContentSwitcher> createState() => _SuiteContentSwitcherState();
}

class _SuiteContentSwitcherState extends State<SuiteContentSwitcher>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, value: 1);

  /// Keeps the page mounted when the entrance wrappers around it are taken
  /// away at the end, so the page is not rebuilt from scratch (its state,
  /// focus, text and scroll position survive the entrance).
  final _keep = GlobalKey(debugLabel: 'switcher-child');

  @override
  void didUpdateWidget(SuiteContentSwitcher old) {
    super.didUpdateWidget(old);
    if (Widget.canUpdate(old.child, widget.child)) return;
    final data = InteractionScope.of(context);
    if (!data.animates || widget.instant) {
      _t.value = 1;
      return;
    }
    _t.duration = switch (data.suite) {
      InteractionSuite.standard => const Duration(milliseconds: 180),
      InteractionSuite.scan => const Duration(milliseconds: 320),
      _ => const Duration(milliseconds: 220),
    };
    _t.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) _t.value = 1;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return AnimatedBuilder(
      animation: _t,
      child: RepaintBoundary(key: _keep, child: widget.child),
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        final c = SuiteMotion.curve.transform(v);
        switch (data.suite) {
          case InteractionSuite.standard:
            return Opacity(opacity: v, child: child);
          case InteractionSuite.rail:
            return Opacity(
              opacity: c,
              child: Transform.translate(
                offset: Offset(-10 * (1 - c), 0),
                child: child,
              ),
            );
          case InteractionSuite.scan:
            return Stack(
              children: [
                ClipRect(clipper: _TopReveal(c), child: child),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _RevealLine(c, data.palette)),
                  ),
                ),
              ],
            );
          case InteractionSuite.glow:
            return Opacity(
              opacity: c,
              child: Transform.scale(scale: 0.985 + 0.015 * c, child: child),
            );
        }
      },
    );
  }
}

class _TopReveal extends CustomClipper<Rect> {
  _TopReveal(this.f);
  final double f;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * f);

  @override
  bool shouldReclip(_TopReveal old) => old.f != f;
}

class _RevealLine extends CustomPainter {
  _RevealLine(this.f, this.p);
  final double f;
  final InteractionPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * f;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1, size.width, 2),
      Paint()..color = p.edge(0.9),
    );
  }

  @override
  bool shouldRepaint(_RevealLine old) => old.f != f;
}
