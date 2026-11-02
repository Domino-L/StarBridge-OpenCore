import 'package:flutter/material.dart';

import 'marketplace_category_roots.dart';

/// Approved single-colour trading-category artwork, in a 64-unit view box.
/// Source: work/trading_category_art_20261018/svg-v8 (2026-10-18).
/// The weapon is adapted from "Pistol gun" by John Colburn / Game-icons.net,
/// CC BY 3.0: https://game-icons.net/1x1/john-colburn/pistol-gun.html
/// Changes: simplified details and geometry, monochrome native Flutter paths.
/// See assets/legal/TRADING-CATEGORY-ICONS.txt for attribution.
class MarketSilhouette extends StatelessWidget {
  const MarketSilhouette(this.category, {required this.color, super.key});
  final int category;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _Silhouette(marketRootCategory(category), color));
}

class _Silhouette extends CustomPainter {
  _Silhouette(this.category, this.color);
  final int category;
  final Color color;

  // Generated from the selected SVG geometry; no runtime SVG dependency,
  // embedded bitmap, category tint, gradients, or game reference photographs.
  static final Map<int, List<Path>> _icons = <int, List<Path>>{
    1: <Path>[
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(32, 6)
        ..lineTo(38, 22)
        ..lineTo(38, 46)
        ..lineTo(32, 52)
        ..lineTo(26, 46)
        ..lineTo(26, 22)
        ..close()
        ..moveTo(30, 22)
        ..lineTo(30, 32)
        ..lineTo(34, 32)
        ..lineTo(34, 22)
        ..close(),
      Path()
        ..moveTo(22, 24)
        ..lineTo(10, 36)
        ..lineTo(6, 50)
        ..lineTo(22, 44)
        ..close(),
      Path()
        ..moveTo(42, 24)
        ..lineTo(54, 36)
        ..lineTo(58, 50)
        ..lineTo(42, 44)
        ..close(),
      Path()
        ..moveTo(28, 56)
        ..lineTo(36, 56)
        ..lineTo(36, 60)
        ..lineTo(28, 60)
        ..close(),
    ],
    2: <Path>[
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(24.4, 10.15)
        ..lineTo(39.6, 10.15)
        ..lineTo(45.3, 17.75)
        ..lineTo(45.3, 48.15)
        ..lineTo(39.6, 53.85)
        ..lineTo(24.4, 53.85)
        ..lineTo(18.7, 48.15)
        ..lineTo(18.7, 17.75)
        ..close()
        ..moveTo(26.3, 17.75)
        ..lineTo(37.7, 17.75)
        ..lineTo(39.6, 21.55)
        ..lineTo(39.6, 29.15)
        ..lineTo(24.4, 29.15)
        ..lineTo(24.4, 21.55)
        ..close()
        ..moveTo(26.3, 36.75)
        ..lineTo(37.7, 36.75)
        ..lineTo(37.7, 46.25)
        ..lineTo(26.3, 46.25)
        ..close(),
      Path()
        ..moveTo(9.2, 17.75)
        ..lineTo(13, 17.75)
        ..lineTo(14.9, 19.65)
        ..lineTo(14.9, 29.15)
        ..lineTo(13, 31.05)
        ..lineTo(9.2, 31.05)
        ..lineTo(7.3, 29.15)
        ..lineTo(7.3, 19.65)
        ..close(),
      Path()
        ..moveTo(51, 17.75)
        ..lineTo(54.8, 17.75)
        ..lineTo(56.7, 19.65)
        ..lineTo(56.7, 29.15)
        ..lineTo(54.8, 31.05)
        ..lineTo(51, 31.05)
        ..lineTo(49.1, 29.15)
        ..lineTo(49.1, 19.65)
        ..close(),
      Path()
        ..moveTo(9.2, 38.65)
        ..lineTo(13, 38.65)
        ..lineTo(14.9, 40.55)
        ..lineTo(14.9, 51.95)
        ..lineTo(13, 53.85)
        ..lineTo(9.2, 53.85)
        ..lineTo(7.3, 51.95)
        ..lineTo(7.3, 40.55)
        ..close(),
      Path()
        ..moveTo(51, 38.65)
        ..lineTo(54.8, 38.65)
        ..lineTo(56.7, 40.55)
        ..lineTo(56.7, 51.95)
        ..lineTo(54.8, 53.85)
        ..lineTo(51, 53.85)
        ..lineTo(49.1, 51.95)
        ..lineTo(49.1, 40.55)
        ..close(),
      Path()
        ..moveTo(29.15, 39.6)
        ..lineTo(34.85, 39.6)
        ..lineTo(34.85, 43.4)
        ..lineTo(29.15, 43.4)
        ..close(),
    ],
    3: <Path>[
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(9.875, 14.5)
        ..lineTo(6.375, 23)
        ..lineTo(57.125, 23)
        ..lineTo(57.125, 14.5)
        ..close()
        ..moveTo(7.125, 24.875)
        ..lineTo(9.625, 28.875)
        ..lineTo(3.625, 50.875)
        ..lineTo(16.375, 51.75)
        ..lineTo(19, 39.5)
        ..lineTo(33.5, 39.5)
        ..lineTo(35.375, 29.5)
        ..lineTo(57.125, 29)
        ..lineTo(57.125, 24.875)
        ..close()
        ..moveTo(33, 29.5)
        ..lineTo(31.5, 37.125)
        ..lineTo(19.625, 37.125)
        ..lineTo(21.25, 29.75)
        ..close(),
    ],
    4: <Path>[
      Path()
        ..moveTo(9, 12)
        ..lineTo(16, 12)
        ..lineTo(16, 52)
        ..lineTo(9, 52)
        ..lineTo(4, 47)
        ..lineTo(4, 17)
        ..close()
        ..moveTo(48, 12)
        ..lineTo(55, 12)
        ..lineTo(60, 17)
        ..lineTo(60, 47)
        ..lineTo(55, 52)
        ..lineTo(48, 52)
        ..close()
        ..moveTo(20, 16)
        ..lineTo(44, 16)
        ..lineTo(44, 22)
        ..lineTo(20, 22)
        ..close()
        ..moveTo(20, 42)
        ..lineTo(44, 42)
        ..lineTo(44, 48)
        ..lineTo(20, 48)
        ..close(),
      Path()
        ..moveTo(20, 26)
        ..lineTo(27, 26)
        ..lineTo(27, 38)
        ..lineTo(20, 38)
        ..close()
        ..moveTo(37, 26)
        ..lineTo(44, 26)
        ..lineTo(44, 38)
        ..lineTo(37, 38)
        ..close()
        ..moveTo(31, 25)
        ..lineTo(33, 25)
        ..lineTo(35, 28)
        ..lineTo(35, 36)
        ..lineTo(33, 39)
        ..lineTo(31, 39)
        ..lineTo(29, 36)
        ..lineTo(29, 28)
        ..close(),
    ],
    5: <Path>[
      Path()
        ..moveTo(22, 5)
        ..lineTo(27, 5)
        ..lineTo(27, 13)
        ..lineTo(37, 13)
        ..lineTo(37, 5)
        ..lineTo(42, 5)
        ..lineTo(45, 14)
        ..lineTo(39, 18)
        ..lineTo(25, 18)
        ..lineTo(19, 14)
        ..close()
        ..moveTo(9, 12)
        ..lineTo(18, 16)
        ..lineTo(15, 29)
        ..lineTo(9, 33)
        ..lineTo(3, 23)
        ..lineTo(4, 16)
        ..close()
        ..moveTo(55, 12)
        ..lineTo(46, 16)
        ..lineTo(49, 29)
        ..lineTo(55, 33)
        ..lineTo(61, 23)
        ..lineTo(60, 16)
        ..close(),
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(22, 22)
        ..lineTo(42, 22)
        ..lineTo(48, 29)
        ..lineTo(43, 43)
        ..lineTo(21, 43)
        ..lineTo(16, 29)
        ..close()
        ..moveTo(23, 30)
        ..lineTo(23, 34)
        ..lineTo(32, 39)
        ..lineTo(41, 34)
        ..lineTo(41, 30)
        ..lineTo(32, 35)
        ..close(),
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(23, 47)
        ..lineTo(41, 47)
        ..lineTo(39, 57)
        ..lineTo(35, 61)
        ..lineTo(29, 61)
        ..lineTo(25, 57)
        ..close()
        ..moveTo(26, 51)
        ..lineTo(26, 54)
        ..lineTo(38, 54)
        ..lineTo(38, 51)
        ..close(),
    ],
    6: <Path>[
      Path()
        ..moveTo(18, 18)
        ..lineTo(18, 15)
        ..cubicTo(18, 9, 24, 5, 32, 5)
        ..cubicTo(40, 5, 46, 9, 46, 15)
        ..lineTo(46, 18)
        ..lineTo(42, 18)
        ..lineTo(42, 15)
        ..cubicTo(42, 11, 38, 9, 32, 9)
        ..cubicTo(26, 9, 22, 11, 22, 15)
        ..lineTo(22, 18)
        ..close()
        ..moveTo(12, 22)
        ..lineTo(16, 19)
        ..lineTo(48, 19)
        ..lineTo(52, 22)
        ..lineTo(52, 25)
        ..lineTo(12, 25)
        ..close(),
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(15, 29)
        ..lineTo(49, 29)
        ..lineTo(49, 52)
        ..lineTo(45, 57)
        ..lineTo(19, 57)
        ..lineTo(15, 52)
        ..close()
        ..moveTo(22, 29)
        ..lineTo(22, 36)
        ..arcToPoint(
          Offset(27, 36),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(27, 29)
        ..close()
        ..moveTo(31, 29)
        ..lineTo(31, 42)
        ..arcToPoint(
          Offset(36, 42),
          radius: Radius.elliptical(2.5, 2.5),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(36, 29)
        ..close()
        ..moveTo(40, 29)
        ..lineTo(40, 34)
        ..arcToPoint(
          Offset(44, 34),
          radius: Radius.elliptical(2, 2),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..lineTo(44, 29)
        ..close(),
    ],
    7: <Path>[
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(39, 4)
        ..lineTo(30, 14)
        ..lineTo(30, 24)
        ..lineTo(8, 46)
        ..lineTo(8, 54)
        ..lineTo(14, 60)
        ..lineTo(22, 60)
        ..lineTo(44, 38)
        ..lineTo(54, 38)
        ..lineTo(63, 28)
        ..lineTo(63, 16)
        ..lineTo(52, 27)
        ..lineTo(42, 22)
        ..lineTo(38, 12)
        ..lineTo(48, 4)
        ..close()
        ..moveTo(15, 48)
        ..arcToPoint(
          Offset(15, 54),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: true,
          clockwise: false,
        )
        ..arcToPoint(
          Offset(15, 48),
          radius: Radius.elliptical(3, 3),
          rotation: 0,
          largeArc: false,
          clockwise: false,
        )
        ..close(),
    ],
    8: <Path>[
      Path()
        ..moveTo(30, 5)
        ..lineTo(40, 16)
        ..lineTo(30, 31)
        ..lineTo(19, 21)
        ..close()
        ..moveTo(17, 25)
        ..lineTo(27, 35)
        ..lineTo(23, 57)
        ..lineTo(11, 37)
        ..close()
        ..moveTo(44, 20)
        ..lineTo(54, 30)
        ..lineTo(52, 47)
        ..lineTo(29, 59)
        ..lineTo(34, 36)
        ..close(),
    ],
    9: <Path>[
      Path()
        ..moveTo(32, 4)
        ..lineTo(38, 13)
        ..lineTo(34, 30)
        ..lineTo(30, 30)
        ..lineTo(26, 13)
        ..close()
        ..moveTo(11, 13)
        ..lineTo(22, 16)
        ..lineTo(27, 30)
        ..lineTo(23, 30)
        ..lineTo(13, 23)
        ..close()
        ..moveTo(53, 13)
        ..lineTo(42, 16)
        ..lineTo(37, 30)
        ..lineTo(41, 30)
        ..lineTo(51, 23)
        ..close()
        ..moveTo(16, 34)
        ..lineTo(48, 34)
        ..lineTo(48, 38)
        ..lineTo(16, 38)
        ..close()
        ..moveTo(19, 42)
        ..lineTo(45, 42)
        ..lineTo(42, 55)
        ..lineTo(38, 59)
        ..lineTo(26, 59)
        ..lineTo(22, 55)
        ..close(),
    ],
  };

  static final List<Path> _unknown = <Path>[
    Path()
      ..moveTo(18, 12)
      ..lineTo(46, 12)
      ..lineTo(54, 20)
      ..lineTo(54, 44)
      ..lineTo(46, 52)
      ..lineTo(18, 52)
      ..lineTo(10, 44)
      ..lineTo(10, 20)
      ..close(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final scale = size.shortestSide / 64;
    canvas.save();
    canvas.translate(
      (size.width - 64 * scale) / 2,
      (size.height - 64 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()..color = color;
    for (final path in _icons[category] ?? _unknown) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Silhouette old) =>
      old.category != category || old.color != color;
}
