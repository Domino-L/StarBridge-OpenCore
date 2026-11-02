import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'official_fleet_bridge_values.dart' as wire;
import 'official_fleet_models.dart';
import 'official_fleet_port.dart';
import 'official_fleet_read_failure.dart';
import 'official_fleet_profile_port.dart';

final class BridgeOfficialFleetAdapter
    implements
        OfficialFleetPort,
        OfficialFleetProfilePort,
        OfficialFleetWebsitePort {
  BridgeOfficialFleetAdapter(this._session) {
    _subscription = _session.events.listen(_onEvent);
  }

  final BridgeClientSession _session;
  final StreamController<void> _invalidations =
      StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  bool _closed = false;
  int _rootEpoch = 0, _profileEpoch = 0;
  final _rootOperations = <BridgeRequestOperation>{};
  final _profileOperations = <BridgeRequestOperation>{};
  @override
  bool get supportsDeferredProfile =>
      !_closed &&
      _session.hostCapabilities.contains('officialFleet.deferredProfile');

  @override
  bool get supportsWebsite =>
      !_closed &&
      _session.hostCapabilities.contains('helpSupport.openRsiOrganization');

  @override
  Future<bool> openWebsite(String sid) async {
    if (!supportsWebsite || !RegExp(r'^[A-Z0-9]{1,10}$').hasMatch(sid)) {
      return false;
    }
    final epoch = _rootEpoch;
    try {
      final response = await _ownedRequest(
        _rootOperations,
        'helpSupport.openRsiOrganization',
        payload: {'schemaVersion': 1, 'sid': sid},
      );
      wire.requireSchema(response.payload);
      return !_closed &&
          epoch == _rootEpoch &&
          response.payload['opened'] == true;
    } on Object {
      return false;
    }
  }

  Future<BridgeEnvelope> _ownedRequest(
    Set<BridgeRequestOperation> operations,
    String name, {
    Map<String, Object?> payload = const {'schemaVersion': 1},
    BridgeAccountContext? accountContext,
  }) async {
    final operation = _session.beginRequest(
      name,
      payload: payload,
      accountContext: accountContext,
    );
    operations.add(operation);
    try {
      return await operation.future;
    } finally {
      operations.remove(operation);
    }
  }

  Future<void> _cancelOperations(Set<BridgeRequestOperation> operations) async {
    await Future.wait(
      operations.toList().map((work) async {
        try {
          await work.cancel();
        } on Object {
          /* The local read is already retired. */
        }
      }),
    );
  }

  @override
  Future<void> cancelProfileRead() {
    ++_profileEpoch;
    return _cancelOperations(_profileOperations);
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  Future<OfficialFleetSnapshot> read() async {
    final epoch = _rootEpoch;
    try {
      final account = await _ownedRequest(
        _rootOperations,
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      wire.requireSchema(account.payload);
      final accountState = wire.requiredString(account.payload, 'state');
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

      if (_closed || epoch != _rootEpoch) {
        throw const BridgeCancelledException('officialFleet.getIdentity');
      }
      final response = await _ownedRequest(
        _rootOperations,
        supportsDeferredProfile
            ? 'officialFleet.getIdentity'
            : 'officialFleet.getCurrent',
        payload: const {'schemaVersion': 1},
        accountContext: account.accountContext,
      );
      if (_closed || epoch != _rootEpoch) {
        throw const BridgeCancelledException('officialFleet.getIdentity');
      }
      return _parseSnapshot(response.payload);
    } on Object catch (error) {
      return OfficialFleetSnapshot.unavailable(
        failureKey: fleetReadFailureKey(error),
        transientFailure: fleetReadIsTransient(error),
        discardContext: fleetReadLosesContext(error),
      );
    }
  }

  void _onEvent(BridgeEnvelope event) {
    if (event.name == 'account.changed' ||
        event.name == 'bootstrap.invalidated') {
      _invalidations.add(null);
      ++_rootEpoch;
      unawaited(_cancelOperations(_rootOperations));
      unawaited(cancelProfileRead());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_rootEpoch;
    await Future.wait([
      _cancelOperations(_rootOperations),
      cancelProfileRead(),
    ]);
    await _subscription.cancel();
    await _invalidations.close();
  }

  @override
  Future<OfficialFleetPublicProfile> readProfile(String sourceRef) async {
    final epoch = _profileEpoch;
    var ownerVerified = false;
    try {
      final account = await _ownedRequest(
        _profileOperations,
        'account.getCurrent',
      );
      wire.requireSchema(account.payload);
      if (account.payload['state'] != 'signedIn' ||
          account.accountContext == null) {
        return OfficialFleetPublicProfile(
          sourceRef: sourceRef,
          state: OfficialFleetProfileReadState.unavailable,
          ownerUnavailable: true,
          discardContext:
              account.payload['state'] == 'signedOut' ||
              account.payload['state'] == 'reauthorizationRequired',
          failureKey: 'officialFleet.error.reauthorizationRequired',
        );
      }
      if (_closed || epoch != _profileEpoch) {
        return OfficialFleetPublicProfile(
          sourceRef: sourceRef,
          state: OfficialFleetProfileReadState.unavailable,
          discarded: true,
        );
      }
      ownerVerified = true;
      final response = await _ownedRequest(
        _profileOperations,
        'officialFleet.getPublicProfile',
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, 'sourceRef': sourceRef},
      );
      if (_closed || epoch != _profileEpoch) {
        return OfficialFleetPublicProfile(
          sourceRef: sourceRef,
          state: OfficialFleetProfileReadState.unavailable,
          discarded: true,
        );
      }
      wire.requireSchema(response.payload);
      if (response.payload['sourceRef'] != sourceRef) {
        throw const BridgeFormatException(
          'Public profile belongs to another source.',
        );
      }
      final sid = wire.requiredString(response.payload, 'sid');
      final profile = _parseProfile(response.payload['profile']);
      final read = _parseProfileRead(response.payload['profileRead'], profile);
      if (read.$1 == OfficialFleetProfileReadState.unknown ||
          read.$1 == OfficialFleetProfileReadState.deferred) {
        throw const BridgeFormatException(
          'Public read must include a terminal result.',
        );
      }
      return OfficialFleetPublicProfile(
        sourceRef: sourceRef,
        sid: sid,
        profile: profile,
        state: read.$1,
        observedAtUtc: read.$2,
      );
    } on Object catch (error) {
      if (_closed ||
          epoch != _profileEpoch ||
          error is BridgeStaleGenerationException) {
        return OfficialFleetPublicProfile(
          sourceRef: sourceRef,
          state: OfficialFleetProfileReadState.unavailable,
          discarded: true,
        );
      }
      final lost =
          error is BridgeClientException &&
          const {
            'account.reauthorization_required',
            'bridge.account_context_required',
          }.contains(error.code);
      final invalid =
          error is BridgeFormatException ||
          error is BridgeClientException &&
              error.code == 'official_fleet.data_invalid';
      return OfficialFleetPublicProfile(
        sourceRef: sourceRef,
        state: fleetReadIsTransient(error)
            ? OfficialFleetProfileReadState.transientFailure
            : invalid
            ? OfficialFleetProfileReadState.invalid
            : OfficialFleetProfileReadState.unavailable,
        failureKey: fleetReadFailureKey(error),
        ownerUnavailable:
            !ownerVerified || lost || error is BridgeDisconnectedException,
        discardContext: lost,
      );
    }
  }
}

OfficialFleetSnapshot _parseSnapshot(Map<String, Object?> payload) {
  wire.requireSchema(payload);
  final state = wire.requiredString(payload, 'state');
  final freshness = _parseFreshness(wire.requiredString(payload, 'freshness'));
  final resourceVersion = wire.optionalNonNegativeInt(
    payload,
    'resourceVersion',
  );
  final observedAt = DateTime.tryParse(
    wire.requiredString(payload, 'observedAtUtc'),
  )?.toUtc();
  if (observedAt == null) {
    throw const BridgeFormatException(
      'observedAtUtc must be an ISO timestamp.',
    );
  }
  if (state == 'notMember') {
    if (payload['fleet'] != null || payload['profileRead'] != null) {
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

  final fleet = wire.requiredMap(payload, 'fleet');
  final sourceRef = wire.requiredString(fleet, 'sourceRef');
  if (!RegExp(r'^officialFleet:[1-9][0-9]*$').hasMatch(sourceRef)) {
    throw const BridgeFormatException(
      'sourceRef must identify an official fleet.',
    );
  }
  final rank = wire.optionalInt(fleet, 'officialRankValue');
  if (rank != null && (rank < 1 || rank > 5)) {
    throw const BridgeFormatException(
      'officialRankValue must be between 1 and 5.',
    );
  }
  final logoUrl = wire.optionalString(fleet, 'logoUrl');
  if (logoUrl != null) {
    final uri = Uri.tryParse(logoUrl);
    if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
      throw const BridgeFormatException('logoUrl must be HTTPS.');
    }
  }
  final profile = _parseProfile(fleet['profile']);
  final profileRead = _parseProfileRead(payload['profileRead'], profile);
  return OfficialFleetSnapshot.available(
    profileReadState: profileRead.$1,
    profileObservedAtUtc: profileRead.$2,
    fleet: OfficialFleetSummary(
      sourceRef: sourceRef,
      sid: wire.requiredString(fleet, 'sid'),
      name: wire.requiredString(fleet, 'name'),
      logoUrl: logoUrl,
      officialRankName: wire.optionalString(fleet, 'officialRankName'),
      officialRankValue: rank,
      profile: profile,
    ),
    freshness: freshness,
    resourceVersion: resourceVersion,
    observedAtUtc: observedAt,
  );
}

(OfficialFleetProfileReadState, DateTime?) _parseProfileRead(
  Object? value,
  OfficialFleetProfileDetails? profile,
) {
  if (value == null) return (OfficialFleetProfileReadState.unknown, null);
  if (value is! Map) {
    throw const BridgeFormatException('Invalid profile read metadata.');
  }
  final row = value.cast<String, Object?>();
  final state = switch (row['state']) {
    'deferred' => OfficialFleetProfileReadState.deferred,
    'available' => OfficialFleetProfileReadState.available,
    'transientFailure' => OfficialFleetProfileReadState.transientFailure,
    'forbidden' => OfficialFleetProfileReadState.forbidden,
    'invalid' => OfficialFleetProfileReadState.invalid,
    'unavailable' => OfficialFleetProfileReadState.unavailable,
    _ => throw const BridgeFormatException('Unsupported profile read state.'),
  };
  if (state != OfficialFleetProfileReadState.available) {
    if (row['observedAtUtc'] != null || profile != null) {
      throw const BridgeFormatException(
        'Failed profile read cannot claim content or a success time.',
      );
    }
    return (state, null);
  }
  final at = DateTime.tryParse(wire.requiredString(row, 'observedAtUtc'));
  if (at == null || !at.isUtc || profile == null) {
    throw const BridgeFormatException(
      'Confirmed profile requires content and a qualified time.',
    );
  }
  return (state, at.toUtc());
}

OfficialFleetProfileDetails? _parseProfile(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const BridgeFormatException('Invalid fleet profile.');
  }
  final profile = value.cast<String, Object?>();
  List<String> labels(String key) {
    final rows = profile[key];
    if (rows is! List ||
        rows.length > 20 ||
        rows.any((item) => item is! String || item.length > 256)) {
      throw const BridgeFormatException('Invalid profile labels.');
    }
    return rows.cast<String>();
  }

  String? image(String key) {
    final value = wire.optionalString(profile, key);
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const BridgeFormatException('Invalid profile image.');
    }
    return value;
  }

  return OfficialFleetProfileDetails(
    bannerUrl: image('bannerUrl'),
    backgroundUrl: image('backgroundUrl'),
    logoUrl: image('logoUrl'),
    memberCount: wire.optionalNonNegativeInt(profile, 'memberCount'),
    rsiDescription: wire.optionalString(profile, 'rsiDescription'),
    scmSupplementalDescription: wire.optionalString(
      profile,
      'scmSupplementalDescription',
    ),
    primaryFocusLabel: wire.optionalString(profile, 'primaryFocusLabel'),
    secondaryFocusLabel: wire.optionalString(profile, 'secondaryFocusLabel'),
    languageLabels: labels('languageLabels'),
    organizationModelLabel: wire.optionalString(
      profile,
      'organizationModelLabel',
    ),
    commitmentLabel: wire.optionalString(profile, 'commitmentLabel'),
    roleplayLabel: wire.optionalString(profile, 'roleplayLabel'),
    archetypeLabel: wire.optionalString(profile, 'archetypeLabel'),
    tags: labels('tags'),
  );
}

OfficialFleetFreshness _parseFreshness(String value) => switch (value) {
  'live' => OfficialFleetFreshness.live,
  _ => throw const BridgeFormatException(
    'Official fleet freshness is unsupported.',
  ),
};
