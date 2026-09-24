import '../../platform/bridge/bridge_client_session.dart';
import 'overlay_settings_models.dart';
import 'overlay_settings_port.dart';

final class BridgeOverlaySettingsAdapter implements OverlaySettingsPort {
  BridgeOverlaySettingsAdapter(this._session);

  final BridgeClientSession _session;

  bool get _supported => _session.hostCapabilities.contains('overlay.settings');

  @override
  Future<OverlaySettingsSnapshot> read() async {
    if (!_supported) return const OverlaySettingsSnapshot.unavailable();
    try {
      final response = await _session.request(
        'overlay.getState',
        payload: const {'schemaVersion': 1},
      );
      return _parse(response.payload);
    } on Object catch (error) {
      return OverlaySettingsSnapshot.unavailable(failure: _map(error, false));
    }
  }

  @override
  Future<OverlaySettingsWriteResult> update(
    OverlaySettingsValue settings, {
    required int expectedRevision,
  }) async {
    if (!_supported) {
      return const OverlaySettingsWriteResult.failed(
        OverlaySettingsFailure.hostUnavailable,
      );
    }
    try {
      final response = await _session.request(
        'overlay.update',
        payload: {
          'schemaVersion': 1,
          'expectedRevision': expectedRevision,
          'settings': {
            'enabled': settings.enabled,
            'opacity': settings.opacity,
            'position': settings.position.name,
            'showTeam': settings.showTeam,
          },
        },
      );
      return OverlaySettingsWriteResult.completed(_parse(response.payload));
    } on Object catch (error) {
      return OverlaySettingsWriteResult.failed(_map(error, true));
    }
  }

  static OverlaySettingsSnapshot _parse(Map<String, Object?> body) {
    final settings = body['settings'];
    final revision = body['revision'];
    final windowState = body['windowState'];
    if (body['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        settings is! Map<String, Object?> ||
        windowState is! String ||
        !const {'unavailable', 'ready', 'visible'}.contains(windowState)) {
      throw const FormatException('Invalid overlay response.');
    }
    final enabled = settings['enabled'];
    final opacity = settings['opacity'];
    final position = settings['position'];
    final showTeam = settings['showTeam'];
    if (enabled is! bool ||
        opacity is! num ||
        opacity < 0.35 ||
        opacity > 1 ||
        position is! String ||
        showTeam is! bool) {
      throw const FormatException('Invalid overlay settings.');
    }
    final parsedPosition = OverlaySettingsPosition.values
        .where((candidate) => candidate.name == position)
        .firstOrNull;
    if (parsedPosition == null) {
      throw const FormatException('Invalid overlay position.');
    }
    return OverlaySettingsSnapshot.available(
      revision: revision,
      settings: OverlaySettingsValue(
        enabled: enabled,
        opacity: opacity.toDouble(),
        position: parsedPosition,
        showTeam: showTeam,
      ),
      windowAvailable: windowState != 'unavailable',
    );
  }

  static OverlaySettingsFailure _map(Object error, bool write) {
    if (error is FormatException) return OverlaySettingsFailure.invalidResponse;
    if (error is BridgeRemoteException) {
      return switch (error.code) {
        'overlay.revision_conflict' => OverlaySettingsFailure.writeConflict,
        'overlay.invalid_value' => OverlaySettingsFailure.invalidValue,
        'overlay.write_failed' => OverlaySettingsFailure.writeFailed,
        'overlay.read_failed' => OverlaySettingsFailure.readFailed,
        _ =>
          write
              ? OverlaySettingsFailure.writeFailed
              : OverlaySettingsFailure.readFailed,
      };
    }
    if (error is BridgeClientException) {
      return OverlaySettingsFailure.hostUnavailable;
    }
    return write
        ? OverlaySettingsFailure.writeFailed
        : OverlaySettingsFailure.invalidResponse;
  }

  @override
  Future<void> close() async {}
}
