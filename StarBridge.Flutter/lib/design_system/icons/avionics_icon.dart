import 'package:flutter/material.dart';

import 'starbridge_icons_v2.dart';

/// Common rendering policy for the approved V2 semantic catalog.
class AvionicsIcon extends StatelessWidget {
  const AvionicsIcon(
    this.reference, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });
  final String reference;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final extent = size ?? theme.size ?? 24;
    final base =
        color ??
        theme.color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.black;
    final opacity = theme.opacity ?? 1;
    final resolved = opacity == 1 ? base : base.withValues(alpha: base.a * opacity);
    final direction =
        textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
    final spec = catalogBySemantic[reference]!;
    final content = ExcludeSemantics(
      child: SizedBox.square(
        dimension: extent,
        child: CustomPaint(
          painter: AvionicsIconPainter(
            spec,
            resolved,
            mirrored:
                direction == TextDirection.rtl &&
                const {
                  'arrowBack',
                  'arrowForward',
                  'chevronLeft',
                  'chevronRight',
                  'login',
                  'logout',
                }.contains(spec.key),
          ),
        ),
      ),
    );
    return semanticLabel == null
        ? content
        : Semantics(
            label: semanticLabel,
            textDirection: direction,
            child: content,
          );
  }
}

class AvionicsIconPainter extends CustomPainter {
  const AvionicsIconPainter(this.spec, this.color, {this.mirrored = false});
  final IconSpec spec;
  final Color color;
  final bool mirrored;
  @override
  void paint(Canvas canvas, Size size) {
    final extent = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - extent) / 2, (size.height - extent) / 2);
    canvas.scale(extent / 24);
    if (mirrored) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    spec.paint(IconPen(canvas, color, iconOpticFor(extent)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AvionicsIconPainter old) =>
      spec != old.spec || color != old.color || mirrored != old.mirrored;
}
