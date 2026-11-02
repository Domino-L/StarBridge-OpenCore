import '../../platform/bridge/bridge_client_session.dart';

import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'overlay_appearance_live_session.dart';

/// Dedicated new capability. It cannot silently fall back to the old carrier.
final class BridgeOverlayAppearanceLivePort
    implements
        OverlayAppearanceLivePort,
        OverlayAppearanceLiveOwnerEvents,
        OverlayAppearanceLiveControlsPort,
        OverlayAppearanceLivePlaybackPort,
        OverlayAppearanceLivePlacementPort {
  BridgeOverlayAppearanceLivePort(this._session);
  static const capability = 'overlay.appearanceLivePreview';
  final BridgeClientSession _session;
  Map<String, String> _placementStates = const {};
  @override
  Map<String, String> get placementStates => _placementStates;
  bool get supported => _session.hostCapabilities.contains(capability);
  @override
  Stream<void> get previewOwnerChanges => _session.events
      .where(
        (event) =>
            event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated',
      )
      .map((_) {});

  Future<BridgeEnvelope> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    if (!supported) throw StateError('live_preview_unavailable');
    final generation = _session.activeGeneration;
    final response = await _session.request(name, payload: payload);
    if (_session.activeGeneration != generation) {
      throw BridgeStaleGenerationException(
        generation,
        _session.activeGeneration,
      );
    }
    if (response.name != name || response.accountContext != null) {
      throw const FormatException('Invalid live preview response.');
    }
    return response;
  }

  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame frame) async {
    final response = await _request('$capability.open', {
      'schemaVersion': 1,
      'frame': frame.toMap(),
    });
    _exact(response.payload, {
      'schemaVersion',
      'sessionId',
      if (response.payload.containsKey('placementStates')) 'placementStates',
    });
    final id = response.payload['sessionId'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid live preview session.');
    }
    _placementStates = _readPlacements(response.payload);
    return id;
  }

  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame frame,
  ) async {
    _sessionId(id);
    if (revision < 1 || revision > 9007199254740991) {
      throw const FormatException('Invalid live preview revision.');
    }
    final response = await _request('$capability.update', {
      'schemaVersion': 1,
      'sessionId': id,
      'revision': revision,
      'frame': frame.toMap(),
    });
    _exact(response.payload, {
      'schemaVersion',
      'revision',
      if (response.payload.containsKey('placementStates')) 'placementStates',
    });
    if (response.payload['revision'] is! int ||
        response.payload['revision'] != revision) {
      throw const FormatException('Invalid live preview revision receipt.');
    }
    _placementStates = _readPlacements(response.payload);
    return revision;
  }

  @override
  Future<void> closeLivePreview(String id) async {
    _sessionId(id);
    final response = await _request('$capability.close', {
      'schemaVersion': 1,
      'sessionId': id,
    });
    _exact(response.payload, {'schemaVersion', 'closed'});
    if (response.payload['closed'] != true) {
      throw const FormatException('Invalid live preview close receipt.');
    }
    _placementStates = const {};
  }

  @override
  Future<int> renewLivePreview(String id, int revision) async {
    _sessionId(id);
    if (revision < 1 || revision > 9007199254740991) {
      throw const FormatException('Invalid preview renewal revision.');
    }
    final response = await _request('$capability.renew', {
      'schemaVersion': 1,
      'sessionId': id,
      'revision': revision,
    });
    _exact(response.payload, {'schemaVersion', 'revision'});
    if (response.payload['revision'] is! int ||
        response.payload['revision'] != revision) {
      throw const FormatException('Invalid preview renewal receipt.');
    }
    return revision;
  }

  @override
  Future<int> protectLivePreviewControls(
    String id,
    int revision,
    List<OverlayPreviewControlArea> areas,
  ) async {
    _sessionId(id);
    if (revision < 1 ||
        revision > 9007199254740991 ||
        areas.length > 16 ||
        areas.any((a) => !a.valid)) {
      throw const FormatException('Invalid control protection.');
    }
    final response = await _request('$capability.protect', {
      'schemaVersion': 1,
      'sessionId': id,
      'revision': revision,
      'areas': areas.map((a) => a.toMap()).toList(growable: false),
    });
    _exact(response.payload, {'schemaVersion', 'revision'});
    if (response.payload['revision'] is! int ||
        response.payload['revision'] != revision) {
      throw const FormatException('Invalid protection receipt.');
    }
    return revision;
  }

  static void _sessionId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid live preview session.');
    }
  }

  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback action,
  ) async {
    _sessionId(id);
    if (revision < 1 || revision > 9007199254740991) {
      throw const FormatException('Invalid playback revision.');
    }
    final response = await _request('$capability.playback', {
      'schemaVersion': 1,
      'sessionId': id,
      'revision': revision,
      'action': action.wireName,
    });
    _exact(response.payload, {'schemaVersion', 'revision', 'accepted'});
    if (response.payload['revision'] is! int ||
        response.payload['revision'] != revision ||
        response.payload['accepted'] is! bool) {
      throw const FormatException('Invalid playback receipt.');
    }
    return response.payload['accepted']! as bool;
  }

  static void _exact(Map<String, Object?> value, Set<String> keys) {
    if (value.length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['schemaVersion'] != 1) {
      throw const FormatException('Invalid live preview fields.');
    }
  }

  static Map<String, String> _readPlacements(Map<String, Object?> payload) {
    if (!payload.containsKey('placementStates')) return const {};
    final rows = payload['placementStates'];
    if (rows is! List || rows.length > 12) {
      throw const FormatException('Invalid placement feedback.');
    }
    final result = <String, String>{};
    for (final row in rows) {
      if (row is! Map ||
          row.length != 2 ||
          row['slotId'] is! String ||
          row['reason'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(row['slotId'] as String) ||
          !const {
            'placed',
            'invalid',
            'module-hidden',
            'module-space',
            'joined-edge',
            'screen-edge',
            'neighbor-module',
            'decoration-overlap',
            'interaction-space',
            'observation-only',
          }.contains(row['reason']) ||
          result.containsKey(row['slotId'])) {
        throw const FormatException('Invalid placement feedback.');
      }
      result[row['slotId'] as String] = row['reason'] as String;
    }
    return Map.unmodifiable(result);
  }
}
