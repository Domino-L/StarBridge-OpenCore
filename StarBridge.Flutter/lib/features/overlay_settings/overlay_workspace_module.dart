import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/window/overlay_editor_window_port.dart';

import 'overlay_preview_identity.dart';
import 'overlay_preview_guide_port.dart';
import 'overlay_scene_controller.dart';
import 'overlay_settings_models.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';
import 'overlay_workspace_port_capabilities.dart';
import 'overlay_workspace_runtime_sync.dart';
import 'overlay_workspace_auto_save.dart';
import 'overlay_workspace_commit.dart';
import 'overlay_experience_presets.dart';
import 'overlay_appearance_progress.dart';
import 'overlay_appearance_live_session.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_projection.dart';
import 'overlay_workspace_draft.dart';

export 'overlay_workspace_projection.dart';

final class OverlayWorkspaceModule {
  OverlayWorkspaceModule(
    this._port, {
    this.editorWindow = const UnavailableOverlayEditorWindow(),
    this.previewIdentity,
    this.sourceScenes,
  }) {
    _pushes = OverlayRuntimePushes(_port, apply: _applyPushedRuntime);
  }

  final OverlayEditorWindowPort editorWindow;
  final ValueListenable<OverlayPreviewIdentity?>? previewIdentity;
  final ValueListenable<OverlaySceneState>? sourceScenes;

  final OverlayWorkspacePort _port;
  final _qualificationUnknown = ValueNotifier(false);
  ValueListenable<bool> get appearanceQualificationUnknown =>
      _qualificationUnknown;
  void setAppearanceQualificationUnknown(bool value) {
    if (!_disposed) _qualificationUnknown.value = value;
  }

  OverlayPreviewGuidePort? get previewGuidePort => _port.previewGuide;
  OverlayAppearanceLivePort? get appearanceLivePort => _port.appearanceLive;
  OverlayAppearanceProgressPort? get appearanceProgressPort =>
      _port.appearanceProgress;
  OverlayAppearancePreviewPort? get appearancePreviewPort =>
      _port.appearancePreview;
  final ValueNotifier<OverlayWorkspaceProjection> _projection = ValueNotifier(
    const OverlayWorkspaceProjection.loading(),
  );
  bool _disposed = false;
  bool _refreshing = false;
  late final _liveSync = OverlayLiveRuntimeSync(
    canSync: () {
      final current = _projection.value;
      return !_disposed && current.available && current.runtime.enabled;
    },
    round: _liveRuntimeRound,
  );
  late final OverlayRuntimePushes _pushes;
  late final _autoSave = OverlayWorkspaceAutoSave(commit: _commitDraft);
  final List<OverlayWorkspaceDraft> _undoHistory = [];
  final List<OverlayWorkspaceDraft> _redoHistory = [];
  String? _lastHistoryKey;
  String _runtimeLanguage = 'zh';
  String get runtimeLanguage => _runtimeLanguage;
  int _manualPresetSelection = 0;
  int get manualPresetSelection => _manualPresetSelection;

  ValueListenable<OverlayWorkspaceProjection> get projection => _projection;

  /// The Host pushes runtime changes (`overlay.runtime.changed`), so callers
  /// can read once on open instead of polling. False on an older Host.
  bool get supportsRuntimeChanges => _pushes.supported;
  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  Future<void> initialize() => refresh();

  /// Renew local workspace/runtime facts without blanking the page, discarding
  /// a draft, or replaying an open/close/save command after an uncertain result.
  Future<void> synchronize() async {
    if (_disposed ||
        _refreshing ||
        _projection.value.busy ||
        _projection.value.dirty ||
        _autoSave.pending) {
      return;
    }
    _refreshing = true;
    final before = _projection.value;
    try {
      final snapshot = await _port.read();
      final latest = _projection.value;
      if (_disposed) return;
      if (!OverlayRuntimePushes.sameExceptRuntime(before, latest)) return;
      if (snapshot.availability != OverlayWorkspaceAvailability.available) {
        if (!before.available) {
          _projection.value = OverlayWorkspaceProjection.fromSnapshot(snapshot);
        }
        return;
      }
      if (snapshot.revision != before.snapshot?.revision) _resetHistory();
      _projection.value = OverlayWorkspaceProjection.fromSnapshot(
        snapshot,
        runtime: latest.runtime,
      );
      final current = _projection.value;
      // A push during this read changes identity, so the push wins below.
      final runtime = await _port.executeRuntime(
        OverlayRuntimeAction.getState,
        language: _runtimeLanguage,
        draft: current.runtimeDraft,
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
    if (_projection.value.dirty && !await save()) return;
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
          final pushes = _pushes.mark;
          final runtime = await _port.executeRuntime(
            OverlayRuntimeAction.getState,
            language: _runtimeLanguage,
          );
          if (!_disposed) {
            _projection.value = _projection.value.copyWith(
              runtimeOperation: OverlayRuntimeOperation.none,
              runtime: _pushes.unchangedSince(pushes) ? runtime : null,
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
      _edited();
    } on Object {
      _projection.value = current.copyWith(
        failure: OverlaySettingsFailure.invalidValue,
      );
    }
  }

  void updateModuleSource(
    OverlaySourceModule module,
    OverlaySourceBinding binding,
  ) => _updateSources(
    (sources) => sources.withModule(module, binding),
    'source:${module.name}',
  );

  /// Every module shows the shared choice again; the plan's fixed source and
  /// automatic use are untouched (released only from the source pickers).
  void followSharedSourceInModules() => _updateSources(
    (sources) => OverlayPresetSources(
      binding: sources.binding,
      autoSwitch: sources.autoSwitch,
    ),
    'source:modules',
  );

  void _updateSources(
    OverlayPresetSources Function(OverlayPresetSources sources) change,
    String key,
  ) {
    final current = _projection.value;
    if (_disposed ||
        current.busy ||
        !current.available ||
        current.snapshot?.sourcePresetsEnabled != true ||
        current.sources == null) {
      return;
    }
    final next = change(current.sources!);
    if (next == current.sources) return;
    _recordChange(current, key: key, coalesce: false);
    _projection.value = current.copyWith(
      sources: next,
      dirty: true,
      clearFailure: true,
    );
    _edited();
  }

  /// Edits presentation values through the same draft/revision/history owner
  /// as settings and layout. This does not select a skin or grant access to it.
  void updateAppearanceOptions(OverlayAppearanceOptions options) {
    final current = _projection.value;
    if (_disposed ||
        current.busy ||
        !current.available ||
        current.snapshot?.appearanceOptionsEnabled != true ||
        current.snapshot?.storageState == 'corrupt' ||
        current.snapshot!.presets.any(
          (preset) => preset.isActive && preset.storageState == 'corrupt',
        ) ||
        options == current.appearanceOptions) {
      return;
    }
    _recordChange(current, key: 'appearanceOptions', coalesce: false);
    _projection.value = current.copyWith(
      appearanceOptions: options,
      dirty: true,
      clearFailure: true,
    );
    _edited();
  }

  void updateChatSources(List<OverlaySourceBinding> sources) =>
      _updateSources((value) => value.withChatSources(sources), 'source:chat');

  void applyExperiencePreset(String preset) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final values = overlayExperiencePresets[preset];
    if (values == null) return;
    try {
      final next = values.entries.fold(
        current.settings!,
        (next, entry) =>
            applyOverlayWorkspaceSettingChange(next, entry.key, entry.value),
      );
      _recordChange(current, key: 'setting:experiencePreset', coalesce: false);
      _projection.value = current.copyWith(
        settings: next,
        clearFailure: true,
        dirty: true,
      );
      _edited();
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
      _edited();
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
    _edited();
  }

  void updateHotkey({String? binding, bool? enabled, bool? registerHotKey}) {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available) return;
    final value = current.hotkey!;
    _recordChange(
      current,
      key: binding != null
          ? 'hotkey:binding'
          : registerHotKey != null
          ? 'hotkey:registerHotKey'
          : 'hotkey:enabled',
      coalesce: binding != null,
    );
    _projection.value = current.copyWith(
      hotkey: OverlayWorkspaceHotkey(
        binding: binding ?? value.binding,
        enabled: enabled ?? value.enabled,
        runtimeState: value.runtimeState,
        registerHotKey: registerHotKey ?? value.registerHotKey,
      ),
      clearFailure: true,
      dirty: true,
    );
    _edited();
  }

  void discardChanges() {
    final snapshot = _projection.value.snapshot;
    if (_disposed || snapshot == null || _projection.value.busy) return;
    _autoSave.cancel();
    _resetHistory();
    _projection.value = OverlayWorkspaceProjection.fromSnapshot(
      snapshot,
      runtime: _projection.value.runtime,
    );
    _edited();
  }

  void undo() {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available || !canUndo) return;
    _redoHistory.add(OverlayWorkspaceDraft.fromProjection(current));
    _applyDraft(current, _undoHistory.removeLast());
    _lastHistoryKey = null;
  }

  void redo() {
    final current = _projection.value;
    if (_disposed || current.busy || !current.available || !canRedo) return;
    _undoHistory.add(OverlayWorkspaceDraft.fromProjection(current));
    _applyDraft(current, _redoHistory.removeLast());
    _lastHistoryKey = null;
  }

  /// Edits save on their own; this writes anything still pending now.
  Future<bool> save() => _autoSave.flush();

  /// In-game placement is an explicit session: Done saves, Cancel restores.
  void holdCommits() => _autoSave.hold();
  void releaseCommits() => _autoSave.release();

  void _edited() {
    _liveSync.request();
    if (_projection.value.dirty) _autoSave.schedule();
  }

  Future<bool> _commitDraft() => commitOverlayDraft(
    port: _port,
    read: () => _projection.value,
    write: (value) => _projection.value = value,
    disposed: () => _disposed,
    resetHistory: _resetHistory,
  );

  Future<bool> selectTemporarySource(
    OverlaySourceBinding choice,
    String ownerKey,
  ) {
    final current = _projection.value;
    final draft = current.runtimeDraft;
    if (current.snapshot?.sourcePresetsEnabled != true || draft == null) {
      return Future.value(false);
    }
    return _apply(
      OverlayWorkspaceMutation.temporarySource(
        ownerKey: ownerKey,
        sources: OverlayPresetSources(binding: choice),
        draft: draft,
      ),
      OverlayWorkspaceOperation.presetAction,
      preserveDraft: true,
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

  Future<bool> activatePreset(String presetId) {
    if (_disposed || _projection.value.busy || !_projection.value.available) {
      return Future.value(false);
    }
    _manualPresetSelection++;
    return _activatePreset(presetId);
  }

  // Automatic commands cannot consume drafts. The same revision-checked Host
  // mutation is used; there is no second store or optimistic activation.
  Future<bool> activatePresetAutomatically(
    String presetId, {
    required String ownerKey,
    required int generation,
    required String source,
  }) {
    final current = _projection.value;
    if (current.dirty || current.snapshot?.sourcePresetsEnabled != true) {
      return Future.value(false);
    }
    return _apply(
      OverlayWorkspaceMutation.activatePresetAutomatically(
        presetId,
        ownerKey: ownerKey,
        generation: generation,
        source: source,
      ),
      OverlayWorkspaceOperation.presetAction,
    );
  }

  Future<bool> _activatePreset(String presetId) => _apply(
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

  Future<bool> configurePreset(
    String presetId,
    String name,
    OverlaySourceBinding binding,
    bool autoSwitch, {
    String? replaceAutoSwitchPresetId,
    int? expectedRevision,
  }) async {
    // Pending edits save first and the write is built from that saved plan,
    // so it never writes older module sources back over them.
    if (_projection.value.dirty && !await save()) return false;
    final current = _projection.value;
    final preset = current.snapshot?.presets
        .where((p) => p.id == presetId)
        .firstOrNull;
    if (current.snapshot?.sourcePresetsEnabled != true ||
        preset?.sources == null ||
        expectedRevision != null &&
            current.snapshot?.revision != expectedRevision) {
      return false;
    }
    return _apply(
      OverlayWorkspaceMutation.configurePresetSources(
        presetId,
        OverlayPresetSources(
          binding: binding,
          autoSwitch: autoSwitch,
          modules: preset!.sources!.modules,
          chatSources: preset.sources!.chatSources,
        ),
        name: name,
        replaceAutoSwitchPresetId: replaceAutoSwitchPresetId,
      ),
      OverlayWorkspaceOperation.presetAction,
      preserveDraft: true,
    );
  }

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
    OverlayPresetSources? sources,
  }) => _apply(
    OverlayWorkspaceMutation.importPreset(
      name: name,
      settings: settings,
      layout: layout,
      sources: sources,
    ),
    OverlayWorkspaceOperation.presetAction,
    preserveDraft: true,
  );

  Future<bool> _apply(
    OverlayWorkspaceMutation mutation,
    OverlayWorkspaceOperation operation, {
    bool preserveDraft = false,
  }) async {
    if (_projection.value.dirty && !await save()) return false;
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
      final updated = OverlayWorkspaceProjection.fromSnapshot(
        result.snapshot!,
        runtime: current.runtime,
      );
      var retainedSources = current.sources;
      if (mutation.kind ==
              OverlayWorkspaceMutationKind.configurePresetSources &&
          mutation.presetId == current.snapshot?.activePresetId &&
          updated.sources != null) {
        OverlayPresetSources? rebase(OverlayPresetSources? source) =>
            source == null
            ? null
            : OverlayPresetSources(
                binding: updated.sources!.binding,
                autoSwitch: updated.sources!.autoSwitch,
                modules: source.modules,
                chatSources: source.chatSources,
              );
        retainedSources = rebase(retainedSources);
        for (final history in [_undoHistory, _redoHistory]) {
          for (var i = 0; i < history.length; i++) {
            history[i] = history[i].withSources(rebase(history[i].sources));
          }
        }
      }
      final next = preserveDraft
          ? updated.copyWith(
              settings: current.settings,
              layout: current.layout,
              renderMode: current.renderMode,
              hotkey: current.hotkey,
              sources: retainedSources,
              appearanceOptions: current.appearanceOptions,
              dirty: current.dirty,
            )
          : updated;
      final pushes = _pushes.mark;
      final runtime = await _port.executeRuntime(
        OverlayRuntimeAction.getState,
        language: _runtimeLanguage,
        draft: preserveDraft ? next.runtimeDraft : null,
      );
      if (_disposed) return false;
      _projection.value = next.copyWith(
        runtime: _pushes.unchangedSince(pushes)
            ? runtime
            : _projection.value.runtime,
      );
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
    if (action == OverlayRuntimeAction.close) _liveSync.cancelPending();
    _projection.value = current.copyWith(runtimeOperation: operation);
    final pushes = _pushes.mark;
    final runtime = await _port.executeRuntime(
      action,
      language: language,
      draft: action == OverlayRuntimeAction.close ? null : current.runtimeDraft,
    );
    if (_disposed) return false;
    _projection.value = _projection.value.copyWith(
      runtimeOperation: OverlayRuntimeOperation.none,
      runtime: _pushes.unchangedSince(pushes) ? runtime : null,
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
      _undoHistory.add(OverlayWorkspaceDraft.fromProjection(current));
    }
    _redoHistory.clear();
    _lastHistoryKey = coalesce ? key : null;
  }

  void _applyDraft(
    OverlayWorkspaceProjection current,
    OverlayWorkspaceDraft draft,
  ) {
    _projection.value = draft.applyTo(current).copyWith(dirty: true);
    _edited();
  }

  Future<void> _liveRuntimeRound() async {
    final current = _projection.value;
    final pushes = _pushes.mark;
    final runtime = await _port.executeRuntime(
      OverlayRuntimeAction.getState,
      language: _runtimeLanguage,
      draft: current.runtimeDraft,
    );
    if (_disposed || !_pushes.unchangedSince(pushes)) return;
    _projection.value = _projection.value.copyWith(runtime: runtime);
  }

  // Runtime facts only: never touches the draft, history, revision or an
  // in-flight operation. Ignored until a workspace has been read.
  bool _applyPushedRuntime(OverlayRuntimeSnapshot runtime) {
    final current = _projection.value;
    if (_disposed || !current.available) return false;
    _projection.value = current.copyWith(runtime: runtime);
    return true;
  }

  void _resetHistory() {
    _undoHistory.clear();
    _redoHistory.clear();
    _lastHistoryKey = null;
  }

  void dispose() {
    if (_disposed) return;
    final last = _projection.value;
    final unsaved = last.dirty && last.snapshot?.revision != null;
    _disposed = true;
    _qualificationUnknown.dispose();
    _autoSave.close();
    _liveSync.close();
    _pushes.dispose();
    _projection.dispose();
    if (!unsaved) {
      _port.close();
      return;
    }
    // Closing must not lose an edit that was still waiting to be written.
    unawaited(
      _port
          .apply(
            overlaySaveMutation(last),
            expectedRevision: last.snapshot!.revision!,
          )
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(_port.close),
    );
  }
}
