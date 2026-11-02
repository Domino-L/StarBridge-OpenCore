import 'dart:async';

import 'overlay_scene_controller.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

/// One controller feeds every selector. A selection is the remembered account
/// choice; on an explicit "follow" this releases the active plan's fixed
/// source (the Host then also drops any session source left on that plan).
final class OverlaySourceSelectionCoordinator {
  OverlaySourceSelectionCoordinator(this.workspace, this.scenes) {
    scenes.followShared = followShared;
    workspace.projection.addListener(_changed);
  }
  final OverlayWorkspaceModule workspace;
  final OverlaySceneController scenes;
  Object? _lastRevision;
  bool _closed = false;

  void _changed() {
    final state = workspace.projection.value;
    if (_closed || state.busy || state.snapshot?.sourcePresetsEnabled != true) {
      return;
    }
    final next = (state.snapshot!.revision, state.snapshot!.activePresetId);
    if (_lastRevision == next) return;
    _lastRevision = next;
    scheduleMicrotask(() {
      if (!_closed) unawaited(scenes.refresh());
    });
  }

  /// Keeps the plan's name, layout and module sources; only its fixed source
  /// and automatic use are released. Never called without a user action.
  Future<bool> followShared() {
    final snapshot = workspace.projection.value.snapshot;
    final plan = snapshot?.presets
        .where((preset) => preset.id == snapshot.activePresetId)
        .firstOrNull;
    final sources = plan?.sources;
    if (_closed ||
        snapshot?.sourcePresetsEnabled != true ||
        plan == null ||
        sources == null ||
        sources.binding.mode == OverlaySourceMode.none) {
      return Future.value(false);
    }
    return workspace.configurePreset(
      plan.id,
      plan.name,
      const OverlaySourceBinding.follow(),
      false,
      expectedRevision: snapshot!.revision,
    );
  }

  void dispose() {
    _closed = true;
    scenes.followShared = null;
    workspace.projection.removeListener(_changed);
  }
}
