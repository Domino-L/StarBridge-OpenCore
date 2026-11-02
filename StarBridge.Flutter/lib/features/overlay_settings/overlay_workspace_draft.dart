import 'package:flutter/foundation.dart';

import 'overlay_workspace_models.dart';
import 'overlay_workspace_projection.dart';

/// Immutable undo/redo snapshot. Persistence and live ownership stay in Module.
@immutable
final class OverlayWorkspaceDraft {
  const OverlayWorkspaceDraft({
    required this.settings,
    required this.layout,
    required this.renderMode,
    required this.hotkey,
    this.sources,
    required this.appearanceOptions,
    required this.dirty,
  });

  factory OverlayWorkspaceDraft.fromProjection(
    OverlayWorkspaceProjection projection,
  ) => OverlayWorkspaceDraft(
    settings: projection.settings!,
    layout: List.unmodifiable(projection.layout),
    renderMode: projection.renderMode!,
    hotkey: projection.hotkey!,
    sources: projection.sources,
    appearanceOptions: projection.appearanceOptions,
    dirty: projection.dirty,
  );

  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final String renderMode;
  final OverlayWorkspaceHotkey hotkey;
  final OverlayPresetSources? sources;
  final OverlayAppearanceOptions appearanceOptions;
  final bool dirty;
  OverlayWorkspaceProjection applyTo(OverlayWorkspaceProjection current) =>
      current.copyWith(
        settings: settings,
        layout: layout,
        renderMode: renderMode,
        hotkey: hotkey,
        sources: sources,
        appearanceOptions: appearanceOptions,
        clearFailure: true,
        dirty: dirty,
      );
  OverlayWorkspaceDraft withSources(OverlayPresetSources? value) =>
      OverlayWorkspaceDraft(
        settings: settings,
        layout: layout,
        renderMode: renderMode,
        hotkey: hotkey,
        dirty: dirty,
        sources: value,
        appearanceOptions: appearanceOptions,
      );
}
