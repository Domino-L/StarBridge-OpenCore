import 'package:flutter/foundation.dart';

import 'overlay_appearance_live_session.dart';
import 'overlay_appearance_progress.dart';
import 'overlay_preview_guide_port.dart';
import 'overlay_visor_editor_content.dart';
import 'overlay_workspace_port.dart';
import 'overlay_workspace_port_capabilities.dart';
import 'overlay_workspace_projection.dart';
import 'overlay_workspace_runtime_sync.dart';

/// The optional capabilities of the module's port (moved out of
/// overlay_workspace_module.dart for the 800-line size gate).
mixin OverlayWorkspaceModulePorts {
  /// The port the module reads and writes through.
  @protected
  OverlayWorkspacePort get capabilityPort;
  String get runtimeLanguage;
  ValueListenable<OverlayWorkspaceProjection> get projection;

  OverlayPreviewGuidePort? get previewGuidePort => capabilityPort.previewGuide;
  OverlayAppearanceLivePort? get appearanceLivePort =>
      capabilityPort.appearanceLive;
  OverlayAppearanceProgressPort? get appearanceProgressPort =>
      capabilityPort.appearanceProgress;
  OverlayAppearancePreviewPort? get appearancePreviewPort =>
      capabilityPort.appearancePreview;

  /// What the visor would show, read from the Host for the layout editor's
  /// simplified panels with the current draft; null when the Host cannot.
  OverlayVisorEditorContentSource? createVisorEditorContent() {
    final port = capabilityPort.visorEditorContent;
    if (port == null) return null;
    return OverlayVisorEditorContentSource(
      port: port,
      language: () => runtimeLanguage,
      draft: () => projection.value.runtimeDraft,
    );
  }
}
