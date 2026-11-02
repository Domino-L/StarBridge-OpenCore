import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';

/// Hover is color-only. A row is not a second click target over its controls.
/// At rest the border is the holo hairline (user 2026-10-29: the preview's
/// low-contrast border), so the art and the text carry the card.
class CommunityShipRowSurface extends StatefulWidget {
  const CommunityShipRowSurface({
    required this.child,
    this.card = false,
    this.selected = false,
    super.key,
  });
  final Widget child;

  /// The ship open in the side column (user 2026-10-29, option D).
  final bool selected;

  /// Grid card: square, as the approved preview (user 2026-10-29: no cut
  /// corner on ship cards), no inner padding so the art runs edge to edge.
  final bool card;
  @override
  State<CommunityShipRowSurface> createState() =>
      _CommunityShipRowSurfaceState();
}

class _CommunityShipRowSurfaceState extends State<CommunityShipRowSurface> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final holo = OrganizationHoloColors(context);
    final border = widget.selected
        ? tokens.colors.accent
        : hovered
        ? tokens.colors.info.withValues(alpha: .65)
        : holo.hair;
    final side = BorderSide(color: border, width: widget.selected ? 1.5 : 1);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Container(
        clipBehavior: widget.card ? Clip.antiAlias : Clip.none,
        padding: widget.card
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: hovered
              ? tokens.surfaces.raised.fill
              : widget.card
              ? holo.well
              : tokens.surfaces.panel.fill,
          shape: RoundedRectangleBorder(
            side: side,
            borderRadius: BorderRadius.circular(widget.card ? 0 : 4),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
