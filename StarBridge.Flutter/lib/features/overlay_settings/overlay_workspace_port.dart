import 'overlay_workspace_models.dart';

abstract interface class OverlayWorkspacePort {
  Future<OverlayWorkspaceSnapshot> read();

  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  });

  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  });

  Future<void> close();
}
