import '../../platform/bridge/bridge_client_session.dart';
import 'overlay_settings_models.dart';
import 'overlay_preview_guide_port.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';
import 'overlay_appearance_configuration.dart';
import 'overlay_appearance_progress.dart';
import 'bridge_overlay_appearance_live_port.dart';
import 'overlay_appearance_live_session.dart';

final class BridgeOverlayWorkspaceAdapter
    implements
        OverlayWorkspacePort,
        OverlayPreviewGuidePort,
        OverlayAppearancePreviewPort,
        OverlayAppearanceProgressPort,
        OverlayAppearanceLivePort,
        OverlayAppearanceLiveAvailability,
        OverlayAppearanceLiveControlsPort,
        OverlayAppearanceLivePlaybackPort,
        OverlayAppearanceLivePlacementPort,
        OverlayAppearanceLiveOwnerEvents,
        OverlayRuntimeChangePort {
  BridgeOverlayWorkspaceAdapter(this._session);

  final BridgeClientSession _session;
  @override
  Future<bool> readPreviewGuideSeen() async {
    final response = await _session.request('applicationPreferences.get',
        payload: const {'schemaVersion': 1});
    final preferences = response.payload['preferences'];
    if (response.payload['storageState'] == 'recoveredDefaults' ||
        preferences is! Map ||
        preferences['appearancePreviewGuideSeen'] is! bool) {
      throw StateError('Preview guide preference unavailable.');
    }
    return preferences['appearancePreviewGuideSeen'] as bool;
  }

  @override
  Future<void> markPreviewGuideSeen() async {
    // Fresh revision; never rewrite a cached copy of unrelated preferences.
    final response = await _session.request('applicationPreferences.get',
        payload: const {'schemaVersion': 1});
    final values = response.payload['preferences'];
    if (response.payload['storageState'] == 'recoveredDefaults' ||
        values is! Map || values['appearancePreviewGuideSeen'] is! bool ||
        response.payload['revision'] is! int) {
      throw StateError('Preview guide preference unavailable.');
    }
    if (values['appearancePreviewGuideSeen'] == true) return;
    final saved = await _session.request('applicationPreferences.update', payload: {
      'schemaVersion': 1,
      'expectedRevision': response.payload['revision'],
      'patch': {'appearancePreviewGuideSeen': true},
    });
    final stored = saved.payload['preferences'];
    if (stored is! Map || stored['appearancePreviewGuideSeen'] != true) {
      throw StateError('Preview guide acknowledgement not confirmed.');
    }
  }
  late final BridgeOverlayAppearanceLivePort _livePreview =
      BridgeOverlayAppearanceLivePort(_session);
  @override
  Map<String, String> get placementStates => _livePreview.placementStates;
  @override
  bool get supportsLiveAppearancePreview => _livePreview.supported;
  @override
  Stream<void> get previewOwnerChanges => _livePreview.previewOwnerChanges;
  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame frame) =>
      _livePreview.openLivePreview(frame);
  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame frame,
  ) => _livePreview.updateLivePreview(id, revision, frame);
  @override
  Future<void> closeLivePreview(String id) => _livePreview.closeLivePreview(id);
  @override
  Future<int> renewLivePreview(String id, int revision) =>
      _livePreview.renewLivePreview(id, revision);
  @override
  Future<int> protectLivePreviewControls(
    String id,
    int revision,
    List<OverlayPreviewControlArea> areas,
  ) => _livePreview.protectLivePreviewControls(id, revision, areas);
  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback action,
  ) => _livePreview.playLivePreview(id, revision, action);

  @override
  bool get supportsAppearanceProgress =>
      _session.hostCapabilities.contains('overlay.appearanceProgress');
  @override
  Stream<void> get appearanceOwnerChanges => _session.events
      .where(
        (event) =>
            event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated',
      )
      .map((_) {});
  @override
  Future<OverlayAppearanceProgress> readAppearanceProgress(
    String appearanceId,
  ) async {
    if (!supportsAppearanceProgress) throw StateError('collection_unavailable');
    final response = await _session.request(
      'overlay.appearanceProgress.read',
      payload: {'schemaVersion': 1, 'appearanceId': appearanceId},
    );
    return OverlayAppearanceProgress.fromMap(
      response.payload,
      appearanceId: appearanceId,
    );
  }

  bool get _supported =>
      _session.hostCapabilities.contains('overlay.workspace');
  bool get _runtimeSupported =>
      _session.hostCapabilities.contains('overlay.runtime');

  @override
  bool get supportsRuntimeChanges =>
      _runtimeSupported &&
      _session.hostCapabilities.contains('overlay.runtimeEvents');
  // The session already drops other generations and out-of-order events. A
  // malformed payload is skipped; the next read or push supplies the state.
  @override
  Stream<OverlayRuntimeSnapshot> get runtimeChanges => _session.events
      .where((event) => event.name == 'overlay.runtime.changed')
      .expand((event) {
        try {
          return [OverlayRuntimeSnapshot.fromMap(event.payload)];
        } on Object {
          return const <OverlayRuntimeSnapshot>[];
        }
      });

  @override
  Future<String> openAppearancePreview(
    String appearanceId,
    OverlayAppearanceOptions options, {
    bool reduceMotion = false,
  }) async {
    if (!_session.hostCapabilities.contains('overlay.appearancePreview')) {
      throw StateError('preview_unavailable');
    }
    final response = await _session.request(
      'overlay.appearancePreview.open',
      payload: {
        'schemaVersion': 1,
        'appearanceId': appearanceId,
        'appearanceOptions': options.toMap(),
        'reduceMotion': reduceMotion,
      },
    );
    final id = response.payload['sessionId'];
    if (response.payload['schemaVersion'] != 1 ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid appearance preview session.');
    }
    return id;
  }

  @override
  Future<void> closeAppearancePreview(String sessionId) async {
    final response = await _session.request(
      'overlay.appearancePreview.close',
      payload: {'schemaVersion': 1, 'sessionId': sessionId},
    );
    if (response.payload['schemaVersion'] != 1 ||
        response.payload['closed'] != true) {
      throw const FormatException('Invalid appearance preview close.');
    }
  }

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
    final sourcePresetsEnabled = body['sourcePresetsEnabled'] ?? false;
    final appearanceOptionsEnabled =
        body.containsKey('appearanceOptionsEnabled')
        ? body['appearanceOptionsEnabled']
        : false;
    final removedOrganizationBindings =
        body['removedOrganizationBindings'] ?? false;
    if (body['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        storageState is! String ||
        activePresetId is! String ||
        activePresetId.isEmpty ||
        renderMode is! String ||
        renderMode.isEmpty ||
        sourcePresetsEnabled is! bool ||
        appearanceOptionsEnabled is! bool ||
        removedOrganizationBindings is! bool) {
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
    final presetMaps = objectList(body['presets']).map(stringMap).toList();
    if (appearanceOptionsEnabled &&
        (!body.containsKey('appearanceOptions') ||
            presetMaps.any(
              (preset) => !preset.containsKey('appearanceOptions'),
            ))) {
      throw const FormatException('Missing enabled appearance options.');
    }
    final appearanceOptions = body.containsKey('appearanceOptions')
        ? OverlayAppearanceOptions.fromMap(stringMap(body['appearanceOptions']))
        : const OverlayAppearanceOptions.empty();
    final presets = presetMaps
        .map(OverlayWorkspacePreset.fromMap)
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
    if (appearanceOptionsEnabled &&
        active.single.appearanceOptions != appearanceOptions) {
      throw const FormatException('Inconsistent active appearance options.');
    }
    if (sourcePresetsEnabled &&
        presets.any((p) => p.sources == null && p.storageState != 'corrupt')) {
      throw const FormatException('Missing enabled source policy.');
    }
    return OverlayWorkspaceSnapshot.available(
      revision: revision,
      storageState: storageState,
      activePresetId: activePresetId,
      renderMode: renderMode,
      appearances: appearances,
      livePreviewAppearanceIds: _livePreviewIds(
        body['livePreviewAppearanceIds'],
        appearances,
      ),
      hotkey: hotkey,
      settings: settings,
      layout: layout,
      presets: presets,
      sourcePresetsEnabled: sourcePresetsEnabled,
      removedOrganizationBindings: removedOrganizationBindings,
      appearanceOptionsEnabled: appearanceOptionsEnabled,
      appearanceOptions: appearanceOptions,
      appearanceConfigurations: _configurations(
        body['appearanceConfigurations'],
      ),
      appearanceProgressIds: _progressIds(
        body['appearanceProgressIds'],
        appearances,
      ),
    );
  }

  static List<OverlayAppearanceConfiguration> _configurations(Object? value) {
    if (value == null) return const [];
    try {
      final items = objectList(value);
      if (items.length > 8) return const [];
      final result = items
          .map((v) => OverlayAppearanceConfiguration.fromMap(stringMap(v)))
          .toList();
      if (result.map((c) => c.profileId).toSet().length != result.length) {
        return const [];
      }
      return List.unmodifiable(result);
    } on FormatException {
      return const [];
    }
  }

  static Set<String> _livePreviewIds(
    Object? value,
    List<OverlayWorkspaceAppearance> appearances,
  ) {
    if (value == null) return const {};
    if (value is! List ||
        value.length > 8 ||
        value.any((v) => v is! String) ||
        value.toSet().length != value.length) {
      return const {};
    }
    final allowed = appearances
        .where((a) => a.isPreviewAvailable)
        .map((a) => a.id)
        .toSet();
    if (value.any((v) => !allowed.contains(v))) return const {};
    return Set.unmodifiable(value.cast<String>());
  }

  static Set<String> _progressIds(
    Object? value,
    List<OverlayWorkspaceAppearance> appearances,
  ) {
    if (value is! List ||
        value.length > 8 ||
        value.any(
          (id) =>
              id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id),
        ) ||
        value.toSet().length != value.length) {
      return const {};
    }
    return Set.unmodifiable(
      value.whereType<String>().where(
        (id) => appearances.any((a) => a.id == id),
      ),
    );
  }

  static OverlaySettingsFailure _map(Object error, {bool writing = false}) {
    if (error is FormatException) return OverlaySettingsFailure.invalidResponse;
    if (error is BridgeRemoteException) {
      if (error.code == 'overlay.workspace_version_unsupported') {
        return OverlaySettingsFailure.versionUnsupported;
      }
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
