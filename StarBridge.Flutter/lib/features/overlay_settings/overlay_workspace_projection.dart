import 'package:flutter/foundation.dart';

import 'overlay_settings_models.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_rules.dart';

enum OverlayWorkspaceOperation { none, reading, saving, presetAction }

@immutable
final class OverlayWorkspaceProjection {
  const OverlayWorkspaceProjection({
    required this.operation,
    this.runtimeOperation = OverlayRuntimeOperation.none,
    this.runtime = const OverlayRuntimeSnapshot.unavailable(),
    this.snapshot,
    this.settings,
    this.layout = const [],
    this.renderMode,
    this.hotkey,
    this.sources,
    this.failure,
    this.dirty = false,
  });

  const OverlayWorkspaceProjection.loading()
    : this(operation: OverlayWorkspaceOperation.reading);

  factory OverlayWorkspaceProjection.fromSnapshot(
    OverlayWorkspaceSnapshot snapshot, {
    OverlayRuntimeSnapshot runtime = const OverlayRuntimeSnapshot.unavailable(),
  }) {
    final settings = snapshot.settings;
    return OverlayWorkspaceProjection(
      operation: OverlayWorkspaceOperation.none,
      runtime: runtime,
      snapshot: snapshot,
      settings: settings == null
          ? null
          : applyOverlayWorkspaceAppearanceAvailability(
              settings,
              snapshot.appearances,
            ),
      layout: snapshot.layout,
      renderMode: snapshot.renderMode,
      hotkey: snapshot.hotkey,
      sources: snapshot.sourcePresetsEnabled
          ? snapshot.presets.where((p) => p.isActive).firstOrNull?.sources
          : null,
      failure: snapshot.failure,
    );
  }

  final OverlayWorkspaceOperation operation;
  final OverlayRuntimeOperation runtimeOperation;
  final OverlayRuntimeSnapshot runtime;
  final OverlayWorkspaceSnapshot? snapshot;
  final OverlayWorkspaceSettings? settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final String? renderMode;
  final OverlayWorkspaceHotkey? hotkey;
  final OverlayPresetSources? sources;
  final OverlaySettingsFailure? failure;
  final bool dirty;

  bool get available =>
      snapshot?.availability == OverlayWorkspaceAvailability.available &&
      settings != null &&
      renderMode != null &&
      hotkey != null &&
      snapshot?.revision != null;

  bool get busy =>
      operation != OverlayWorkspaceOperation.none ||
      runtimeOperation != OverlayRuntimeOperation.none;

  bool get runtimeBusy => runtimeOperation != OverlayRuntimeOperation.none;

  OverlayWorkspaceProjection copyWith({
    OverlayWorkspaceOperation? operation,
    OverlayRuntimeOperation? runtimeOperation,
    OverlayRuntimeSnapshot? runtime,
    OverlayWorkspaceSnapshot? snapshot,
    OverlayWorkspaceSettings? settings,
    List<OverlayWorkspaceLayoutItem>? layout,
    String? renderMode,
    OverlayWorkspaceHotkey? hotkey,
    OverlayPresetSources? sources,
    OverlaySettingsFailure? failure,
    bool clearFailure = false,
    bool? dirty,
  }) => OverlayWorkspaceProjection(
    operation: operation ?? this.operation,
    runtimeOperation: runtimeOperation ?? this.runtimeOperation,
    runtime: runtime ?? this.runtime,
    snapshot: snapshot ?? this.snapshot,
    settings: settings ?? this.settings,
    layout: layout ?? this.layout,
    renderMode: renderMode ?? this.renderMode,
    hotkey: hotkey ?? this.hotkey,
    sources: sources ?? this.sources,
    failure: clearFailure ? null : failure ?? this.failure,
    dirty: dirty ?? this.dirty,
  );
}
