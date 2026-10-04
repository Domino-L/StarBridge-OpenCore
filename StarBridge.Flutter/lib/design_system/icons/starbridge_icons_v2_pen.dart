import 'dart:math' as math;

import 'package:flutter/material.dart';

enum IconOptic { compact, standard, display }

IconOptic iconOpticFor(double size) => size <= 17
    ? IconOptic.compact
    : size <= 21
    ? IconOptic.standard
    : IconOptic.display;

/// Drawing vocabulary for the grammar. All coordinates are on the 24 grid.
final class IconPen {
  IconPen(this.canvas, Color color, this.optic)
    : stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = switch (optic) {
          IconOptic.compact => 2.25,
          IconOptic.standard => 2.1,
          IconOptic.display => 2.0,
        }
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter
        ..strokeMiterLimit = 4,
      fill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

  final Canvas canvas;
  final IconOptic optic;
  final Paint stroke;
  final Paint fill;

  bool get fine => optic != IconOptic.compact;
  bool get display => optic == IconOptic.display;
  double get cutSize => fine ? 3.0 : 2.4;

  void l(double x1, double y1, double x2, double y2) =>
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);

  Path _path(List<double> xy, bool close) {
    final p = Path()..moveTo(xy[0], xy[1]);
    for (var i = 2; i < xy.length; i += 2) {
      p.lineTo(xy[i], xy[i + 1]);
    }
    if (close) p.close();
    return p;
  }

  /// Polyline from a flat [x0, y0, x1, y1, ...] list.
  void p(List<double> xy, {bool close = false}) =>
      canvas.drawPath(_path(xy, close), stroke);

  /// Filled polygon from a flat list.
  void fp(List<double> xy) => canvas.drawPath(_path(xy, true), fill);

  void path(Path path, {bool filled = false}) =>
      canvas.drawPath(path, filled ? fill : stroke);

  void rect(double l, double t, double r, double b) =>
      canvas.drawRect(Rect.fromLTRB(l, t, r, b), stroke);

  /// Grammar 1: rectangle with the top-right corner clipped.
  void cut(double l, double t, double r, double b, [double? c]) {
    final k = c ?? cutSize;
    p([l, t, r - k, t, r, t + k, r, b, l, b], close: true);
  }

  List<double> _regular(double cx, double cy, double r, int n, double rotDeg) {
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final a = (rotDeg + i * 360 / n) * math.pi / 180;
      out
        ..add(cx + r * math.cos(a))
        ..add(cy + r * math.sin(a));
    }
    return out;
  }

  /// Octagon with flat top/bottom — the faceted replacement for circles.
  void oct(double cx, double cy, double r) =>
      p(_regular(cx, cy, r, 8, 22.5), close: true);

  void hex(double cx, double cy, double r) =>
      p(_regular(cx, cy, r, 6, 0), close: true);

  void circle(double cx, double cy, double r, {bool filled = false}) =>
      canvas.drawCircle(Offset(cx, cy), r, filled ? fill : stroke);

  void dot(double cx, double cy, [double r = 1.2]) =>
      circle(cx, cy, r, filled: true);

  /// Arc in degrees; 0° = +x, positive = clockwise on screen.
  void arc(double cx, double cy, double r, double startDeg, double sweepDeg) =>
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        stroke,
      );

  /// Grammar 4: brand four-point spark.
  void spark(double cx, double cy, double r, {double? ry, double? waist}) {
    final v = ry ?? r;
    final w = waist ?? r * 0.22;
    final s = Path()
      ..moveTo(cx, cy - v)
      ..cubicTo(cx, cy - w, cx + w, cy, cx + r, cy)
      ..cubicTo(cx + w, cy, cx, cy + w, cx, cy + v)
      ..cubicTo(cx, cy + w, cx - w, cy, cx - r, cy)
      ..cubicTo(cx - w, cy, cx, cy - w, cx, cy - v)
      ..close();
    canvas.drawPath(s, fill);
  }

  /// Spark at standard/display, plain dot at compact.
  void node(double cx, double cy, double r) =>
      fine ? spark(cx, cy, r) : dot(cx, cy, math.max(1.15, r * 0.5));

  /// Diamond (selection / status mark).
  void dia(double cx, double cy, double r, {bool filled = false}) {
    final xy = [cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy];
    filled ? fp(xy) : p(xy, close: true);
  }

  void head(double cx, double cy, double r) => circle(cx, cy, r);

  /// Shoulder curve from (cx-w, bottom) over (cx, top) to (cx+w, bottom).
  void bust(double cx, double top, double w, double bottom) {
    final h = bottom - top;
    path(
      Path()
        ..moveTo(cx - w, bottom)
        ..cubicTo(cx - w, top + h * 0.3, cx - w * 0.55, top, cx, top)
        ..cubicTo(cx + w * 0.55, top, cx + w, top + h * 0.3, cx + w, bottom),
    );
  }

  void arrowHead(
    double tx,
    double ty,
    double dx,
    double dy, {
    double len = 4.6,
    double width = 5.6,
  }) {
    final m = math.sqrt(dx * dx + dy * dy);
    final ux = dx / m, uy = dy / m;
    final bx = tx - ux * len, by = ty - uy * len;
    final nx = -uy * width / 2, ny = ux * width / 2;
    fp([tx, ty, bx + nx, by + ny, bx - nx, by - ny]);
  }

  /// Straight arrow: shaft ends where the filled head begins.
  void arrow(
    double x1,
    double y1,
    double x2,
    double y2, {
    double len = 4.6,
    double width = 5.6,
  }) {
    final dx = x2 - x1, dy = y2 - y1;
    final m = math.sqrt(dx * dx + dy * dy);
    l(x1, y1, x2 - dx / m * (len - 0.5), y2 - dy / m * (len - 0.5));
    arrowHead(x2, y2, dx, dy, len: len, width: width);
  }

  /// Arc arrow; head sits at the end of the sweep, pointing along travel.
  void arcArrow(
    double cx,
    double cy,
    double r,
    double startDeg,
    double sweepDeg, {
    double len = 4.6,
    double width = 5.6,
  }) {
    final dir = sweepDeg.sign;
    final headSweep = (len * 0.55 / r) * 180 / math.pi * dir;
    arc(cx, cy, r, startDeg, sweepDeg - headSweep);
    final endA = (startDeg + sweepDeg) * math.pi / 180;
    final baseA = (startDeg + sweepDeg - headSweep * 1.6) * math.pi / 180;
    final tx = cx + r * math.cos(endA), ty = cy + r * math.sin(endA);
    final bx = cx + r * math.cos(baseA), by = cy + r * math.sin(baseA);
    arrowHead(tx, ty, tx - bx, ty - by, len: len, width: width);
  }

  /// Tapered brand trail (logo streak).
  void trail(double bx, double by, double tx, double ty, double w) {
    final dx = tx - bx, dy = ty - by;
    final m = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / m * w / 2, ny = dx / m * w / 2;
    fp([bx + nx, by + ny, bx - nx, by - ny, tx, ty]);
  }

  void rot(double deg, VoidCallback draw, {double cx = 12, double cy = 12}) {
    canvas
      ..save()
      ..translate(cx, cy)
      ..rotate(deg * math.pi / 180)
      ..translate(-cx, -cy);
    draw();
    canvas.restore();
  }

  void brackets({double inset = 3.5, double arm = 4.5}) {
    final f = 24 - inset;
    p([inset + arm, inset, inset, inset, inset, inset + arm]);
    p([f - arm, inset, f, inset, f, inset + arm]);
    p([inset, f - arm, inset, f, inset + arm, f]);
    p([f - arm, f, f, f, f, f - arm]);
  }
}

// ---------------------------------------------------------------------------
// Shared motifs
// ---------------------------------------------------------------------------

void paintIconBell(IconPen g) {
  g.l(12, 2.8, 12, 4.8);
  g.p([
    9.4,
    4.8,
    14.6,
    4.8,
    17,
    8.4,
    17,
    13.6,
    19.6,
    17,
    4.4,
    17,
    7,
    13.6,
    7,
    8.4,
  ], close: true);
  g.l(9.8, 20.4, 14.2, 20.4);
}

void paintIconShield(IconPen g) => g.p([
  12,
  3,
  19.5,
  5.6,
  19.5,
  12.4,
  12,
  21,
  4.5,
  12.4,
  4.5,
  5.6,
], close: true);

void paintIconCalendar(IconPen g) {
  g.cut(3.5, 5.5, 20.5, 20.5);
  g.l(8, 3, 8, 7.5);
  g.l(16, 3, 16, 7.5);
  g.l(3.5, 10.5, 20.5, 10.5);
}

void paintIconPersonAt(IconPen g, double cx) {
  g.head(cx, 7.8, 3.1);
  g.bust(cx, 13.6, 6.3, 20.5);
}

void paintIconMonitor(IconPen g) {
  g.cut(3, 4, 21, 16);
  g.l(12, 16, 12, 20);
  g.l(7.5, 20, 16.5, 20);
}

void paintIconBin(IconPen g) {
  g.l(3.5, 6, 20.5, 6);
  g.p([9, 6, 9, 3.5, 15, 3.5, 15, 6]);
  g.p([5.5, 6, 7, 20.5, 17, 20.5, 18.5, 6]);
}

void paintIconCopyBase(IconPen g) {
  g.p([8.5, 16, 4, 16, 4, 3.5, 13, 3.5, 15.5, 6, 15.5, 8.5]);
  g.cut(8.5, 8.5, 20, 20.5);
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------
