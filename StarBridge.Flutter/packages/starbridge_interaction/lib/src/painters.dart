import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Shared drawing primitives. Everything here is plain canvas work: rects,
/// strokes and gradients, no blur filters or layers.

/// Eight short strokes framing [rect]'s corners (scan suite).
void paintBrackets(
  Canvas canvas,
  Rect rect, {
  required Color color,
  double length = 7,
  double width = 2,
}) {
  if (color.a == 0) return;
  final paint = Paint()..color = color;
  final l = math.min(length, math.min(rect.width, rect.height) / 2);
  for (final corner in [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ]) {
    final dx = corner.dx == rect.left ? 1.0 : -1.0;
    final dy = corner.dy == rect.top ? 1.0 : -1.0;
    canvas.drawRect(
      Rect.fromPoints(corner, corner + Offset(dx * l, dy * width)),
      paint,
    );
    canvas.drawRect(
      Rect.fromPoints(corner, corner + Offset(dx * width, dy * l)),
      paint,
    );
  }
}

/// A soft band sweeping left to right across [bounds] at progress [t].
/// Caller clips to the control shape.
void paintBeam(Canvas canvas, Rect bounds, double t, Color color) {
  if (t <= 0 || t >= 1) return;
  final w = bounds.width * 0.55;
  final x = lerpDouble(bounds.left - w * 1.1, bounds.right + w * 0.1, t)!;
  final band = Rect.fromLTWH(x, bounds.top, w, bounds.height);
  canvas.drawRect(
    band,
    Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
      ).createShader(band),
  );
}

/// A 2 px line travelling top to bottom with a short fading trail. The trail
/// is a gradient, not a blur. Caller clips.
void paintScanLine(Canvas canvas, Rect bounds, double t, Color color) {
  if (t <= 0 || t >= 1) return;
  final y = bounds.top + bounds.height * t;
  final fade = 1 - t * 0.75;
  final trail = Rect.fromLTRB(bounds.left, y - 10, bounds.right, y);
  canvas.drawRect(
    trail,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.35 * fade),
        ],
      ).createShader(trail),
  );
  canvas.drawRect(
    Rect.fromLTRB(bounds.left, y, bounds.right, y + 2),
    Paint()..color = color.withValues(alpha: color.a * fade),
  );
}

/// One expanding ring at [center] (glow suite). [t] is linear progress.
void paintRing(
  Canvas canvas,
  Offset center,
  double t,
  Color color, {
  double radius = 9,
  double maxScale = 3.2,
}) {
  if (t <= 0 || t >= 1) return;
  final e = const Cubic(0.2, 0, 0, 1).transform(t);
  final r = radius * lerpDouble(0.4, maxScale, e)!;
  canvas.drawCircle(
    center,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * (1 - 0.4 * t)
      ..color = color.withValues(alpha: 0.95 * (1 - t)),
  );
}

/// Imitation outer glow: three widening strokes with falling alpha. Much
/// cheaper than a mask blur and stays crisp at any DPI.
void paintGlowStrokes(
  Canvas canvas,
  RRect rrect,
  Color color,
  double strength,
) {
  if (strength <= 0) return;
  const steps = [(1.0, 0.55), (3.0, 0.22), (6.0, 0.09)];
  for (final (inflate, alpha) in steps) {
    canvas.drawRRect(
      rrect.inflate(inflate),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = inflate <= 1 ? 1.2 : 2.5
        ..color = color.withValues(alpha: alpha * strength),
    );
  }
}

/// Paint-only cutout for a native floating label. The outer area permits the
/// approved corner/glow overshoot; no render or semantic subtree is clipped.
void clipPaintExclusion(Canvas canvas, Size size, Rect? exclusion) {
  if (exclusion == null) return;
  canvas.clipPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(24))
      ..addRect(exclusion),
  );
}

/// Elliptical light from the left middle of [rrect] (glow hover and
/// selection): reaches ~90 % of the width and 1.6× the height, clipped to
/// the shape. Drawn as a scaled circle so the falloff stays smooth.
void paintSideGlow(Canvas canvas, RRect rrect, Color color, double alpha) {
  if (alpha <= 0) return;
  final rect = rrect.outerRect;
  final r = rect.height * 1.6;
  final sx = rect.width * 0.9 / r;
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.translate(rect.left, rect.center.dy);
  canvas.scale(sx, 1);
  canvas.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
  );
  canvas.restore();
}

/// Horizontal gradient fill fading to the right (rail selection face).
void paintRailFace(Canvas canvas, RRect rrect, Color color, double alpha) {
  if (alpha <= 0) return;
  final rect = rrect.outerRect;
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.2),
        ],
        stops: const [0, 0.8],
      ).createShader(rect),
  );
}

/// A vertical bar on the left edge of [rect], scaled vertically by [scale].
void paintSideBar(
  Canvas canvas,
  Rect rect,
  Color color, {
  double scale = 1,
  double inset = 8,
  double width = 3,
  Color? glow,
}) {
  if (scale <= 0) return;
  final full = rect.height - inset * 2;
  final h = full * scale;
  final top = rect.center.dy - h / 2;
  final bar = RRect.fromRectAndCorners(
    Rect.fromLTWH(rect.left, top, width, h),
    topRight: const Radius.circular(2),
    bottomRight: const Radius.circular(2),
  );
  if (glow != null) paintGlowStrokes(canvas, bar, glow, 0.9);
  canvas.drawRRect(bar, Paint()..color = color);
}

/// A horizontal line along the bottom (or top) of [rect], growing from the
/// left by [scale].
void paintEdgeLine(
  Canvas canvas,
  Rect rect,
  Color color, {
  double scale = 1,
  double height = 2,
  bool top = false,
  Color? glow,
}) {
  if (scale <= 0) return;
  final y = top ? rect.top : rect.bottom - height;
  final line = Rect.fromLTWH(rect.left, y, rect.width * scale, height);
  if (glow != null) {
    paintGlowStrokes(canvas, RRect.fromRectXY(line, 1, 1), glow, 0.7);
  }
  canvas.drawRect(line, Paint()..color = color);
}
