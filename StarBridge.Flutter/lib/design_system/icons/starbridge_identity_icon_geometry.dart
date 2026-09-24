import 'package:flutter/material.dart';

import 'icon_semantic.dart';
import 'starbridge_icon_geometry.dart';

abstract final class StarBridgeIdentityIconGeometry {
  static bool paint(StarBridgeIconSemantic semantic, StarBridgeIconCanvas g) {
    switch (semantic) {
      case StarBridgeIconSemantic.home:
        _paintHome(g);
        return true;
      case StarBridgeIconSemantic.room:
        _paintRoom(g);
        return true;
      case StarBridgeIconSemantic.operation:
        _paintOperation(g);
        return true;
      case StarBridgeIconSemantic.officialFleet:
        _paintOfficialFleet(g);
        return true;
      case StarBridgeIconSemantic.marketplace:
        _paintMarketplace(g);
        return true;
      case StarBridgeIconSemantic.community:
        _paintCommunity(g);
        return true;
      case StarBridgeIconSemantic.hangar:
        _paintHangar(g);
        return true;
      case StarBridgeIconSemantic.overlay:
        _paintOverlay(g);
        return true;
      case StarBridgeIconSemantic.tools:
        _paintTools(g);
        return true;
      case StarBridgeIconSemantic.settings:
        _paintSettings(g);
        return true;
      case StarBridgeIconSemantic.friends:
        _paintFriends(g);
        return true;
      case StarBridgeIconSemantic.notifications:
        _paintNotifications(g);
        return true;
      case StarBridgeIconSemantic.account:
        _paintAccount(g);
        return true;
      case StarBridgeIconSemantic.profile:
        _paintProfile(g);
        return true;
      default:
        return false;
    }
  }

  static void _paintHome(StarBridgeIconCanvas g) {
    g.spark(
      const Offset(12, 12),
      horizontalRadius: g.keepsFineDetail ? 7.4 : 6.7,
      verticalRadius: g.keepsFineDetail ? 7.4 : 6.7,
      waist: g.keepsFineDetail ? 1.55 : 1.75,
    );
  }

  static void _paintRoom(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(4, 20),
      Offset(4, 4),
      Offset(18.5, 4),
      Offset(18.5, 20),
    ]);
    g.polyline(const [
      Offset(8, 20),
      Offset(8, 7.25),
      Offset(16, 5.5),
      Offset(16, 20),
    ]);
    g.dot(const Offset(13.25, 12.75), radius: g.keepsFineDetail ? 1.05 : 1.2);
    g.line(const Offset(3, 20), const Offset(21, 20));
  }

  static void _paintOperation(StarBridgeIconCanvas g) {
    g.line(const Offset(6, 4), const Offset(6, 20));
    if (g.keepsFineDetail) {
      final flag = Path()
        ..moveTo(6, 5)
        ..cubicTo(9.25, 3.9, 12.5, 6.1, 18, 4.8)
        ..lineTo(18, 12.4)
        ..cubicTo(13.25, 13.6, 10, 11.5, 6, 12.7);
      g.path(flag);
    } else {
      g.polyline(const [
        Offset(6, 5),
        Offset(17.5, 5),
        Offset(17.5, 12.5),
        Offset(6, 12.5),
      ]);
    }
  }

  static void _paintOfficialFleet(StarBridgeIconCanvas g) {
    _paintShip(g, const Offset(12, 7), scale: 0.95);
    _paintShip(g, const Offset(6.5, 16), scale: 0.75);
    _paintShip(g, const Offset(17.5, 16), scale: 0.75);
  }

  static void _paintCommunity(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 7), 2);
    g.circle(const Offset(6.25, 9.5), 1.6);
    g.circle(const Offset(17.75, 9.5), 1.6);

    final center = Path()
      ..moveTo(7.25, 19)
      ..cubicTo(7.5, 14.75, 9.25, 12.5, 12, 12.5)
      ..cubicTo(14.75, 12.5, 16.5, 14.75, 16.75, 19);
    g.path(center);

    final left = Path()
      ..moveTo(3.25, 18)
      ..cubicTo(3.5, 14.75, 4.7, 13, 6.5, 13)
      ..cubicTo(7.15, 13, 7.75, 13.2, 8.25, 13.6);
    g.path(left);
    final right = Path()
      ..moveTo(15.75, 13.6)
      ..cubicTo(16.25, 13.2, 16.85, 13, 17.5, 13)
      ..cubicTo(19.3, 13, 20.5, 14.75, 20.75, 18);
    g.path(right);
  }

  static void _paintMarketplace(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(4, 9),
      Offset(6, 4.5),
      Offset(18, 4.5),
      Offset(20, 9),
    ]);
    g.line(const Offset(4, 9), const Offset(20, 9));
    g.rect(const Rect.fromLTRB(5.5, 9, 18.5, 20), radius: 1.25);
    g.line(const Offset(9, 9), const Offset(9, 20));
    if (g.keepsFineDetail) {
      g.line(const Offset(14, 13), const Offset(17, 13));
    }
  }

  static void _paintHangar(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(3.5, 20),
      Offset(5, 8),
      Offset(12, 4),
      Offset(19, 8),
      Offset(20.5, 20),
    ]);
    final bay = Path()
      ..moveTo(7.25, 20)
      ..lineTo(7.25, 13)
      ..cubicTo(7.25, 9.8, 9.2, 8.25, 12, 8.25)
      ..cubicTo(14.8, 8.25, 16.75, 9.8, 16.75, 13)
      ..lineTo(16.75, 20);
    g.path(bay);
    if (g.keepsFineDetail) {
      g.line(const Offset(7.25, 16), const Offset(16.75, 16));
    }
  }

  static void _paintShip(
    StarBridgeIconCanvas g,
    Offset center, {
    required double scale,
    bool filled = true,
  }) {
    final cx = center.dx;
    final cy = center.dy;
    final points = [
      Offset(cx, cy - 4.8 * scale),
      Offset(cx + 1.25 * scale, cy - 0.8 * scale),
      Offset(cx + 4.8 * scale, cy + 2.15 * scale),
      Offset(cx + 1.7 * scale, cy + 1.45 * scale),
      Offset(cx + 1.35 * scale, cy + 4.2 * scale),
      Offset(cx - 1.35 * scale, cy + 4.2 * scale),
      Offset(cx - 1.7 * scale, cy + 1.45 * scale),
      Offset(cx - 4.8 * scale, cy + 2.15 * scale),
      Offset(cx - 1.25 * scale, cy - 0.8 * scale),
    ];
    if (filled) {
      g.polygon(points);
    } else {
      g.polyline(points, close: true);
    }
  }

  static void _paintOverlay(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTRB(4, 4.5, 16, 14.5), radius: 1.5);
    g.rect(const Rect.fromLTRB(8, 9.5, 20, 19.5), radius: 1.5);
    if (g.keepsFineDetail) {
      g.line(const Offset(11, 13), const Offset(17, 13));
    }
  }

  static void _paintSettings(StarBridgeIconCanvas g) {
    _paintSlider(g, y: 7, knobX: 8.5);
    _paintSlider(g, y: 17, knobX: 15.5);
    if (g.keepsFineDetail) {
      _paintSlider(g, y: 12, knobX: 13);
    }
  }

  static void _paintTools(StarBridgeIconCanvas g) {
    g.polyline(const [
      Offset(8, 8),
      Offset(8, 5),
      Offset(16, 5),
      Offset(16, 8),
    ]);
    g.rect(const Rect.fromLTRB(3.5, 8, 20.5, 20), radius: 1.5);
    g.line(const Offset(3.5, 12), const Offset(20.5, 12));
    g.rect(
      Rect.fromCenter(
        center: const Offset(12, 12),
        width: g.keepsFineDetail ? 3.5 : 4,
        height: g.keepsFineDetail ? 2.6 : 3,
      ),
      radius: 0.6,
      filled: true,
    );
    if (g.keepsFineDetail) {
      g.line(const Offset(7, 16), const Offset(17, 16));
    }
  }

  static void _paintSlider(
    StarBridgeIconCanvas g, {
    required double y,
    required double knobX,
  }) {
    const left = 4.5;
    const right = 19.5;
    const gap = 2.25;
    g.line(Offset(left, y), Offset(knobX - gap, y));
    g.line(Offset(knobX + gap, y), Offset(right, y));
    g.circle(Offset(knobX, y), 1.55);
  }

  static void _paintFriends(StarBridgeIconCanvas g) {
    g.circle(const Offset(9, 8), 2);
    g.circle(const Offset(16.25, 9.25), 1.75);

    final primary = Path()
      ..moveTo(4.5, 19)
      ..cubicTo(4.75, 14.8, 6.75, 12.5, 9.25, 12.5)
      ..cubicTo(11.7, 12.5, 13.5, 14.8, 13.75, 19);
    g.path(primary);

    if (g.keepsFineDetail) {
      final companion = Path()
        ..moveTo(13.25, 14.25)
        ..cubicTo(14.1, 13.45, 15.1, 13, 16.25, 13)
        ..cubicTo(18.5, 13, 20, 15.2, 20, 18.5);
      g.path(companion);
    } else {
      g.line(const Offset(14, 18.5), const Offset(19.5, 18.5));
    }
  }

  static void _paintNotifications(StarBridgeIconCanvas g) {
    final bell = Path()
      ..moveTo(6, 17)
      ..cubicTo(7.1, 15.4, 7.4, 13.4, 7.4, 10.5)
      ..cubicTo(7.4, 7.25, 9.15, 5.25, 12, 5.25)
      ..cubicTo(14.85, 5.25, 16.6, 7.25, 16.6, 10.5)
      ..cubicTo(16.6, 13.4, 16.9, 15.4, 18, 17);
    g.path(bell);
    g.line(const Offset(5.5, 17.5), const Offset(18.5, 17.5));
    if (g.keepsFineDetail) {
      final clapper = Path()
        ..moveTo(10, 19.25)
        ..cubicTo(10.6, 20.4, 11.25, 20.75, 12, 20.75)
        ..cubicTo(12.75, 20.75, 13.4, 20.4, 14, 19.25);
      g.path(clapper);
    }
  }

  static void _paintAccount(StarBridgeIconCanvas g) {
    g.circle(const Offset(12, 7.75), 2.75);
    final shoulders = Path()
      ..moveTo(5, 20)
      ..cubicTo(5.2, 15.25, 8, 12.5, 12, 12.5)
      ..cubicTo(16, 12.5, 18.8, 15.25, 19, 20);
    g.path(shoulders);
  }

  static void _paintProfile(StarBridgeIconCanvas g) {
    g.rect(const Rect.fromLTRB(4, 3.5, 20, 20.5), radius: 1.5);
    g.circle(const Offset(9, 9), 2);
    final shoulders = Path()
      ..moveTo(6.25, 14.5)
      ..cubicTo(6.5, 12.7, 7.55, 11.75, 9, 11.75)
      ..cubicTo(10.45, 11.75, 11.5, 12.7, 11.75, 14.5);
    g.path(shoulders);
    g.line(const Offset(14, 8), const Offset(17.5, 8));
    if (g.keepsFineDetail) {
      g.line(const Offset(14, 12), const Offset(17.5, 12));
      g.line(const Offset(14, 16), const Offset(17.5, 16));
    }
  }
}
