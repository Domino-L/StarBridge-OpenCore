part of 'selection_track.dart';

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter(
    this.s,
    this.data,
    Listenable repaint, {
    required this.front,
  }) : super(repaint: repaint);

  final SuiteSelectionTrackState s;
  final InteractionData data;

  /// Front pass: brackets, beams and rings drawn above the item content.
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = s._currentRect();
    if (rect == null) return;
    final opacity = s._opacity;
    final p = data.palette;
    final style = s.widget.style;
    final suite = data.suite;
    final radius = suiteRadius(suite, style == TrackStyle.segmented ? 5 : 6);
    final rrect = radius.toRRect(rect);
    Color a(Color c) => c.withValues(alpha: c.a * opacity);

    if (!front) {
      switch (style) {
        case TrackStyle.navigation:
          switch (suite) {
            case InteractionSuite.standard:
              canvas.drawRRect(rrect, Paint()..color = p.selectedFill);
              paintSideBar(canvas, rect, p.accent);
            case InteractionSuite.rail:
              paintRailFace(canvas, rrect, p.accent, p.isDark ? 0.30 : 0.20);
              paintSideBar(
                canvas,
                rect,
                p.edge(),
                glow: p.isDark ? p.edge() : null,
              );
            case InteractionSuite.scan:
              canvas.drawRRect(
                rrect,
                Paint()..color = a(p.selectedFill.withValues(alpha: 0.85)),
              );
              canvas.drawRect(
                Rect.fromLTWH(rect.left, rect.top + 8, 3, rect.height - 16),
                Paint()..color = a(p.accent),
              );
            case InteractionSuite.glow:
              paintSideGlow(canvas, rrect, p.accent, p.isDark ? 0.38 : 0.26);
              if (p.isDark) paintGlowStrokes(canvas, rrect, p.accent, 0.25);
              paintSideBar(canvas, rect, p.edge(), glow: p.edge());
          }
        case TrackStyle.tabs:
          final line = Rect.fromLTWH(rect.left, size.height - 1, rect.width, 2);
          switch (suite) {
            case InteractionSuite.standard:
              canvas.drawRect(line, Paint()..color = p.accent);
            case InteractionSuite.rail:
              paintGlowStrokes(
                canvas,
                RRect.fromRectXY(line, 1, 1),
                p.edge(),
                p.isDark ? 0.8 : 0.4,
              );
              canvas.drawRect(line, Paint()..color = p.edge());
            case InteractionSuite.scan:
              canvas.drawRect(line, Paint()..color = a(p.accent));
            case InteractionSuite.glow:
              final glowRect = Rect.fromLTRB(
                rect.left,
                rect.top,
                rect.right,
                size.height,
              );
              canvas.drawRect(
                glowRect,
                Paint()
                  ..shader = RadialGradient(
                    center: Alignment.bottomCenter,
                    radius: 0.9,
                    colors: [p.light(0.22), p.light(0)],
                  ).createShader(glowRect),
              );
              paintGlowStrokes(
                canvas,
                RRect.fromRectXY(line, 1, 1),
                p.accent,
                1,
              );
              canvas.drawRect(line, Paint()..color = p.accent);
          }
        case TrackStyle.segmented:
          switch (suite) {
            case InteractionSuite.standard:
              canvas.drawRRect(rrect, Paint()..color = p.selectedFill);
            case InteractionSuite.rail:
              canvas.drawRRect(
                rrect,
                Paint()
                  ..shader = LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.light(0.10), p.light(0.30)],
                  ).createShader(rect),
              );
              canvas.save();
              canvas.clipRRect(rrect);
              paintEdgeLine(canvas, rect, p.edge());
              canvas.restore();
            case InteractionSuite.scan:
              canvas.drawRRect(
                rrect,
                Paint()..color = a(p.selectedFill.withValues(alpha: 0.9)),
              );
            case InteractionSuite.glow:
              canvas.drawRRect(
                rrect,
                Paint()
                  ..shader = RadialGradient(
                    center: Alignment.bottomCenter,
                    radius: 1.1,
                    colors: [p.light(0.42), p.light(0.08)],
                  ).createShader(rect),
              );
              if (p.isDark) paintGlowStrokes(canvas, rrect, p.accent, 0.35);
          }
      }
      return;
    }

    if (suite == InteractionSuite.scan) {
      paintBrackets(
        canvas,
        rect.deflate(3),
        color: a(p.edge()),
        length: style == TrackStyle.segmented ? 5 : 7,
      );
      final sweep = s._sweep.value;
      if (sweep > 0 && sweep < 1) {
        canvas.save();
        canvas.clipRRect(rrect);
        final e = SuiteMotion.curve.transform(sweep);
        paintBeam(
          canvas,
          rect,
          e,
          p.isDark
              ? const Color(0xFFAAE4FF).withValues(alpha: 0.75)
              : p.accent.withValues(alpha: 0.3),
        );
        if (style == TrackStyle.navigation) {
          paintScanLine(canvas, rect, e, p.edge());
        }
        canvas.restore();
      }
    }
    final ring = s._ring.value;
    if (suite == InteractionSuite.glow && ring > 0 && ring < 1) {
      final target = s._rectOf(s._target) ?? rect;
      final center = switch (style) {
        TrackStyle.navigation => Offset(target.left + 2, target.center.dy),
        TrackStyle.tabs => Offset(target.center.dx, size.height),
        TrackStyle.segmented => target.center,
      };
      paintRing(canvas, center, ring, p.edge());
    }
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) => old.data != data;
}

/// Calls [onLayout] after the frame whenever its child is laid out, so the
/// indicator follows resizes and font changes without rebuilding.
class _LayoutWatcher extends SingleChildRenderObjectWidget {
  const _LayoutWatcher({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutWatcher(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderLayoutWatcher r) =>
      r.onLayout = onLayout;
}

class _RenderLayoutWatcher extends RenderProxyBox {
  _RenderLayoutWatcher(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    SchedulerBinding.instance.addPostFrameCallback((_) => onLayout());
  }
}
