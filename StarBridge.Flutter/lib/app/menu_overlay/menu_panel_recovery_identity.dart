import 'menu_bridge_dock.dart';
import 'menu_workspace_controller.dart';

/// Read-only identity projection for context-menu retirement. Unknown panel ids
/// remain owned by the workspace and are deliberately not converted to tools.
/// No layout, persistence or window command is performed here.
Map<BridgePreviewPanel, Object> menuPanelRecoveryIdentities(
  Iterable<MenuPanelLease> leases,
) => {
  for (final panel in BridgePreviewPanel.values)
    for (final lease in leases)
      if (lease.id == panel.name) panel: lease,
};
