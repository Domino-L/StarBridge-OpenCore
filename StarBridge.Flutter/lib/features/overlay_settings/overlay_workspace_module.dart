import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/window/overlay_editor_window_port.dart';

import 'overlay_preview_identity.dart';
import 'overlay_settings_models.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';

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
    failure: clearFailure ? null : failure ?? this.failure,
    dirty: dirty ?? this.dirty,
  );
}

final class OverlayWorkspaceModule {
  OverlayWorkspaceModule(
    this._port, {
    this.editorWindow = const UnavailableOverlayEditorWindow(),
    this.previewIdentity,
  });

  final OverlayEditorWindowPort editorWindow;
  final ValueListenable<OverlayPreviewIdentity?>? previewIdentity;

  final OverlayWorkspacePort _port;
  final ValueNotifier<OverlayWorkspaceProjection> _projection = ValueNotifier(
    const OverlayWorkspaceProjection.loading(),
  );
  bool _disposed = false;
  bool _refreshing = false;
  bool _liveSyncInFlight = false;
  bool _liveSyncRequested = false;
  final List<_OverlayWorkspaceDraft> _undoHistory = [];
  final List<_OverlayWorkspaceDraft> _redoHistory = [];
  String? _lastHistoryKey;
  String _runtimeLanguage = 'zh';

  ValueListenable<OverlayWorkspaceProjection> get projection => _projection;
  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  Future<void> initialize() => refresh();

  /// Renew local workspace/runtime facts without blanking the page, discarding
  /// a draft, or replaying an open/close/save command after an uncertain result.
  Future<void> synchronize() async {
    if (_disposed || _refreshing || _projection.value.busy) return;
    _refreshing = true;
    final before = _projection.value;
    try {
      final snapshot = await _port.read();
      if (_disposed || !identical(before, _projection.value)) return;
      if (snapshot.availability != OverlayWorkspaceAvailability.available) {
        if (!before.available) {
          _projection.value = OverlayWorkspaceProjection.fromSnapshot(snapshot);
        }
        return;
      }
      if (before.dirty) {
        // Never apply an old draft onto a changed authoritative revision.
        if (snapshot.revision != before.snapshot?.revision) {
          _projection.value = before.copyWith(
            failure: OverlaySettingsFailure.writeConflict,
          );
          return;
        }
      } else {
        if (snapshot.revision != before.snapshot?.revision) _resetHistory();
        _projection.value = OverlayWorkspaceProjection.fromSnapshot(
          snapshot,
          runtime: before.runtime,
        );
      }
      final current = _projection.value;
      final runtime = await _port.executeRuntime(
        OverlayRuntimeAction.getState,
        language: _runtimeLanguage,
        draft: _runtimeDraft(current),
      );
      if (!_disposed && identical(current, _projection.value)) {
        _projection.value = current.copyWith(runtime: runtime);
      }
    } on Object {
      if (!_disposed &&
          identical(before, _projection.value) &&
          !before.available) {
        _projection.value = OverlayWorkspaceProjection.fromSnapshot(
          const OverlayWorkspaceSnapshot.unavailable(
            failure: OverlaySettingsFailure.readFailed,
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> refresh() async {
    if (_disposed ||
        _refreshing ||
        (_projection.value.busy &&
            _projection.value.operation != OverlayWorkspaceOperation.reading)) {
      return;
    }
    _refreshing = true;
    _projection.value = const OverlayWorkspaceProjection.loading();
    try {
      final snapshot = await _port.read();
      if (!_disposed) {
        _resetHistory();
        _projection.value = OverlayWorkspaceProjection.fromSnapshot(snapshot);
        if (snapshot.availability == OverlayWorkspaceAvailability.available) {
          _projection.value = _projection.value.copyWith(
            runtimeOperation: OverlayRuntimeOperation.reading,
          );
          final runtime = await _port.executeRuntime(
            OverlayRuntimeAction.getState,
            language: _runtimeLanguage,
          );
          if (!_disposed) {
            _projection.value = _projection.value.copyWith(
              runtimeOperation: OverlayRuntimeOperation.none,
              runtime: runtime,
            );
          }
        }
      }
    } on Object {
      if (!_disposed) {
        _projection.value = OverlayWorkspaceProjection.fromSnapshot(
          const OverlayWorkspaceSnapshot.unavailable(
            failure: OverlaySettingsFailure.readFailed,
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  void updateSetting(String field, Object? value) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    try {
      if (field == 'skin') {
        final requested = current.snapshot!.appearances.where(
          (appearance) => appearance.id == value,
        );
        if (requested.length != 1 ||
            !requested.single.isReleased ||
            !requested.single.isAvailable) {
          _projection.value = current.copyWith(
            failure: OverlaySettingsFailure.invalidValue,
          );
          return;
        }
      }
      final next = applyOverlayWorkspaceSettingChange(
        current.settings!,
        field,
        value,
      );
      final kind = overlayWorkspaceFieldSpecs
          .singleWhere((spec) => spec.field == field)
          .kind;
      _recordChange(
        current,
        key: 'setting:$field',
        coalesce:
            kind == OverlayWorkspaceFieldKind.number ||
            kind == OverlayWorkspaceFieldKind.color ||
            kind == OverlayWorkspaceFieldKind.eventDurations,
      );
      _projection.value = current.copyWith(
        settings: next,
        clearFailure: true,
        dirty: true,
      );
      _queueLiveRuntimeSync();
    } on Object {
      _projection.value = current.copyWith(
        failure: OverlaySettingsFailure.invalidValue,
      );
    }
  }

  void applyExperiencePreset(String preset) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final values = switch (preset) {
      'Smooth' => const <String, Object>{
        'enableStartupTransition': true,
        'startupTransitionFrameRate': 'Fps120',
        'animationFrameRate': 'Fps120',
      },
      'ReducedMotion' => const <String, Object>{
        'enableStartupTransition': false,
        'startupTransitionFrameRate': 'Fps60',
        'animationFrameRate': 'Fps60',
      },
      'Balanced' => const <String, Object>{
        'enableStartupTransition': true,
        'startupTransitionFrameRate': 'Fps60',
        'animationFrameRate': 'Fps60',
      },
      _ => null,
    };
    if (values == null) return;
    try {
      var next = current.settings!;
      for (final entry in values.entries) {
        next = applyOverlayWorkspaceSettingChange(next, entry.key, entry.value);
      }
      _recordChange(current, key: 'setting:experiencePreset', coalesce: false);
      _projection.value = current.copyWith(
        settings: next,
        clearFailure: true,
        dirty: true,
      );
      _queueLiveRuntimeSync();
    } on Object {
      _projection.value = current.copyWith(
        failure: OverlaySettingsFailure.invalidValue,
      );
    }
  }

  void beginEventNotificationGesture() {
    _lastHistoryKey = null;
  }

  void updateEventNotificationPlacement(String side, double normalizedY) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final normalizedSide = side == 'Left' ? 'Left' : 'Right';
    final clampedY = normalizedY.clamp(0.0, 1.0).toDouble();
    final currentSide = current.settings!['eventNotificationSide']! as String;
    final currentY = (current.settings!['eventNotificationY']! as num)
        .toDouble();
    if (currentSide == normalizedSide &&
        (currentY - clampedY).abs() < 0.000001) {
      return;
    }
    try {
      final next = current.settings!
          .withValue('eventNotificationSide', normalizedSide)
          .withValue('eventNotificationY', clampedY);
      _recordChange(
        current,
        key: 'setting:eventNotificationPlacement',
        coalesce: true,
      );
      _projection.value = current.copyWith(
        settings: next,
        clearFailure: true,
        dirty: true,
      );
      _queueLiveRuntimeSync();
    } on Object {
      _projection.value = current.copyWith(
        failure: OverlaySettingsFailure.invalidValue,
      );
    }
  }

  void endEventNotificationGesture() {
    _lastHistoryKey = null;
  }

  void updateLayoutItem(
    OverlayWorkspaceLayoutItem next, {
    bool coalesce = true,
  }) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final index = current.layout.indexWhere((item) => item.key == next.key);
    if (index < 0) return;
    final layout = List<OverlayWorkspaceLayoutItem>.from(current.layout);
    layout[index] = next;
    _recordChange(current, key: 'layout:${next.key}', coalesce: coalesce);
    _projection.value = current.copyWith(
      layout: List.unmodifiable(layout),
      clearFailure: true,
      dirty: true,
    );
    _queueLiveRuntimeSync();
  }

  void updateHotkey({String? binding, bool? enabled}) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final value = current.hotkey!;
    _recordChange(
      current,
      key: binding != null ? 'hotkey:binding' : 'hotkey:enabled',
      coalesce: binding != null,
    );
    _projection.value = current.copyWith(
      hotkey: OverlayWorkspaceHotkey(
        binding: binding ?? value.binding,
        enabled: enabled ?? value.enabled,
        runtimeState: value.runtimeState,
      ),
      clearFailure: true,
      dirty: true,
    );
    _queueLiveRuntimeSync();
  }

  void discardChanges() {
    final snapshot = _projection.value.snapshot;
    if (_disposed || snapshot == null || _projection.value.busy) return;
    _resetHistory();
    _projection.value = OverlayWorkspaceProjection.fromSnapshot(
      snapshot,
      runtime: _projection.value.runtime,
    );
    _queueLiveRuntimeSync();
  }

  void undo() {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available || !canUndo) return;
    _redoHistory.add(_OverlayWorkspaceDraft.fromProjection(current));
    _applyDraft(current, _undoHistory.removeLast());
    _lastHistoryKey = null;
  }

  void redo() {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available || !canRedo) return;
    _undoHistory.add(_OverlayWorkspaceDraft.fromProjection(current));
    _applyDraft(current, _redoHistory.removeLast());
    _lastHistoryKey = null;
  }

  Future<bool> save() {
    final current = _projection.value;
    if (!current.available || current.busy || !current.dirty) {
      return Future.value(false);
    }
    return _apply(
      OverlayWorkspaceMutation.saveActive(
        settings: current.settings!,
        layout: current.layout,
        renderMode: current.renderMode!,
        hotkey: current.hotkey!,
      ),
      OverlayWorkspaceOperation.saving,
    );
  }

  Future<bool> refreshRuntime(String language) => _executeRuntime(
    OverlayRuntimeAction.getState,
    OverlayRuntimeOperation.reading,
    language,
  );

  Future<bool> openRuntime(String language) => _executeRuntime(
    OverlayRuntimeAction.open,
    OverlayRuntimeOperation.opening,
    language,
  );

  Future<bool> closeRuntime(String language) => _executeRuntime(
    OverlayRuntimeAction.close,
    OverlayRuntimeOperation.closing,
    language,
  );

  Future<bool> retryRuntime(String language) => _executeRuntime(
    OverlayRuntimeAction.retry,
    OverlayRuntimeOperation.retrying,
    language,
  );

  Future<bool> activatePreset(String presetId) => _apply(
    OverlayWorkspaceMutation.activatePreset(presetId),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> createPreset(String name) => _apply(
    OverlayWorkspaceMutation.createPreset(name),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> duplicatePreset(String presetId, String name) => _apply(
    OverlayWorkspaceMutation.duplicatePreset(presetId, name),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> renamePreset(String presetId, String name) => _apply(
    OverlayWorkspaceMutation.renamePreset(presetId, name),
    OverlayWorkspaceOperation.presetAction,
    preserveDraft: true,
  );

  Future<bool> deletePreset(String presetId) => _apply(
    OverlayWorkspaceMutation.deletePreset(presetId),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> resetPreset(String presetId) => _apply(
    OverlayWorkspaceMutation.resetPreset(presetId),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> importPreset({
    required String name,
    required OverlayWorkspaceSettings settings,
    required List<OverlayWorkspaceLayoutItem> layout,
  }) => _apply(
    OverlayWorkspaceMutation.importPreset(
      name: name,
      settings: settings,
      layout: layout,
    ),
    OverlayWorkspaceOperation.presetAction,
  );

  Future<bool> _apply(
    OverlayWorkspaceMutation mutation,
    OverlayWorkspaceOperation operation, {
    bool preserveDraft = false,
  }) async {
    final current = _projection.value;
    final revision = current.snapshot?.revision;
    if (_disposed || current.busy || !current.available || revision == null) {
      return false;
    }
    _projection.value = current.copyWith(
      operation: operation,
      clearFailure: true,
    );
    final result = await _port.apply(mutation, expectedRevision: revision);
    if (_disposed) return false;
    if (result.completed) {
      if (!preserveDraft) _resetHistory();
      final runtime = await _port.executeRuntime(
        OverlayRuntimeAction.getState,
        language: _runtimeLanguage,
      );
      if (_disposed) return false;
      final updated = OverlayWorkspaceProjection.fromSnapshot(
        result.snapshot!,
        runtime: runtime,
      );
      _projection.value = preserveDraft
          ? updated.copyWith(
              settings: current.settings,
              layout: current.layout,
              renderMode: current.renderMode,
              hotkey: current.hotkey,
              dirty: current.dirty,
            )
          : updated;
      if (preserveDraft) _queueLiveRuntimeSync();
      return true;
    }
    _projection.value = current.copyWith(
      operation: OverlayWorkspaceOperation.none,
      failure: result.failure ?? OverlaySettingsFailure.writeFailed,
    );
    _lastHistoryKey = null;
    return false;
  }

  Future<bool> _executeRuntime(
    OverlayRuntimeAction action,
    OverlayRuntimeOperation operation,
    String language,
  ) async {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return false;
    _runtimeLanguage = language;
    if (action == OverlayRuntimeAction.close) _liveSyncRequested = false;
    _projection.value = current.copyWith(runtimeOperation: operation);
    final runtime = await _port.executeRuntime(
      action,
      language: language,
      draft: action == OverlayRuntimeAction.close
          ? null
          : _runtimeDraft(current),
    );
    if (_disposed) return false;
    _projection.value = _projection.value.copyWith(
      runtimeOperation: OverlayRuntimeOperation.none,
      runtime: runtime,
    );
    return runtime.available && !runtime.failed;
  }

  void _recordChange(
    OverlayWorkspaceProjection current, {
    required String key,
    required bool coalesce,
  }) {
    if (!coalesce || _lastHistoryKey != key) {
      if (_undoHistory.length == 100) {
        _undoHistory.removeAt(0);
      }
      _undoHistory.add(_OverlayWorkspaceDraft.fromProjection(current));
    }
    _redoHistory.clear();
    _lastHistoryKey = coalesce ? key : null;
  }

  void _applyDraft(
    OverlayWorkspaceProjection current,
    _OverlayWorkspaceDraft draft,
  ) {
    _projection.value = current.copyWith(
      settings: draft.settings,
      layout: draft.layout,
      renderMode: draft.renderMode,
      hotkey: draft.hotkey,
      clearFailure: true,
      dirty: draft.dirty,
    );
    _queueLiveRuntimeSync();
  }

  OverlayWorkspaceRuntimeDraft? _runtimeDraft(
    OverlayWorkspaceProjection projection,
  ) {
    final revision = projection.snapshot?.revision;
    if (!projection.available || revision == null) return null;
    return OverlayWorkspaceRuntimeDraft(
      expectedRevision: revision,
      settings: projection.settings!,
      layout: projection.layout,
      hotkey: projection.hotkey!,
    );
  }

  void _queueLiveRuntimeSync() {
    final current = _projection.value;
    if (_disposed || !current.available || !current.runtime.isVisible) return;
    _liveSyncRequested = true;
    if (!_liveSyncInFlight) unawaited(_drainLiveRuntimeSync());
  }

  Future<void> _drainLiveRuntimeSync() async {
    if (_liveSyncInFlight || _disposed) return;
    _liveSyncInFlight = true;
    try {
      while (_liveSyncRequested && !_disposed) {
        _liveSyncRequested = false;
        final current = _projection.value;
        if (!current.available || !current.runtime.isVisible) break;
        final runtime = await _port.executeRuntime(
          OverlayRuntimeAction.getState,
          language: _runtimeLanguage,
          draft: _runtimeDraft(current),
        );
        if (_disposed) return;
        _projection.value = _projection.value.copyWith(runtime: runtime);
      }
    } finally {
      _liveSyncInFlight = false;
      if (_liveSyncRequested && !_disposed) _queueLiveRuntimeSync();
    }
  }

  void _resetHistory() {
    _undoHistory.clear();
    _redoHistory.clear();
    _lastHistoryKey = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _liveSyncRequested = false;
    _projection.dispose();
    _port.close();
  }
}

@immutable
final class _OverlayWorkspaceDraft {
  const _OverlayWorkspaceDraft({
    required this.settings,
    required this.layout,
    required this.renderMode,
    required this.hotkey,
    required this.dirty,
  });

  factory _OverlayWorkspaceDraft.fromProjection(
    OverlayWorkspaceProjection projection,
  ) => _OverlayWorkspaceDraft(
    settings: projection.settings!,
    layout: List.unmodifiable(projection.layout),
    renderMode: projection.renderMode!,
    hotkey: projection.hotkey!,
    dirty: projection.dirty,
  );

  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final String renderMode;
  final OverlayWorkspaceHotkey hotkey;
  final bool dirty;
}
