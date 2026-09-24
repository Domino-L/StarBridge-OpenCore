import 'package:flutter/material.dart';

import 'icon_semantic.dart';
import 'starbridge_icon_geometry.dart';
import 'starbridge_icon_painter.dart';
import 'starbridge_icon_set.dart';

/// Renders a semantic StarBridge icon without exposing its glyph source.
///
/// A null [size] or [color] inherits from the ambient [IconTheme]. A null
/// [textDirection] inherits from [Directionality] for direction-aware glyphs.
class StarBridgeIcon extends StatelessWidget {
  const StarBridgeIcon(
    this.semantic, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  final StarBridgeIconSemantic semantic;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final baseColor =
        color ??
        iconTheme.color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.black;
    final opacity = iconTheme.opacity ?? 1;
    final resolvedColor = opacity == 1
        ? baseColor
        : baseColor.withValues(alpha: baseColor.a * opacity);
    final direction =
        textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
    final glyph = StarBridgeIconSet.resolve(semantic);
    final paintedIcon = ExcludeSemantics(
      child: SizedBox.square(
        dimension: resolvedSize,
        child: CustomPaint(
          painter: StarBridgeIconPainter(
            semantic: semantic,
            color: resolvedColor,
            opticalSize: starBridgeIconOpticalSizeFor(resolvedSize),
            mirrored:
                glyph.matchTextDirection && direction == TextDirection.rtl,
          ),
        ),
      ),
    );
    if (semanticLabel == null) {
      return paintedIcon;
    }
    return Semantics(
      label: semanticLabel,
      textDirection: direction,
      child: paintedIcon,
    );
  }
}
