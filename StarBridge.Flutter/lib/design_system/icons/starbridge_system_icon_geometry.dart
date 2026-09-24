import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'icon_semantic.dart';
import 'starbridge_icon_geometry.dart';

abstract final class StarBridgeSystemIconGeometry {
  static bool paint(StarBridgeIconSemantic semantic, StarBridgeIconCanvas g) {
    switch (semantic) {
      case StarBridgeIconSemantic.login:
        _login(g);
        return true;
      case StarBridgeIconSemantic.logout:
        _logout(g);
        return true;
      case StarBridgeIconSemantic.refresh:
        _refresh(g);
        return true;
      case StarBridgeIconSemantic.undo:
        _historyArrow(g, pointsLeft: true);
        return true;
      case StarBridgeIconSemantic.redo:
        _historyArrow(g, pointsLeft: false);
        return true;
      case StarBridgeIconSemantic.save:
        _save(g);
        return true;
      case StarBridgeIconSemantic.cache:
        _cache(g);
        return true;
      case StarBridgeIconSemantic.scene:
        _scene(g);
        return true;
      case StarBridgeIconSemantic.statusHost:
        _statusHost(g);
        return true;
      case StarBridgeIconSemantic.statusGame:
        _statusGame(g);
        return true;
      case StarBridgeIconSemantic.statusIdentity:
        _statusIdentity(g);
        return true;
      case StarBridgeIconSemantic.statusNetwork:
        _statusNetwork(g);
        return true;
      case StarBridgeIconSemantic.connected:
        _connected(g);
        return true;
      case StarBridgeIconSemantic.disconnected:
        _disconnected(g);
        return true;
      case StarBridgeIconSemantic.warning:
        _warning(g);
        return true;
      case StarBridgeIconSemantic.forward:
        _forward(g);
        return true;
      case StarBridgeIconSemantic.windowMinimize:
        _windowMinimize(g);
        return true;
      case StarBridgeIconSemantic.windowMaximize:
        _windowMaximize(g);
        return true;
      case StarBridgeIconSemantic.windowRestore:
        _windowRestore(g);
        return true;
      case StarBridgeIconSemantic.windowClose:
        _windowClose(g);
        return true;
      case StarBridgeIconSemantic.pending:
        _pending(g);
        return true;
      case StarBridgeIconSemantic.menuDown:
        _menuDown(g);
        return true;
      default:
        return false;
    }
  }

  static void _login(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(15, 4),
      Offset(20, 4),
      Offset(20, 20),
      Offset(15, 20),
    ]);
    g.line(const Offset(4, 12), const Offset(15.5, 12));
    g.arrowHead(
      const Offset(16.5, 12),
      const Offset(1, 0),
      length: 3.8,
      width: 4.5,
    );
  }

  static void _logout(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(9, 4),
      Offset(4, 4),
      Offset(4, 20),
      Offset(9, 20),
    ]);
    g.line(const Offset(8.5, 12), const Offset(20, 12));
    g.arrowHead(
      const Offset(20.5, 12),
      const Offset(1, 0),
      length: 3.8,
      width: 4.5,
    );
  }

  static void _refresh(StarBridgeIconCanvas g) {
    final bounds = Rect.fromCircle(center: const Offset(12, 12), radius: 7.7);
    g.arc(bounds, -0.15 * math.pi, 1.03 * math.pi);
    g.arc(bounds, 0.85 * math.pi, 1.03 * math.pi);
    g.arrowHead(
      const Offset(5.05, 8.55),
      const Offset(-0.5, -0.85),
      length: 3,
      width: 3.4,
    );
    g.arrowHead(
      const Offset(18.95, 15.45),
      const Offset(0.5, 0.85),
      length: 3,
      width: 3.4,
    );
  }

  static void _historyArrow(
    StarBridgeIconCanvas g, {
    required bool pointsLeft,
  }) {
    final direction = pointsLeft ? -1.0 : 1.0;
    final tip = Offset(pointsLeft ? 4 : 20, 9);
    final centerX = pointsLeft ? 13.5 : 10.5;
    final path = Path()
      ..moveTo(tip.dx + direction * -0.5, tip.dy)
      ..cubicTo(
        centerX,
        5,
        centerX + direction * 6,
        7,
        centerX + direction * 6,
        13,
      )
      ..cubicTo(
        centerX + direction * 6,
        17,
        centerX + direction * 3,
        19,
        centerX,
        19,
      );
    g.path(path);
    g.arrowHead(tip, Offset(direction, 0), length: 3.5, width: 4);
  }

  static void _save(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(4, 4),
      Offset(17, 4),
      Offset(20, 7),
      Offset(20, 20),
      Offset(4, 20),
      Offset(4, 4),
    ]);
    g.rect(const Rect.fromLTWH(8, 4, 7, 5));
    g.rect(const Rect.fromLTWH(7, 13, 10, 7), radius: 0.8);
    if (g.keepsFineDetail) {
      g.line(const Offset(10, 16), const Offset(14, 16));
    }
  }

  static void _cache(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(4, 8),
      Offset(12, 4),
      Offset(20, 8),
      Offset(12, 12),
      Offset(4, 8),
    ]);
    g.polyline(const [Offset(4, 12), Offset(12, 16), Offset(20, 12)]);
    g.polyline(const [Offset(4, 16), Offset(12, 20), Offset(20, 16)]);
    if (g.keepsFineDetail) {
      g.line(const Offset(4, 8), const Offset(4, 16));
      g.line(const Offset(20, 8), const Offset(20, 16));
    }
  }

  static void _scene(StarBridgeIconCanvas g) {
    g.focusCorners(inset: g.opticalSize.detailInset, arm: 4.5);
    g.spark(
      const Offset(12, 12),
      horizontalRadius: g.keepsFineDetail ? 3.6 : 3.2,
      verticalRadius: g.keepsFineDetail ? 3.6 : 3.2,
      waist: 0.75,
    );
  }

  static void _statusHost(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTWH(6, 6, 12, 12), radius: 1.2);
    for (final x in const [4.0, 20.0]) {
      g.line(Offset(x, 8), Offset(x == 4 ? 6 : 18, 8));
      g.line(Offset(x, 12), Offset(x == 4 ? 6 : 18, 12));
      g.line(Offset(x, 16), Offset(x == 4 ? 6 : 18, 16));
    }
    if (g.keepsFineDetail) {
      g.polyline(const [
        Offset(9, 14.5),
        Offset(9, 9.5),
        Offset(12, 12),
        Offset(15, 9.5),
        Offset(15, 14.5),
      ]);
    } else {
      g.dot(const Offset(12, 12), radius: 1.5);
    }
  }

  static void _statusGame(StarBridgeIconCanvas g) {
    final body = Path()
      ..moveTo(7.2, 8)
      ..quadraticBezierTo(4.8, 8, 4, 11)
      ..lineTo(2.8, 16)
      ..quadraticBezierTo(2.1, 19.2, 5.2, 19.5)
      ..quadraticBezierTo(7.4, 19.5, 9, 16.5)
      ..lineTo(15, 16.5)
      ..quadraticBezierTo(16.6, 19.5, 18.8, 19.5)
      ..quadraticBezierTo(21.9, 19.2, 21.2, 16)
      ..lineTo(20, 11)
      ..quadraticBezierTo(19.2, 8, 16.8, 8)
      ..close();
    g.path(body);
    g.line(const Offset(6, 12.5), const Offset(10, 12.5));
    g.line(const Offset(8, 10.5), const Offset(8, 14.5));
    g.dot(const Offset(16, 11.2), radius: 1);
    g.dot(const Offset(18.2, 13.5), radius: 1);
  }

  static void _statusIdentity(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTWH(4, 5, 16, 14), radius: 1.2);
    g.circle(const Offset(9, 10), 2.1);
    g.arc(const Rect.fromLTWH(6.2, 12.2, 5.6, 4.2), math.pi, math.pi);
    g.line(const Offset(14, 9), const Offset(18, 9));
    g.line(const Offset(14, 13), const Offset(18, 13));
    if (g.keepsFineDetail) {
      g.line(const Offset(14, 16), const Offset(17, 16));
    }
  }

  static void _statusNetwork(StarBridgeIconCanvas g) {
    g.line(const Offset(12, 7), const Offset(12, 12));
    g.polyline(const [
      Offset(5.5, 14),
      Offset(5.5, 12),
      Offset(18.5, 12),
      Offset(18.5, 14),
    ]);
    g.circle(const Offset(12, 5), 2.2);
    g.circle(const Offset(5.5, 17), 2.2);
    g.circle(const Offset(18.5, 17), 2.2);
  }

  static void _connected(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 12), 8.2);
    g.check(origin: const Offset(7, 12));
  }

  static void _disconnected(StarBridgeIconCanvas g) {
    final bounds = Rect.fromCircle(center: const Offset(12, 12), radius: 8.2);
    g.arc(bounds, -0.38 * math.pi, 0.72 * math.pi);
    g.arc(bounds, 0.62 * math.pi, 0.72 * math.pi);
    g.line(const Offset(7.5, 12), const Offset(16.5, 12));
  }

  static void _warning(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(12, 3.5),
      Offset(21, 20),
      Offset(3, 20),
      Offset(12, 3.5),
    ]);
    g.line(const Offset(12, 9), const Offset(12, 14));
    g.dot(const Offset(12, 17.2), radius: 1.05);
  }

  static void _forward(StarBridgeIconCanvas g) {
    g.polyline(const [Offset(8, 5), Offset(15, 12), Offset(8, 19)]);
  }

  static void _windowMinimize(StarBridgeIconCanvas g) {
    g.line(const Offset(5, 16), const Offset(19, 16));
  }

  static void _windowMaximize(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTWH(5, 5, 14, 14));
  }

  static void _windowRestore(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(8, 7),
      Offset(8, 4),
      Offset(20, 4),
      Offset(20, 16),
      Offset(17, 16),
    ]);
    g.rect(const Rect.fromLTWH(4, 8, 13, 12));
  }

  static void _windowClose(StarBridgeIconCanvas g) {
    g.line(const Offset(6, 6), const Offset(18, 18));
    g.line(const Offset(18, 6), const Offset(6, 18));
  }

  static void _pending(StarBridgeIconCanvas g) {
    final bounds = Rect.fromCircle(center: const Offset(12, 12), radius: 7.8);
    g.arc(bounds, -0.1 * math.pi, 0.82 * math.pi);
    g.arc(bounds, 0.9 * math.pi, 0.82 * math.pi);
    g.arrowHead(
      const Offset(6.3, 6.7),
      const Offset(-0.75, 0.55),
      length: 2.8,
      width: 3.2,
    );
    g.arrowHead(
      const Offset(17.7, 17.3),
      const Offset(0.75, -0.55),
      length: 2.8,
      width: 3.2,
    );
  }

  static void _menuDown(StarBridgeIconCanvas g) {
    g.polyline(const [Offset(6, 9), Offset(12, 15), Offset(18, 9)]);
  }
}
