import 'dart:math' as math;

import 'package:flutter/material.dart';

enum StarBridgeIconOpticalSize { compact, standard, display }

StarBridgeIconOpticalSize starBridgeIconOpticalSizeFor(double size) {
  if (size <= 17) {
    return StarBridgeIconOpticalSize.compact;
  }
  if (size <= 21) {
    return StarBridgeIconOpticalSize.standard;
  }
  return StarBridgeIconOpticalSize.display;
}

extension StarBridgeIconOptics on StarBridgeIconOpticalSize {
  double get strokeWidth => switch (this) {
    StarBridgeIconOpticalSize.compact => 2.25,
    StarBridgeIconOpticalSize.standard => 2.10,
    StarBridgeIconOpticalSize.display => 2.00,
  };

  double get detailInset => switch (this) {
    StarBridgeIconOpticalSize.compact => 2.75,
    StarBridgeIconOpticalSize.standard => 2.25,
    StarBridgeIconOpticalSize.display => 2.00,
  };

  bool get keepsFineDetail => this != StarBridgeIconOpticalSize.compact;
}

final class StarBridgeIconCanvas {
  StarBridgeIconCanvas(this.canvas, Color color, this.opticalSize)
    : outline = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = opticalSize.strokeWidth
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round,
      fill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

  final Canvas canvas;
  final StarBridgeIconOpticalSize opticalSize;
  final Paint outline;
  final Paint fill;

  bool get keepsFineDetail => opticalSize.keepsFineDetail;

  void line(Offset start, Offset end) {
    canvas.drawLine(start, end, outline);
  }

  void polyline(List<Offset> points, {bool close = false}) {
    assert(points.length >= 2);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) {
      path.close();
    }
    canvas.drawPath(path, outline);
  }

  void polygon(List<Offset> points) {
    assert(points.length >= 3);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
  }

  void path(Path path, {bool filled = false}) {
    canvas.drawPath(path, filled ? fill : outline);
  }

  void circle(Offset center, double radius, {bool filled = false}) {
    canvas.drawCircle(center, radius, filled ? fill : outline);
  }

  void oval(Rect bounds, {bool filled = false}) {
    canvas.drawOval(bounds, filled ? fill : outline);
  }

  void rect(Rect bounds, {double radius = 0, bool filled = false}) {
    final paint = filled ? fill : outline;
    if (radius == 0) {
      canvas.drawRect(bounds, paint);
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(radius)),
      paint,
    );
  }

  void arc(Rect bounds, double startAngle, double sweepAngle) {
    canvas.drawArc(bounds, startAngle, sweepAngle, false, outline);
  }

  void dot(Offset center, {double radius = 1.15}) {
    circle(center, radius, filled: true);
  }

  void spark(
    Offset center, {
    double horizontalRadius = 3.8,
    double verticalRadius = 3.8,
    double waist = 0.85,
  }) {
    final cx = center.dx;
    final cy = center.dy;
    final path = Path()
      ..moveTo(cx, cy - verticalRadius)
      ..cubicTo(cx, cy - waist, cx + waist, cy, cx + horizontalRadius, cy)
      ..cubicTo(cx + waist, cy, cx, cy + waist, cx, cy + verticalRadius)
      ..cubicTo(cx, cy + waist, cx - waist, cy, cx - horizontalRadius, cy)
      ..cubicTo(cx - waist, cy, cx, cy - waist, cx, cy - verticalRadius)
      ..close();
    canvas.drawPath(path, fill);
  }

  void trail(Offset base, Offset tip, {double width = 1.8}) {
    final delta = tip - base;
    final length = delta.distance;
    if (length == 0) {
      return;
    }
    final normal = Offset(-delta.dy / length, delta.dx / length) * (width / 2);
    polygon([base + normal, base - normal, tip]);
  }

  void arrowHead(
    Offset tip,
    Offset direction, {
    double length = 3.5,
    double width = 3.5,
  }) {
    final magnitude = direction.distance;
    if (magnitude == 0) {
      return;
    }
    final unit = direction / magnitude;
    final normal = Offset(-unit.dy, unit.dx) * (width / 2);
    final base = tip - unit * length;
    polygon([tip, base + normal, base - normal]);
  }

  void check({Offset origin = const Offset(6, 12)}) {
    polyline([
      origin,
      origin + const Offset(3.6, 3.6),
      origin + const Offset(11.5, -4.5),
    ]);
  }

  void focusCorners({double inset = 3.5, double arm = 4.5}) {
    final far = 24 - inset;
    polyline([
      Offset(inset + arm, inset),
      Offset(inset, inset),
      Offset(inset, inset + arm),
    ]);
    polyline([
      Offset(far - arm, inset),
      Offset(far, inset),
      Offset(far, inset + arm),
    ]);
    polyline([
      Offset(inset, far - arm),
      Offset(inset, far),
      Offset(inset + arm, far),
    ]);
    polyline([
      Offset(far - arm, far),
      Offset(far, far),
      Offset(far, far - arm),
    ]);
  }

  void rotateAround(Offset center, double radians, VoidCallback draw) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  static const courseAngle = -26 * math.pi / 180;
}
