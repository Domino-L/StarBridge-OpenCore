import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';

const menuHudGuide = BridgeInk.amber;

/// Screen-edge frame and corner brackets: "the overlay is editable now".
class MenuHudPlacementFrame extends CustomPainter {
  const MenuHudPlacementFrame();
  @override
  void paint(Canvas canvas, Size size) {
    final edge = Paint()
      ..color = BridgeInk.blue.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect((Offset.zero & size).deflate(1), edge);
    final corner = Paint()
      ..color = BridgeInk.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    const inset = 8.0, arm = 44.0;
    for (final (x, y, dx, dy) in [
      (inset, inset, 1.0, 1.0),
      (size.width - inset, inset, -1.0, 1.0),
      (inset, size.height - inset, 1.0, -1.0),
      (size.width - inset, size.height - inset, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + arm * dy)
          ..lineTo(x, y)
          ..lineTo(x + arm * dx, y),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(MenuHudPlacementFrame oldDelegate) => false;
}

/// Faint 16 px grid with a stronger line every 64 px.
class MenuHudPlacementGrid extends CustomPainter {
  const MenuHudPlacementGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final fine = Paint()..color = BridgeInk.blue.withValues(alpha: .045);
    final major = Paint()..color = BridgeInk.blue.withValues(alpha: .10);
    for (var x = 0.0; x <= size.width; x += 16) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        x % 64 == 0 ? major : fine,
      );
    }
    for (var y = 0.0; y <= size.height; y += 16) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        y % 64 == 0 ? major : fine,
      );
    }
  }

  @override
  bool shouldRepaint(MenuHudPlacementGrid oldDelegate) => false;
}

/// Module outline: dashed when idle, solid when selected, amber while dragged.
class MenuHudModuleOutline extends CustomPainter {
  const MenuHudModuleOutline({
    required this.selected,
    required this.dragging,
    required this.hovered,
  });
  final bool selected, dragging, hovered;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2 : 1.5
      ..color = dragging
          ? menuHudGuide
          : selected
          ? BridgeInk.blue
          : hovered
          ? BridgeInk.placementHover
          : BridgeInk.blue.withValues(alpha: .8);
    if (selected || dragging) {
      canvas.drawRect(rect, paint);
      return;
    }
    const dash = 6.0, gap = 4.0;
    final path = Path()..addRect(rect);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MenuHudModuleOutline old) =>
      old.selected != selected ||
      old.dragging != dragging ||
      old.hovered != hovered;
}

/// Lower-right resize triangle (drawn inside a larger square hit area).
class MenuHudGrip extends CustomPainter {
  const MenuHudGrip();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 3, 3)
        ..lineTo(size.width - 3, size.height - 3)
        ..lineTo(3, size.height - 3)
        ..close(),
      Paint()..color = BridgeInk.blue,
    );
  }

  @override
  bool shouldRepaint(MenuHudGrip oldDelegate) => false;
}

/// Full-length amber alignment lines and the dock line for the notice.
class MenuHudGuides extends CustomPainter {
  const MenuHudGuides(this.vertical, this.horizontal);
  final List<double> vertical, horizontal;
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = menuHudGuide.withValues(alpha: .35)
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final line = Paint()
      ..color = menuHudGuide
      ..strokeWidth = 1;
    for (final x in vertical) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), glow);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (final y in horizontal) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glow);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(MenuHudGuides old) =>
      old.vertical.length != vertical.length ||
      old.horizontal.length != horizontal.length ||
      !_same(old.vertical, vertical) ||
      !_same(old.horizontal, horizontal);
  static bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Edges of [rect] that line up (within half a pixel) with the screen edges,
/// centre lines or another module. Matches what the shared snapping produced.
({List<double> vertical, List<double> horizontal}) menuHudAlignment(
  Rect rect,
  Iterable<Rect> others,
  Size surface,
) {
  final xs = <double>{0, surface.width / 2, surface.width};
  final ys = <double>{0, surface.height / 2, surface.height};
  for (final other in others) {
    xs.addAll([other.left, other.right]);
    ys.addAll([other.top, other.bottom]);
  }
  bool near(double a, double b) => (a - b).abs() < .5;
  final vertical = <double>{
    for (final x in xs)
      if (near(rect.left, x) ||
          near(rect.right, x) ||
          (x == surface.width / 2 && near(rect.center.dx, x)))
        x,
  };
  final horizontal = <double>{
    for (final y in ys)
      if (near(rect.top, y) ||
          near(rect.bottom, y) ||
          (y == surface.height / 2 && near(rect.center.dy, y)))
        y,
  };
  return (
    vertical: vertical.toList()..sort(),
    horizontal: horizontal.toList()..sort(),
  );
}
