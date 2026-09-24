import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/window/overlay_editor_window_port.dart';
import '../../platform/window/menu_preview_window_port.dart';

import 'overlay_preview_identity.dart';
import 'overlay_scene_controller.dart';
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
    this.menuPreview,
  }) : workspace = workspacePort == null
           ? null
           : OverlayWorkspaceModule(
               workspacePort,
               editorWindow: editorWindow,
               previewIdentity: previewIdentity,
             );

  final OverlaySettingsPort _port;
  final MenuPreviewWindowPort? menuPreview;
  final OverlaySceneController? scenes;
  final OverlayWorkspaceModule? workspace;
  final ValueNotifier<OverlaySettingsProjection> _projection = ValueNotifier(
    const OverlaySettingsProjection.loading(),
  );
  bool _disposed = false;
  bool _busy = false;
  int _observers = 0;
  Timer? _refreshTimer;

  // Shared by the tray and settings page; neither owns a second settings copy.
  VoidCallback watch() {
    if (_disposed) return () {};
    _observers++;
    unawaited(synchronize());
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(synchronize());
    });
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
    if (menuPreview case final MenuLiveWindowPort menu) menu.dispose();
    _refreshTimer?.cancel();
    _projection.dispose();
    _port.close();
    workspace?.dispose();
    scenes?.dispose();
  }
}
