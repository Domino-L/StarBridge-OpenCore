import 'package:flutter/material.dart';

import '../../features/overlay_settings/overlay_workspace_layout_geometry.dart';
import 'menu_bridge_preview.dart';
import 'menu_hud_placement.dart';
import 'menu_hud_quick_view.dart';

/// Small seams used by [MenuBridgePreview]; kept here so the preview stays a
/// thin composition of the information-overlay entry points.

/// Header button: switch the overlay directly (the dock opens the panel).
void menuHudToggle(MenuBridgePreview widget) {
  if (widget.settingsPreview || !widget.visible) return;
  if (widget.features['hud']?.busy ?? false) return;
  widget.onFeatureAction?.call('hud', 'toggle', '');
}

/// Arrange mode replaces the whole menu (no scrim, no chrome, no windows).
Widget? menuHudPlacementFor(MenuBridgePreview widget) {
  final quick = widget.features['hud']?.hudQuick;
  final act = widget.onFeatureAction;
  if (quick == null || !quick.placing || act == null) return null;
  return MenuHudPlacementLayer(
    view: quick,
    onAction: (key, value) => act('hud', key, value),
    onDismiss: widget.onDismiss,
  );
}

/// The menu scrim. While the quick panel is open it leaves the visible
/// overlay modules undimmed, so changes are judged at real brightness.
class MenuHudScrim extends StatelessWidget {
  const MenuHudScrim({
    super.key,
    required this.scrimKey,
    required this.color,
    this.quick,
  });
  final Key scrimKey;
  final Color color;
  final MenuHudQuickView? quick;
  @override
  Widget build(BuildContext context) {
    final quick = this.quick;
    if (quick == null || quick.layout.isEmpty) {
      return ColoredBox(key: scrimKey, color: color);
    }
    return CustomPaint(
      key: scrimKey,
      painter: _Scrim(color, quick),
      child: const SizedBox.expand(),
    );
  }
}

class _Scrim extends CustomPainter {
  const _Scrim(this.color, this.quick);
  final Color color;
  final MenuHudQuickView quick;
  @override
  void paint(Canvas canvas, Size size) {
    final holes = Path()..fillType = PathFillType.evenOdd;
    holes.addRect(Offset.zero & size);
    final shown = [
      for (final item in quick.layout)
        if (quick.modules[item.key] ?? false) item,
    ];
    for (final rect in OverlayWorkspaceLayoutGeometry.resolveItems(
      shown,
      surfaceSize: size,
    ).values) {
      holes.addRect(rect);
    }
    if (quick.modules['Events'] ?? false) {
      holes.addRect(
        OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
          surfaceWidth: size.width,
          surfaceHeight: size.height,
          side: quick.eventSide,
          normalizedY: quick.eventY,
          preferredHeight:
              OverlayWorkspaceLayoutGeometry
                  .singleEventNotificationPlacementHeight *
              2,
        ),
      );
    }
    canvas.drawPath(holes, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Scrim old) =>
      old.color != color || !identical(old.quick, quick);
}
