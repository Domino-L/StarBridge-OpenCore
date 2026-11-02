import 'dart:ui';

import 'menu_workspace_controller.dart';

/// Initial presentation defaults only. The preview retains panel lifetimes,
/// restored geometry, profile targets and all command/persistence ownership.
List<MenuPanelSpec> menuBridgePanelSpecs({
  required bool hasHangar,
  required bool hasLocalTools,
  required Iterable<String> profileIds,
  MenuPanelSpec? hudPanel,
  Size? commsViewport,
}) => [
  if (hasHangar)
    MenuPanelSpec(
      id: 'execHangar',
      initialBounds: const Rect.fromLTWH(128, 112, 680, 620),
      minimumSize: const Size(320, 240),
    ),
  if (hudPanel != null)
    for (final id in const ['organizations', 'rooms'])
      MenuPanelSpec(
        id: id,
        initialBounds: id == 'organizations'
            ? const Rect.fromLTWH(168, 132, 900, 620)
            : const Rect.fromLTWH(168, 132, 680, 550),
        viewportBounds: id == 'organizations'
            ? _initialOrganizationBounds
            : null,
        minimumSize: const Size(320, 200),
      ),
  ?hudPanel,
  if (hasLocalTools)
    for (final id in const ['screenshot', 'image', 'browser', 'settings'])
      MenuPanelSpec(
        id: id,
        initialBounds: const Rect.fromLTWH(128, 132, 820, 560),
        minimumSize: const Size(320, 200),
      ),
  MenuPanelSpec(
    id: 'friends',
    initialBounds: const Rect.fromLTWH(28, 112, 340, 550),
    minimumSize: const Size(300, 180),
  ),
  MenuPanelSpec(
    id: 'comms',
    initialBounds: commsViewport == null
        ? const Rect.fromLTWH(408, 136, 460, 480)
        : Rect.fromLTWH(
            48,
            88,
            (commsViewport.width - 96).clamp(320, 980),
            (commsViewport.height - 176).clamp(240, 680),
          ),
    minimumSize: const Size(320, 180),
  ),
  for (final id in profileIds)
    MenuPanelSpec(
      id: id,
      initialBounds: const Rect.fromLTWH(108, 132, 900, 620),
      minimumSize: const Size(360, 240),
    ),
];

Rect _initialOrganizationBounds(Size viewport) {
  final width = (viewport.width - 48).clamp(320.0, 900.0);
  final height = (viewport.height - 180).clamp(200.0, 620.0);
  // Initial placement only: never clamp a restored or manually moved window.
  return Rect.fromLTWH((viewport.width - width) / 2, 64, width, height);
}
