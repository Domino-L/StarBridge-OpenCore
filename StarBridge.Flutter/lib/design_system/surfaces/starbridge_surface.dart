import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/starbridge_tokens.dart';

class StarBridgeSurface extends StatelessWidget {
  const StarBridgeSurface({
    required this.role,
    required this.child,
    this.padding,
    this.borderRadius,
    this.fillOpacity = 1,
    super.key,
  }) : assert(fillOpacity >= 0 && fillOpacity <= 1);

  final SurfaceRole role;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final surface = tokens.surfaces.resolve(role);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.fill.withValues(alpha: surface.fill.a * fillOpacity),
        border: Border.all(color: surface.border, width: tokens.stroke.regular),
        borderRadius: borderRadius ?? tokens.shape.medium,
        boxShadow: surface.shadows,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(tokens.density.panelPadding),
        child: child,
      ),
    );
  }
}
