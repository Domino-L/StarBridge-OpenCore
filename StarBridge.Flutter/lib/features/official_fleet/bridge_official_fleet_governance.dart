import 'dart:async';

import '../common/organization_governance_port.dart';
import '../communities/communities_module.dart';
import '../communities/community_bridge_transport.dart';
import '../../platform/bridge/bridge_request_operation.dart';
import 'official_fleet_governance_management.dart';

/// Borrows the one account transport. It has no worker, journal or authority.
final class BridgeOfficialFleetGovernance
    implements
        OrganizationGovernancePort,
        OfficialFleetGovernanceManagementProvider {
  BridgeOfficialFleetGovernance(this.transport) {
    _invalidations = transport.invalidations.listen((_) => _retire());
    _supported = transport.session.hostCapabilities.contains(command);
    _capabilities = transport.session.capabilitiesChanged.listen((_) {
      final supported = transport.session.hostCapabilities.contains(command);
      _supported = supported;
      // Management capabilities can disappear while the context read remains.
      _retire();
    });
    _unobserve = transport.session.observeGenerationChanges(
      (_, _) => _retire(),
    );
  }
  static const command = 'officialFleet.readGovernanceContext';
  static const activate = 'officialFleet.governance.activate';
  static const revoke = 'officialFleet.governance.revokeActivation';

  /// Host can add the caller's role when asked (Flutter→Host negotiation).
  static const roleCapability = 'officialFleet.governanceRole';
  final CommunityBridgeTransport transport;
  @override
  late final OfficialFleetGovernanceManagementPort management =
      BridgeOfficialFleetGovernanceManagement(
        transport,
        invalidations,
        ownerAvailable: () => !_closed,
        ownerFence: () => _epoch,
      );
  late final StreamSubscription<void> _invalidations, _capabilities;
  late final void Function() _unobserve;
  final _changes = StreamController<void>.broadcast(sync: true);
  bool _closed = false, _supported = false;

  /// Source whose last context carried a role: Host and relay then accept
  /// per-leader activation for it. Retired with every invalidation.
  String? _activationSource;
  int _epoch = 0;
  @override
  bool get available =>
      !_closed &&
      !transport.isClosed &&
      transport.onlineTrafficAllowed &&
      !transport.session.connectionModeChanging &&
      transport.session.hostCapabilities.contains(command);
  @override
  Stream<void> get invalidations => _changes.stream;
  void _retire() {
    if (_closed) return;
    ++_epoch;
    _activationSource = null;
    _changes.add(null);
  }

  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) async {
    if (_closed || transport.isClosed || !_supported) {
      throw const CommunityFailure('upgradeRequired');
    }
    if (!available) throw const CommunityFailure('unavailable');
    if (!RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(sourceRef)) {
      throw const CommunityFailure('dataInvalid');
    }
    final fence = (
      _epoch,
      transport.requestEpoch,
      transport.session.activeGeneration,
      transport.session.connectionModeRevision,
    );
    final row = await transport.workspaceRead(
      () => transport.sendRequest(command, {
        'sourceRef': sourceRef,
        if (transport.session.hostCapabilities.contains(roleCapability) ||
            transport.session.hostCapabilities.contains(
              'officialFleet.governanceCapabilitiesV2',
            ))
          'include': [
            if (transport.session.hostCapabilities.contains(roleCapability))
              'role',
            if (transport.session.hostCapabilities.contains(
              'officialFleet.governanceCapabilitiesV2',
            ))
              'capabilitiesV2',
          ],
      }, timeout: const Duration(seconds: 15)),
    );
    if (!available ||
        fence !=
            (
              _epoch,
              transport.requestEpoch,
              transport.session.activeGeneration,
              transport.session.connectionModeRevision,
            )) {
      throw const CommunityFailure('identityUnavailable');
    }
    final context = OrganizationGovernanceContext.parse(row, sourceRef);
    _activationSource = context.role == null ? null : sourceRef;
    return context;
  }

  @override
  bool get canActivate => available && _activationSource != null;

  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) async {
    if (!canActivate || _activationSource != sourceRef) {
      throw const CommunityFailure('upgradeRequired');
    }
    if (!RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(sourceRef) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(operationId) ||
        expectedPolicyRevision < 0) {
      throw const CommunityFailure('dataInvalid');
    }
    final fence = (
      _epoch,
      transport.requestEpoch,
      transport.session.activeGeneration,
    );
    final Map<String, Object?> row;
    try {
      row = await transport.sendRequest(active ? activate : revoke, {
        'sourceRef': sourceRef,
        'operationId': operationId,
        'expectedPolicyRevision': expectedPolicyRevision,
      }, timeout: const Duration(seconds: 20));
    } on CommunityFailure {
      rethrow;
    } on BridgeRemoteException catch (error) {
      switch (error.code) {
        // Host validates these before it forwards anything to the relay.
        case 'communities.upgradeRequired':
          throw const CommunityFailure('upgradeRequired');
        case 'communities.dataInvalid':
          throw const CommunityFailure('dataInvalid');
        // Host timed out before sending, so no outcome is pending.
        case 'communities.activationNotSent':
          throw const CommunityFailure('unavailable');
        // The account changed: its intent retires with it.
        case 'communities.identityUnavailable' ||
            'official_fleet.identity_unavailable' ||
            'account.reauthorization_required':
          throw const CommunityFailure('identityUnavailable');
      }
      // Any other Host error may come after the write was forwarded.
      return const OrganizationActivationOutcome('outcomeUnknown');
    } on Object {
      // Timeout or lost connection: the relay may have applied it.
      return const OrganizationActivationOutcome('outcomeUnknown');
    }
    if (fence !=
        (_epoch, transport.requestEpoch, transport.session.activeGeneration)) {
      throw const CommunityFailure('identityUnavailable');
    }
    final state = row['state'],
        revision = row['policyRevision'],
        sequence = row['auditSequence'],
        echoed = row['operationId'];
    const keys = {
      'schemaVersion',
      'sourceRef',
      'operationId',
      'state',
      'policyRevision',
      'auditSequence',
    };
    final receipt = state == 'accepted' || state == 'duplicate';
    if (row['schemaVersion'] != 1 ||
        !keys.containsAll(row.keys) ||
        row['sourceRef'] != sourceRef ||
        (echoed != null && echoed != operationId) ||
        state is! String ||
        !OrganizationActivationOutcome.states.contains(state) ||
        (revision != null && (revision is! int || revision < 0)) ||
        (sequence != null && (sequence is! int || sequence < 0)) ||
        (receipt && (revision == null || echoed == null))) {
      // The write was sent; an unreadable answer proves nothing either way.
      return const OrganizationActivationOutcome('outcomeUnknown');
    }
    return OrganizationActivationOutcome(
      state,
      policyRevision: revision as int?,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    _unobserve();
    await _invalidations.cancel();
    await _capabilities.cancel();
    await _changes.close();
  }
}
