import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// Hover is color-only. A row is not a second click target over its controls.
class CommunityShipRowSurface extends StatefulWidget {
  const CommunityShipRowSurface({required this.child, super.key});
  final Widget child;
  @override
  State<CommunityShipRowSurface> createState() =>
      _CommunityShipRowSurfaceState();
}

class _CommunityShipRowSurfaceState extends State<CommunityShipRowSurface> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hovered
              ? tokens.surfaces.raised.fill
              : tokens.surfaces.panel.fill,
          border: Border.all(
            color: hovered
                ? tokens.colors.info.withValues(alpha: .65)
                : tokens.surfaces.panel.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: widget.child,
      ),
    );
  }
}
