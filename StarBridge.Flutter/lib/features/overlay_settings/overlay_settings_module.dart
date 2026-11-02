import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/diagnostics/loading_read_scope.dart';

import '../../platform/window/overlay_editor_window_port.dart';
import '../../platform/window/menu_preview_window_port.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'menu_settings_draft.dart';

import 'overlay_preview_identity.dart';
import 'overlay_scene_controller.dart';
import 'overlay_preset_auto_switch.dart';
import 'overlay_source_selection_coordinator.dart';
import 'overlay_roster_editor.dart';
import 'overlay_settings_models.dart';
import 'overlay_settings_port.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_port.dart';

final class OverlaySettingsModule {
  OverlaySettingsModule(
    this._port, {
    OverlayWorkspacePort? workspacePort,
    OverlayEditorWindowPort editorWindow =
        const UnavailableOverlayEditorWindow(),
    ValueListenable<OverlayPreviewIdentity?>? previewIdentity,
    this.scenes,
    this.roster,
    this.menuPreview,
    this.languageChanges,
    this.language,
    Stream<void>? hostInvalidations,
  }) : workspace = workspacePort == null
           ? null
           : OverlayWorkspaceModule(
               workspacePort,
               editorWindow: editorWindow,
               previewIdentity: previewIdentity,
               sourceScenes: scenes?.projection,
             ) {
    if (menuPreview case MenuWindowPreferencesProvider provider) {
      final port = provider.menuPreferences;
      if (port != null) menuDraft = MenuSettingsDraft(port);
    }
    if (workspace != null && scenes != null) {
      _sourceSelection = OverlaySourceSelectionCoordinator(workspace!, scenes!);
      _presetAutoSwitch = OverlayPresetAutoSwitch(
        workspace!,
        scenes!.projection,
      );
    }
    _lastLanguage = language?.call();
    languageChanges?.addListener(_onLanguage);
    _invalidations = hostInvalidations?.listen((_) => resynchronize());
  }

  final Listenable? languageChanges;
  final Object? Function()? language;
  Object? _lastLanguage;
  StreamSubscription<void>? _invalidations;

  void _onLanguage() {
    final next = language?.call();
    if (next == _lastLanguage) return;
    _lastLanguage = next;
    resynchronize();
  }

  /// One read while the tray or settings page watches: language change and
  /// Host invalidation. Runtime facts otherwise arrive as pushes.
  void resynchronize() {
    if (_disposed || _observers == 0) return;
    unawaited(backgroundLoadingRead(synchronize));
  }

  /// Host pushes `overlay.runtime.changed`; older Hosts keep the poll.
  bool get _runtimePushed => workspace?.supportsRuntimeChanges ?? false;

  OverlayPresetAutoSwitch? _presetAutoSwitch;
  OverlaySourceSelectionCoordinator? _sourceSelection;

  final OverlaySettingsPort _port;
  final MenuPreviewWindowPort? menuPreview;
  MenuSettingsDraft? menuDraft;
  final OverlaySceneController? scenes;
  final OverlayRosterPort? roster;
  final OverlayWorkspaceModule? workspace;
  final ValueNotifier<OverlaySettingsProjection> _projection = ValueNotifier(
    const OverlaySettingsProjection.loading(),
  );
  bool _disposed = false;
  bool _busy = false;
  int _observers = 0;
  Timer? _refreshTimer;

  // Shared by the tray and settings page; neither owns a second settings copy.
  // Each watch (settings page entry, tray) reads once. With runtime pushes no
  // timer runs; on an older Host the 10 s poll remains the fallback.
  VoidCallback watch() {
    if (_disposed) return () {};
    _observers++;
    unawaited(backgroundLoadingRead(synchronize));
    if (!_runtimePushed) {
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 10), (timer) {
        // Capabilities can arrive after the watch started.
        if (_runtimePushed) {
          timer.cancel();
          if (identical(_refreshTimer, timer)) _refreshTimer = null;
          return;
        }
        unawaited(backgroundLoadingRead(synchronize));
      });
    }
    bool released = false;
    return () {
      if (released) return;
      released = true;
      if (--_observers == 0) {
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    };
  }

  Future<void> synchronize() async {
    if (_disposed) return;
    if (workspace case final workspace?) {
      await workspace.synchronize();
    } else {
      await refresh(silent: true);
    }
  }

  ValueListenable<OverlaySettingsProjection> get projection => _projection;

  Future<void> initialize() async {
    if (menuPreview case final MenuWindowStartupPort startup) {
      startup.initialize();
    }
    final futures = <Future<void>>[refresh()];
    if (workspace != null) futures.add(workspace!.initialize());
    await Future.wait(futures);
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _busy) return;
    _busy = true;
    if (!silent) _projection.value = const OverlaySettingsProjection.loading();
    try {
      final snapshot = await _port.read();
      if (!_disposed) {
        _projection.value = OverlaySettingsProjection.fromSnapshot(snapshot);
      }
    } on Object {
      if (!_disposed && _projection.value.settings == null) {
        _projection.value = OverlaySettingsProjection.fromSnapshot(
          const OverlaySettingsSnapshot.unavailable(
            failure: OverlaySettingsFailure.readFailed,
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<bool> save(OverlaySettingsValue settings) async {
    final current = _projection.value;
    if (_disposed || _busy || !current.canEdit || current.revision == null) {
      return false;
    }
    _busy = true;
    _projection.value = current.copyWith(
      operation: OverlaySettingsOperation.saving,
      clearFailure: true,
    );
    final result = await _port.update(
      settings,
      expectedRevision: current.revision!,
    );
    if (_disposed) return false;
    _busy = false;
    if (result.completed) {
      _projection.value = OverlaySettingsProjection.fromSnapshot(
        result.snapshot!,
      );
      return true;
    }
    _projection.value = current.copyWith(
      operation: OverlaySettingsOperation.none,
      failure: result.failure ?? OverlaySettingsFailure.writeFailed,
    );
    return false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    menuDraft?.dispose();
    _presetAutoSwitch?.dispose();
    _sourceSelection?.dispose();
    if (menuPreview case final MenuLiveWindowPort menu) menu.dispose();
    _refreshTimer?.cancel();
    languageChanges?.removeListener(_onLanguage);
    unawaited(_invalidations?.cancel());
    _projection.dispose();
    _port.close();
    workspace?.dispose();
    scenes?.dispose();
  }
}
