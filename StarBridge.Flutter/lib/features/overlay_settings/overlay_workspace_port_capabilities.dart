import 'overlay_appearance_live_session.dart';
import 'overlay_appearance_progress.dart';
import 'overlay_preview_guide_port.dart';
import 'overlay_workspace_port.dart';

/// Optional capabilities a workspace port may also implement. Each is null
/// unless the port implements it and reports it as currently supported.
extension OverlayWorkspacePortCapabilities on OverlayWorkspacePort {
  OverlayPreviewGuidePort? get previewGuide =>
      this is OverlayPreviewGuidePort ? this as OverlayPreviewGuidePort : null;

  OverlayAppearanceLivePort? get appearanceLive =>
      this is OverlayAppearanceLivePort &&
          this is OverlayAppearanceLiveControlsPort &&
          this is OverlayAppearanceLivePlaybackPort &&
          this is OverlayAppearanceLiveAvailability &&
          (this as OverlayAppearanceLiveAvailability)
              .supportsLiveAppearancePreview
      ? this as OverlayAppearanceLivePort
      : null;

  OverlayAppearanceProgressPort? get appearanceProgress =>
      this is OverlayAppearanceProgressPort &&
          (this as OverlayAppearanceProgressPort).supportsAppearanceProgress
      ? this as OverlayAppearanceProgressPort
      : null;

  OverlayAppearancePreviewPort? get appearancePreview =>
      this is OverlayAppearancePreviewPort
      ? this as OverlayAppearancePreviewPort
      : null;
}
