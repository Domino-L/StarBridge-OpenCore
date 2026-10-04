import 'dart:async';

import 'overlay_scene_controller.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

/// One controller feeds both selectors. The Host owns the temporary intent;
/// no picker persists a shadow account choice or changes the preset's draft.
final class OverlaySourceSelectionCoordinator {
  OverlaySourceSelectionCoordinator(this.workspace, this.scenes) {
    scenes.selectTemporary = _select;
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

  Future<bool> _select(String id) {
    final owner = scenes.projection.value.sourceOwnerKey;
    if (_closed || owner == null) return Future.value(false);
    final source = switch (id) {
      'auto' => const OverlaySourceBinding.automatic(),
      'room' => const OverlaySourceBinding.room(),
      'resumeBinding' => const OverlaySourceBinding.follow(),
      _ when id.startsWith('org:') => OverlaySourceBinding.community(
        id.substring(4),
        owner,
      ),
      _ => null,
    };
    return source == null
        ? Future.value(false)
        : workspace.selectTemporarySource(source, owner);
  }

  void dispose() {
    _closed = true;
    scenes.selectTemporary = null;
    workspace.projection.removeListener(_changed);
  }
}
