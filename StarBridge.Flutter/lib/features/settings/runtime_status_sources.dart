import '../../app/preferences/app_preferences_projection.dart';
import '../overlay_settings/overlay_workspace_models.dart';
import '../overlay_settings/overlay_workspace_port.dart';
import 'runtime_status_controller.dart';
import 'bridge_runtime_overlay_status.dart';

/// Consume the confirmed preference owner; never show effective fallback defaults
/// as a successful read after the Host has disconnected.
RuntimeStartupFacts? runtimeStartupFacts(AppPreferencesProjection projection) {
  if (projection.phase != AppPreferencesPhase.ready ||
      projection.operation != AppPreferencesOperation.idle) {
    return null;
  }
  final behavior = projection.confirmed?.applicationBehavior;
  return behavior == null
      ? null
      : RuntimeStartupFacts(
          launchAtStartup: behavior.launchAtStartup,
          startMinimized: behavior.startMinimized,
          keepRunningInBackground: behavior.keepRunningInBackground,
        );
}

/// Reuse the existing parser/port. Never pass an editor draft, save a workspace,
/// open/close the overlay, or retry a failed hotkey from a status dialog.
/// In particular, never use the existing getState command: it applies settings.
Future<RuntimeOverlayFacts?> readRuntimeOverlayFacts(
  OverlayWorkspacePort port, {
  required Future<RuntimeOverlayStatus> Function() readStatus,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final workspaceRead = _read(port.read, timeout);
  final runtimeRead = _read(readStatus, timeout);
  final workspace = await workspaceRead;
  final runtime = await runtimeRead;
  final hasWorkspace =
      workspace?.availability == OverlayWorkspaceAvailability.available;
  final hasRuntime = runtime?.available ?? false;
  if (!hasWorkspace && !hasRuntime) return null;
  // Another window may save between reads. Do not attach an old preset/binding
  // to runtime state that reports a different revision.
  final consistent =
      hasWorkspace &&
      (!hasRuntime || workspace!.revision == runtime!.appliedRevision);
  final active = consistent
      ? workspace!.presets
            .where((p) => p.isActive && p.id == workspace.activePresetId)
            .toList()
      : const <OverlayWorkspacePreset>[];
  return RuntimeOverlayFacts(
    windowState: hasRuntime ? runtime!.windowState : null,
    hotkeyState: hasRuntime ? runtime!.hotkeyState : null,
    hotkeyBinding: hasRuntime ? runtime!.hotkeyBinding : null,
    presetName: active.length == 1 ? active.single.name : null,
    renderMode: consistent ? workspace!.renderMode : null,
  );
}

Future<T?> _read<T>(Future<T> Function() read, Duration timeout) async {
  try {
    return await read().timeout(timeout);
  } on Object {
    return null;
  }
}
