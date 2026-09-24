import 'package:flutter/widgets.dart';

import '../../app/preferences/app_preferences_port.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../overlay_settings/overlay_workspace_port.dart';
import 'bridge_runtime_facts.dart';
import 'bridge_runtime_overlay_status.dart';
import 'runtime_status_controller.dart';
import 'runtime_status_dialog.dart';
import 'runtime_status_sources.dart';

Future<void> showConnectedRuntimeStatus(
  BuildContext context, {
  required AppPreferencesPort preferences,
  required BridgeClientSession? session,
  required bool metadataAvailable,
  bool overlayStatusAvailable = false,
  OverlayWorkspacePort? overlay,
}) async {
  final controller = createRuntimeStatusController(
    preferences: preferences,
    session: session,
    metadataAvailable: metadataAvailable,
    overlayStatusAvailable: overlayStatusAvailable,
    overlay: overlay,
  );
  try {
    await showRuntimeStatusDialog(context, controller);
  } finally {
    controller.dispose();
  }
}

RuntimeStatusController createRuntimeStatusController({
  required AppPreferencesPort preferences,
  required BridgeClientSession? session,
  required bool metadataAvailable,
  bool overlayStatusAvailable = false,
  OverlayWorkspacePort? overlay,
}) => RuntimeStatusController(
  readInstallation: () async => session == null || !metadataAvailable
      ? null
      : BridgeRuntimeFacts(session).read(),
  readOverlay: () async {
    if (session == null || overlay == null) return null;
    final generation = session.activeGeneration;
    final facts = await readRuntimeOverlayFacts(
      overlay,
      readStatus: () async => overlayStatusAvailable
          ? BridgeRuntimeOverlayStatus(session).read()
          : const RuntimeOverlayStatus(
              windowState: 'unavailable',
              hotkeyState: 'unavailable',
              appliedRevision: 0,
            ),
    );
    return generation == session.activeGeneration ? facts : null;
  },
  readStartup: () async => runtimeStartupFacts(preferences.projection.value),
);
