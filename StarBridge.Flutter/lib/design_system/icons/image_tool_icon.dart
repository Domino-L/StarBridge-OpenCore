import 'package:flutter/material.dart';

/// Image-editor gestures absent from the shared catalog, using its 24px
/// stroked geometry. Common actions continue to use the existing catalog.
enum ImageToolGlyph { crop, pin, rotate }

class ImageToolIcon extends StatelessWidget {
  const ImageToolIcon(this.glyph, {super.key});
  final ImageToolGlyph glyph;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CustomPaint(
      painter: _ImageToolPainter(glyph, IconTheme.of(context).color!),
    ),
  );
}

class _ImageToolPainter extends CustomPainter {
  const _ImageToolPainter(this.glyph, this.color);
  final ImageToolGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final path = Path();
    switch (glyph) {
      case ImageToolGlyph.crop:
        path
          ..moveTo(6, 2)
          ..lineTo(6, 18)
          ..lineTo(22, 18)
          ..moveTo(2, 6)
          ..lineTo(18, 6)
          ..lineTo(18, 22);
      case ImageToolGlyph.pin:
        path
          ..moveTo(7, 3)
          ..lineTo(17, 3)
          ..lineTo(15, 6)
          ..lineTo(15, 11)
          ..lineTo(19, 15)
          ..lineTo(5, 15)
          ..lineTo(9, 11)
          ..lineTo(9, 6)
          ..close()
          ..moveTo(12, 15)
          ..lineTo(12, 22);
      case ImageToolGlyph.rotate:
        path
          ..moveTo(20, 3)
          ..lineTo(20, 9)
          ..lineTo(14, 9)
          ..moveTo(20, 9)
          ..cubicTo(17, 1, 5, 2, 4, 11)
          ..cubicTo(3, 19, 13, 23, 18, 17);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ImageToolPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
