import 'package:flutter/widgets.dart';

import '../../features/overlay_settings/overlay_visor_events_sample.dart';
import '../../features/overlay_settings/overlay_visor_layout.dart';
import '../../features/overlay_settings/overlay_visor_overlap_warning.dart';
import '../../features/overlay_settings/overlay_visor_rally_sample.dart';
import '../../features/overlay_settings/overlay_workspace_models.dart';

/// What a block shows inside its outline in Alt+M placement on the visor
/// (moved out of menu_hud_placement.dart for the 800-line size gate): the
/// events box holds the most events at once as samples; the rally box a
/// sample rally as the game draws it (11-18 "照真实召集的样子"). Null for the
/// other blocks and off the visor.
Widget? menuHudVisorSample(
  String key,
  OverlayWorkspaceSettings? visor,
  Rect rect,
  Size surface,
) => switch (key) {
  _ when visor == null => null,
  'Events' => Opacity(
    opacity: .55,
    child: OverlayVisorEventsSample(
      count: (visor['eventNotificationMaxVisibleCount'] as num?)?.round() ?? 3,
      right: visor['eventNotificationSide'] != 'Left',
      unit: OverlayVisorEventsSample.unitFor(
        OverlayVisorLayout.sizeFactor(visor),
        surface,
      ),
    ),
  ),
  'Notice' => OverlayVisorRallySample(
    unit: rect.width / OverlayVisorRallySample.width,
  ),
  _ => null,
};

/// The visor's placement aids under the blocks: the rally's other dock while
/// its block is selected or dragged (OverlayVisorRallySlots; none while it is
/// hidden, [rally] null) and the warning where the events and the members
/// would overlap (OverlayVisorOverlapWarning, 11-18). Null when neither shows.
Widget? menuHudVisorAids({
  required List<OverlayWorkspaceLayoutItem> items,
  required OverlayWorkspaceSettings? visor,
  required Rect? rally,
  required bool selected,
  required double? dragDy,
  required Size surface,
}) {
  if (visor == null) return null;
  final aids = [
    if (rally != null)
      ?OverlayVisorRallySlots.forLayout(
        layout: items,
        settings: visor,
        surface: surface,
        scale: const Offset(1, 1),
        selected: selected,
        dragDy: dragDy,
      ),
    ?OverlayVisorOverlapWarning.forLayout(
      layout: items,
      settings: visor,
      surface: surface,
    ),
  ];
  return aids.isEmpty ? null : Positioned.fill(child: Stack(children: aids));
}

/// A block's name in placement, with its marks: locked, fixed (the
/// crosshair), and on the visor the rally's dock (11-18 "召集与提醒 · 顶部").
String menuHudModuleTag(
  String Function(String key) text,
  String key,
  OverlayWorkspaceLayoutItem? item, {
  required bool visor,
}) => [
  text('menu.hudQuick.module.$key'),
  if (key == 'Notice' && visor)
    text(
      'overlay.workspace.anchor.'
      '${item?.verticalAnchor == 'Bottom' ? 'Bottom' : 'Top'}',
    ),
  if (item?.isLocked ?? false) text('menu.hudPlace.locked'),
  if (key == 'Crosshair') text('menu.hudPlace.fixed'),
].join(' · ');
