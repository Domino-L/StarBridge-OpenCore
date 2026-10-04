import 'dart:async';

import 'package:flutter/foundation.dart';

import 'overlay_scene_controller.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

/// One session-scoped coordinator for every editor and the native runtime.
/// Observes shared projections only: no timer, I/O reader or authority cache.
final class OverlayPresetAutoSwitch {
  OverlayPresetAutoSwitch(this.workspace, this.scenes) {
    _manual = workspace.manualPresetSelection;
    workspace.projection.addListener(_schedule);
    scenes.addListener(_schedule);
    _schedule();
  }

  final OverlayWorkspaceModule workspace;
  final ValueListenable<OverlaySceneState> scenes;
  (String, int)? _scope;
  String? _source, _restorePreset, _observedActive;
  Object? _attempt;
  int _manual = 0;
  bool _paused = false, _scheduled = false, _running = false, _disposed = false;

  void _schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) unawaited(_reconcile());
    });
  }

  Future<void> _reconcile() async {
    final scene = scenes.value;
    final owner = scene.sourceOwnerKey;
    final generation = scene.contextGeneration;
    final scope = owner == null || generation == null
        ? null
        : (owner, generation);
    if (scope != _scope) {
      _scope = scope;
      _source = null;
      _restorePreset = null;
      _observedActive = null;
      _attempt = null;
      _paused = false;
      _manual = workspace.manualPresetSelection;
    }
    final current = workspace.projection.value;
    final snapshot = current.snapshot;
    final active = snapshot?.activePresetId;
    if (workspace.manualPresetSelection != _manual ||
        !_running &&
            _observedActive != null &&
            active != null &&
            active != _observedActive) {
      _manual = workspace.manualPresetSelection;
      _paused = true;
      _restorePreset = null;
    }
    if (!_running) _observedActive = active;
    // An unknown source suppresses new commands, but is not a leave event.
    // Invalidated identities above erase the pending transition immediately.
    if (scope == null ||
        !scene.available ||
        scene.busy ||
        scene.failure ||
        scene.automaticPresetSourceId == null ||
        snapshot?.sourcePresetsEnabled != true) {
      return;
    }
    final source = scene.automaticPresetSourceId!;
    if (source != _source) {
      // First confirmation establishes a baseline, not a source transition
      // that may override a manual choice made while this scope was unknown.
      if (_source != null) _paused = false;
      _source = source;
      _attempt = null;
    }
    if (_running ||
        _paused ||
        current.dirty ||
        current.busy ||
        !current.available ||
        active == null) {
      return;
    }
    final matches = snapshot!.presets.where((preset) {
      final policy = preset.sources;
      if (policy == null || !policy.autoSwitch) return false;
      final binding = policy.binding;
      return source.startsWith('room:') &&
              binding.mode == OverlaySourceMode.room ||
          source.startsWith('org:') &&
              binding.mode == OverlaySourceMode.community &&
              binding.ownerKey == owner &&
              source == 'org:${binding.communityCode}';
    }).toList();
    // Corrupt/conflicting metadata is never resolved by arbitrary list order.
    if (matches.length > 1) return;
    final target = matches.firstOrNull?.id ?? _restorePreset;
    if (target == null || !snapshot.presets.any((p) => p.id == target)) {
      _restorePreset = null;
      return;
    }
    if (target == active) {
      if (matches.isEmpty) _restorePreset = null;
      return;
    }
    final attempt = (scope, source, target, snapshot.revision);
    if (_attempt == attempt) {
      return; // Never replay an uncertain write on a poll.
    }
    _attempt = attempt;
    _running = true;
    final restore = _restorePreset ?? active;
    try {
      final completed = await workspace.activatePresetAutomatically(
        target,
        ownerKey: scope.$1,
        generation: scope.$2,
        source: source,
      );
      if (_disposed || _scope != scope) return;
      _observedActive = workspace.projection.value.snapshot?.activePresetId;
      if (completed) _restorePreset = matches.isEmpty ? null : restore;
    } finally {
      _running = false;
      // Process the latest source after an in-flight save; never a queued old room.
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    workspace.projection.removeListener(_schedule);
    scenes.removeListener(_schedule);
  }
}
