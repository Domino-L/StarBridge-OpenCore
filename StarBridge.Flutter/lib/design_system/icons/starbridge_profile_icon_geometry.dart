import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'icon_semantic.dart';
import 'starbridge_icon_geometry.dart';

abstract final class StarBridgeProfileIconGeometry {
  static bool paint(StarBridgeIconSemantic semantic, StarBridgeIconCanvas g) {
    switch (semantic) {
      case StarBridgeIconSemantic.edit:
        _edit(g);
        return true;
      case StarBridgeIconSemantic.add:
        _add(g);
        return true;
      case StarBridgeIconSemantic.dragHandle:
        _dragHandle(g);
        return true;
      case StarBridgeIconSemantic.resize:
        _resize(g);
        return true;
      case StarBridgeIconSemantic.remove:
        _remove(g);
        return true;
      case StarBridgeIconSemantic.schedule:
        _schedule(g);
        return true;
      case StarBridgeIconSemantic.playtime:
        _playtime(g);
        return true;
      case StarBridgeIconSemantic.activity:
        _activity(g);
        return true;
      case StarBridgeIconSemantic.publicProfile:
        _publicProfile(g);
        return true;
      case StarBridgeIconSemantic.generalData:
        _generalData(g);
        return true;
      case StarBridgeIconSemantic.privacy:
        _privacy(g);
        return true;
      case StarBridgeIconSemantic.reminder:
        _reminder(g);
        return true;
      case StarBridgeIconSemantic.diagnostics:
        _diagnostics(g);
        return true;
      case StarBridgeIconSemantic.legalNotice:
        _legalNotice(g);
        return true;
      default:
        return false;
    }
  }

  static void _edit(StarBridgeIconCanvas g) {
    final pencil = Path()
      ..moveTo(4.5, 19)
      ..lineTo(6.1, 13.7)
      ..lineTo(15.6, 4.2)
      ..lineTo(19.8, 8.4)
      ..lineTo(10.3, 17.9)
      ..close();
    g.path(pencil);
    g.line(const Offset(6.1, 13.7), const Offset(10.3, 17.9));
    if (g.keepsFineDetail) {
      g.line(const Offset(14.1, 5.7), const Offset(18.3, 9.9));
    }
  }

  static void _add(StarBridgeIconCanvas g) {
    if (g.keepsFineDetail) {
      g.focusCorners(inset: 4, arm: 4);
    } else {
      g.rect(const Rect.fromLTWH(4.5, 4.5, 15, 15), radius: 1.2);
    }
    g.line(const Offset(12, 8), const Offset(12, 16));
    g.line(const Offset(8, 12), const Offset(16, 12));
  }

  static void _dragHandle(StarBridgeIconCanvas g) {
    if (!g.keepsFineDetail) {
      for (final y in const [8.0, 12.0, 16.0]) {
        g.line(Offset(7.5, y), Offset(16.5, y));
      }
      return;
    }
    for (final x in const [8.5, 15.5]) {
      for (final y in const [7.0, 12.0, 17.0]) {
        g.dot(Offset(x, y), radius: 1.05);
      }
    }
  }

  static void _resize(StarBridgeIconCanvas g) {
    g.line(const Offset(7, 7), const Offset(17, 17));
    g.arrowHead(
      const Offset(4.7, 4.7),
      const Offset(-1, -1),
      length: 3.2,
      width: 3.6,
    );
    g.arrowHead(
      const Offset(19.3, 19.3),
      const Offset(1, 1),
      length: 3.2,
      width: 3.6,
    );
    if (g.keepsFineDetail) {
      g.polyline(const [Offset(4, 10), Offset(4, 4), Offset(10, 4)]);
      g.polyline(const [Offset(14, 20), Offset(20, 20), Offset(20, 14)]);
    }
  }

  static void _remove(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 12), g.keepsFineDetail ? 8.2 : 7.8);
    g.line(const Offset(7.7, 12), const Offset(16.3, 12));
  }

  static void _schedule(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTWH(4, 5.5, 16, 14.5), radius: 1.3);
    g.line(const Offset(4, 10), const Offset(20, 10));
    g.line(const Offset(8, 3.8), const Offset(8, 7.2));
    g.line(const Offset(16, 3.8), const Offset(16, 7.2));
    if (g.keepsFineDetail) {
      for (final x in const [8.0, 12.0, 16.0]) {
        g.dot(Offset(x, 14.3), radius: 0.9);
      }
    }
  }

  static void _playtime(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 13), g.keepsFineDetail ? 7.4 : 7.1);
    g.line(const Offset(10, 3.8), const Offset(14, 3.8));
    g.line(const Offset(12, 3.8), const Offset(12, 5.6));
    g.line(const Offset(12, 13), const Offset(12, 8.7));
    g.line(const Offset(12, 13), const Offset(15.4, 15));
    if (g.keepsFineDetail) {
      g.line(const Offset(17.1, 6.4), const Offset(19, 8.3));
    }
  }

  static void _activity(StarBridgeIconCanvas g) {
    g.polyline(const [Offset(4, 5), Offset(4, 20), Offset(21, 20)]);
    g.polyline(const [
      Offset(6, 17),
      Offset(10, 13),
      Offset(13.5, 15),
      Offset(19.5, 8.5),
    ]);
    if (g.keepsFineDetail) {
      g.line(const Offset(4, 10), const Offset(6, 10));
      g.line(const Offset(12, 18), const Offset(12, 20));
    }
  }

  static void _publicProfile(StarBridgeIconCanvas g) {
    g.circle(const Offset(7.7, 8.2), 2.35);
    g.arc(const Rect.fromLTWH(3.5, 11.7, 8.4, 7.2), math.pi, math.pi);
    const signalCenter = Offset(10.1, 11.1);
    g.arc(
      Rect.fromCircle(center: signalCenter, radius: 5.1),
      -0.34 * math.pi,
      0.68 * math.pi,
    );
    if (g.keepsFineDetail) {
      g.arc(
        Rect.fromCircle(center: signalCenter, radius: 8.3),
        -0.34 * math.pi,
        0.68 * math.pi,
      );
    }
  }

  static void _generalData(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(5, 3.5),
      Offset(16, 3.5),
      Offset(20, 7.5),
      Offset(20, 20.5),
      Offset(5, 20.5),
      Offset(5, 3.5),
    ]);
    g.polyline(const [Offset(16, 3.5), Offset(16, 7.5), Offset(20, 7.5)]);
    for (final y
        in g.keepsFineDetail ? const [9.0, 13.5, 18.0] : const [10.0, 16.0]) {
      g.dot(Offset(8, y), radius: 0.9);
      g.line(Offset(11, y), Offset(17, y));
    }
  }

  static void _privacy(StarBridgeIconCanvas g) {
    final shield = Path()
      ..moveTo(12, 3.5)
      ..lineTo(20, 6.5)
      ..lineTo(19, 13.3)
      ..quadraticBezierTo(18.2, 18.1, 12, 21)
      ..quadraticBezierTo(5.8, 18.1, 5, 13.3)
      ..lineTo(4, 6.5)
      ..close();
    g.path(shield);
    if (g.keepsFineDetail) {
      g.circle(const Offset(12, 11), 1.65);
      g.line(const Offset(12, 12.65), const Offset(12, 16));
    } else {
      g.dot(const Offset(12, 11.5), radius: 1.3);
      g.line(const Offset(12, 12.8), const Offset(12, 15.5));
    }
  }

  static void _reminder(StarBridgeIconCanvas g) {
    final bell = Path()
      ..moveTo(5, 17)
      ..quadraticBezierTo(7, 15.2, 7, 11)
      ..quadraticBezierTo(7, 6.2, 12, 5.5)
      ..quadraticBezierTo(17, 6.2, 17, 11)
      ..quadraticBezierTo(17, 15.2, 19, 17)
      ..lineTo(5, 17);
    g.path(bell);
    if (g.keepsFineDetail) {
      g.arc(const Rect.fromLTWH(9.2, 16.2, 5.6, 3.5), 0, math.pi);
    } else {
      g.line(const Offset(10, 19), const Offset(14, 19));
    }
    g.dot(const Offset(19.4, 4.5), radius: 1.2);
  }

  static void _diagnostics(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTWH(3.5, 4.5, 17, 13), radius: 1.3);
    g.polyline(const [
      Offset(6, 11),
      Offset(9, 11),
      Offset(10.5, 8),
      Offset(13, 14.5),
      Offset(15.2, 10.5),
      Offset(18, 10.5),
    ]);
    g.line(const Offset(12, 17.5), const Offset(12, 20));
    if (g.keepsFineDetail) {
      g.line(const Offset(8, 20), const Offset(16, 20));
    } else {
      g.line(const Offset(9.5, 20), const Offset(14.5, 20));
    }
  }

  static void _legalNotice(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 4.5), 1.4);
    g.line(const Offset(12, 5.9), const Offset(12, 19.5));
    g.line(const Offset(5, 8), const Offset(19, 8));

    g.polyline(const [
      Offset(7, 8),
      Offset(4.5, 14.5),
      Offset(9.5, 14.5),
      Offset(7, 8),
    ]);
    g.polyline(const [
      Offset(17, 8),
      Offset(14.5, 14.5),
      Offset(19.5, 14.5),
      Offset(17, 8),
    ]);
    g.line(const Offset(8, 20), const Offset(16, 20));
  }
}
