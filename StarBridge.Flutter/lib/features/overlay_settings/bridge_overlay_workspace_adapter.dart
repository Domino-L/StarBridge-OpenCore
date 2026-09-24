import '../../platform/bridge/bridge_client_session.dart';
import 'overlay_settings_models.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';

final class BridgeOverlayWorkspaceAdapter implements OverlayWorkspacePort {
  BridgeOverlayWorkspaceAdapter(this._session);

  final BridgeClientSession _session;

  bool get _supported =>
      _session.hostCapabilities.contains('overlay.workspace');
  bool get _runtimeSupported =>
      _session.hostCapabilities.contains('overlay.runtime');

  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    if (!_supported) return const OverlayWorkspaceSnapshot.unavailable();
    try {
      final response = await _session.request(
        'overlay.getWorkspace',
        payload: const {'schemaVersion': 1},
      );
      return _parse(response.payload);
    } on Object catch (error) {
      return OverlayWorkspaceSnapshot.unavailable(failure: _map(error));
    }
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    if (!_supported) {
      return const OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.hostUnavailable,
      );
    }
    try {
      final response = await _session.request(
        'overlay.updateWorkspace',
        payload: mutation.toPayload(expectedRevision),
      );
      return OverlayWorkspaceWriteResult.completed(_parse(response.payload));
    } on Object catch (error) {
      return OverlayWorkspaceWriteResult.failed(_map(error, writing: true));
    }
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    if (!_runtimeSupported) {
      return const OverlayRuntimeSnapshot.unavailable();
    }
    final name = switch (action) {
      OverlayRuntimeAction.getState => 'overlay.runtime.getState',
      OverlayRuntimeAction.open => 'overlay.runtime.open',
      OverlayRuntimeAction.close => 'overlay.runtime.close',
      OverlayRuntimeAction.retry => 'overlay.runtime.retry',
    };
    try {
      final response = await _session.request(
        name,
        payload: {
          'schemaVersion': 1,
          'language': language,
          if (draft != null) 'workspace': draft.toMap(),
        },
      );
      return OverlayRuntimeSnapshot.fromMap(response.payload);
    } on BridgeTimeoutException {
      return const OverlayRuntimeSnapshot.unavailable(
        failureCode: 'overlay.runtime_start_timeout',
      );
    } on BridgeClientException {
      return const OverlayRuntimeSnapshot.unavailable();
    } on Object {
      return const OverlayRuntimeSnapshot.unavailable(
        failureCode: 'overlay.runtime_invalid_response',
      );
    }
  }

  static OverlayWorkspaceSnapshot _parse(Map<String, Object?> body) {
    final revision = body['revision'];
    final storageState = body['storageState'];
    final activePresetId = body['activePresetId'];
    final renderMode = body['renderMode'];
    if (body['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        storageState is! String ||
        activePresetId is! String ||
        activePresetId.isEmpty ||
        renderMode is! String ||
        renderMode.isEmpty) {
      throw const FormatException('Invalid overlay workspace response.');
    }
    final settings = OverlayWorkspaceSettings.fromMap(
      stringMap(body['settings']),
    );
    final appearances = objectList(body['appearances'])
        .map((item) => OverlayWorkspaceAppearance.fromMap(stringMap(item)))
        .toList(growable: false);
    final hotkey = OverlayWorkspaceHotkey.fromMap(stringMap(body['hotkey']));
    final layout = objectList(body['layout'])
        .map((item) => OverlayWorkspaceLayoutItem.fromMap(stringMap(item)))
        .toList(growable: false);
    final presets = objectList(body['presets'])
        .map((item) => OverlayWorkspacePreset.fromMap(stringMap(item)))
        .toList(growable: false);
    final active = presets.where((preset) => preset.isActive).toList();
    if (layout.isEmpty ||
        presets.isEmpty ||
        appearances.isEmpty ||
        appearances.map((appearance) => appearance.id).toSet().length !=
            appearances.length ||
        appearances
                .where(
                  (appearance) =>
                      appearance.id == 'Default' && appearance.isAvailable,
                )
                .length !=
            1 ||
        active.length != 1 ||
        active.single.id != activePresetId) {
      throw const FormatException('Invalid overlay workspace state.');
    }
    return OverlayWorkspaceSnapshot.available(
      revision: revision,
      storageState: storageState,
      activePresetId: activePresetId,
      renderMode: renderMode,
      appearances: appearances,
      hotkey: hotkey,
      settings: settings,
      layout: layout,
      presets: presets,
    );
  }

  static OverlaySettingsFailure _map(Object error, {bool writing = false}) {
    if (error is FormatException) return OverlaySettingsFailure.invalidResponse;
    if (error is BridgeRemoteException) {
      if (error.code == 'overlay.workspace_revision_conflict') {
        return OverlaySettingsFailure.writeConflict;
      }
      if (error.code == 'overlay.workspace_write_failed') {
        return OverlaySettingsFailure.writeFailed;
      }
      if (error.code == 'overlay.workspace_read_failed') {
        return OverlaySettingsFailure.readFailed;
      }
      if (error.code.startsWith('overlay.workspace_invalid_') ||
          error.code == 'overlay.workspace_duplicate_name' ||
          error.code == 'overlay.workspace_preset_not_found' ||
          error.code == 'overlay.workspace_last_preset') {
        return OverlaySettingsFailure.invalidValue;
      }
      return writing
          ? OverlaySettingsFailure.writeFailed
          : OverlaySettingsFailure.invalidResponse;
    }
    if (error is BridgeClientException) {
      return OverlaySettingsFailure.hostUnavailable;
    }
    return OverlaySettingsFailure.invalidResponse;
  }

  @override
  Future<void> close() async {}
}
