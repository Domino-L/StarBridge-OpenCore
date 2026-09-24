import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'official_fleet_models.dart';
import 'official_fleet_port.dart';

final class BridgeOfficialFleetAdapter implements OfficialFleetPort {
  BridgeOfficialFleetAdapter(this._session) {
    _subscription = _session.events.listen(_onEvent);
  }

  final BridgeClientSession _session;
  final StreamController<void> _invalidations =
      StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;

  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  Future<OfficialFleetSnapshot> read() async {
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      _requireSchema(account.payload);
      final accountState = _requiredString(account.payload, 'state');
      if (accountState == 'signedOut' ||
          accountState == 'reauthorizationRequired') {
        return const OfficialFleetSnapshot.signedOut();
      }
      if (accountState == 'credentialTemporarilyUnavailable') {
        return const OfficialFleetSnapshot.unavailable(
          failureKey: 'officialFleet.error.scmUnavailable',
        );
      }
      if (accountState != 'signedIn' || account.accountContext == null) {
        throw const BridgeFormatException(
          'Signed-in official fleet requires accountContext.',
        );
      }

      final response = await _session.request(
        'officialFleet.getCurrent',
        payload: const {'schemaVersion': 1},
        accountContext: account.accountContext,
      );
      return _parseSnapshot(response.payload);
    } on Object catch (error) {
      return OfficialFleetSnapshot.unavailable(failureKey: _failureKey(error));
    }
  }

  void _onEvent(BridgeEnvelope event) {
    if (event.name == 'account.changed' ||
        event.name == 'bootstrap.invalidated') {
      _invalidations.add(null);
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _invalidations.close();
  }
}

OfficialFleetSnapshot _parseSnapshot(Map<String, Object?> payload) {
  _requireSchema(payload);
  final state = _requiredString(payload, 'state');
  final freshness = _parseFreshness(_requiredString(payload, 'freshness'));
  final resourceVersion = _optionalNonNegativeInt(payload, 'resourceVersion');
  final observedAt = DateTime.tryParse(
    _requiredString(payload, 'observedAtUtc'),
  )?.toUtc();
  if (observedAt == null) {
    throw const BridgeFormatException(
      'observedAtUtc must be an ISO timestamp.',
    );
  }
  if (state == 'notMember') {
    if (payload['fleet'] != null) {
      throw const BridgeFormatException('notMember cannot include fleet data.');
    }
    return OfficialFleetSnapshot.notMember(
      freshness: freshness,
      resourceVersion: resourceVersion,
      observedAtUtc: observedAt,
    );
  }
  if (state != 'member') {
    throw const BridgeFormatException('Official fleet state is unsupported.');
  }

  final fleet = _requiredMap(payload, 'fleet');
  final sourceRef = _requiredString(fleet, 'sourceRef');
  if (!RegExp(r'^officialFleet:[1-9][0-9]*$').hasMatch(sourceRef)) {
    throw const BridgeFormatException(
      'sourceRef must identify an official fleet.',
    );
  }
  final rank = _optionalInt(fleet, 'officialRankValue');
  if (rank != null && (rank < 1 || rank > 5)) {
    throw const BridgeFormatException(
      'officialRankValue must be between 1 and 5.',
    );
  }
  final logoUrl = _optionalString(fleet, 'logoUrl');
  if (logoUrl != null) {
    final uri = Uri.tryParse(logoUrl);
    if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
      throw const BridgeFormatException('logoUrl must be HTTPS.');
    }
  }
  return OfficialFleetSnapshot.available(
    fleet: OfficialFleetSummary(
      sourceRef: sourceRef,
      sid: _requiredString(fleet, 'sid'),
      name: _requiredString(fleet, 'name'),
      logoUrl: logoUrl,
      officialRankName: _optionalString(fleet, 'officialRankName'),
      officialRankValue: rank,
    ),
    freshness: freshness,
    resourceVersion: resourceVersion,
    observedAtUtc: observedAt,
  );
}

OfficialFleetFreshness _parseFreshness(String value) => switch (value) {
  'live' => OfficialFleetFreshness.live,
  _ => throw const BridgeFormatException(
    'Official fleet freshness is unsupported.',
  ),
};

String _failureKey(Object error) {
  if (error is BridgeClientException) {
    return switch (error.code) {
      'bridge.disconnected' => 'officialFleet.error.hostUnavailable',
      'account.reauthorization_required' =>
        'officialFleet.error.reauthorizationRequired',
      'official_fleet.data_invalid' ||
      'bridge.invalid_envelope' ||
      'bridge.protocol_incompatible' => 'officialFleet.error.invalidResponse',
      _ => 'officialFleet.error.unavailable',
    };
  }
  return error is BridgeFormatException
      ? 'officialFleet.error.invalidResponse'
      : 'officialFleet.error.unavailable';
}

void _requireSchema(Map<String, Object?> payload) {
  if (payload['schemaVersion'] != 1) {
    throw const BridgeFormatException(
      'Official fleet payload schema is incompatible.',
    );
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map) {
    throw BridgeFormatException('$key must be an object.');
  }
  return value.cast<String, Object?>();
}

String _requiredString(Map<String, Object?> source, String key) {
  final value = _optionalString(source, key);
  if (value == null) {
    throw BridgeFormatException('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw BridgeFormatException('$key must be a string or null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _optionalInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw BridgeFormatException('$key must be an integer or null.');
  }
  return value;
}

int? _optionalNonNegativeInt(Map<String, Object?> source, String key) {
  final value = _optionalInt(source, key);
  if (value != null && value < 0) {
    throw BridgeFormatException('$key must not be negative.');
  }
  return value;
}
