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

/// Optional Host push of the snapshot `overlay.runtime.getState` returns, sent
/// whenever it changes (open/close, hotkey, follow-game, skin, failure).
/// Only valid snapshots of the current bridge generation are emitted.
abstract interface class OverlayRuntimeChangePort {
  bool get supportsRuntimeChanges;
  Stream<OverlayRuntimeSnapshot> get runtimeChanges;
}

/// Optional isolated native preview; never saves settings or opens the real HUD.
abstract interface class OverlayAppearancePreviewPort {
  Future<String> openAppearancePreview(
    String appearanceId,
    OverlayAppearanceOptions options, {
    bool reduceMotion = false,
  });
  Future<void> closeAppearancePreview(String sessionId);
}
