import 'dart:async';
import 'dart:math';

import '../communities/communities_module.dart';
import '../communities/community_bridge_transport.dart';
import '../../platform/bridge/bridge_request_operation.dart';
import 'bridge_official_fleet_members_adapter.dart';
import 'official_fleet_members_models.dart';

typedef GovernanceRow = Map<String, Object?>;

abstract interface class OfficialFleetGovernanceManagementProvider {
  OfficialFleetGovernanceManagementPort get management;
}

abstract interface class OfficialFleetGovernanceManagementPort {
  bool supports(String command);
  Stream<void> get invalidations;
  Future<GovernanceRow> read(
    String command,
    String source, [
    GovernanceRow args,
  ]);
  Future<String> write(String command, String source, GovernanceRow intent);

  /// The outcome of an uncertain template write, in [write]'s terms, or
  /// [governanceOutcomeNotFound] when the Host never recorded the request.
  Future<String> roleTemplateOutcome(String source, String requestId);
}

const governanceOutcomeNotFound = 'notFound';

String governanceOperationId() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}

const governancePermissions = [
  'announcements.manage',
  'rally.manage',
  'audit.view',
];

List<GovernanceRow> governanceRows(Object? value) {
  if (value is! List || value.any((row) => row is! GovernanceRow)) {
    throw const FormatException();
  }
  return value.cast<GovernanceRow>();
}

bool governanceAllowed(Object? value) =>
    value is Map && value['state'] == 'allowed';

/// Borrows the existing account transport and retires observations with it.
final class BridgeOfficialFleetGovernanceManagement
    implements OfficialFleetGovernanceManagementPort {
  BridgeOfficialFleetGovernanceManagement(
    this.transport,
    this.invalidations, {
    this.ownerAvailable,
    this.ownerFence,
  });
  final CommunityBridgeTransport transport;
  final bool Function()? ownerAvailable;
  final Object Function()? ownerFence;
  @override
  final Stream<void> invalidations;
  @override
  bool supports(String command) =>
      !transport.isClosed &&
      (ownerAvailable?.call() ?? true) &&
      transport.onlineTrafficAllowed &&
      !transport.session.connectionModeChanging &&
      transport.session.hostCapabilities.contains(
        command == 'getMembers'
            ? 'officialFleet.read'
            : 'officialFleet.$command',
      );

  Object get _fence => (
    ownerFence?.call(),
    transport.requestEpoch,
    transport.session.activeGeneration,
    transport.session.connectionModeRevision,
  );

  @override
  Future<GovernanceRow> read(
    String command,
    String source, [
    GovernanceRow args = const {},
  ]) async {
    if (!supports(command)) throw const CommunityFailure('upgradeRequired');
    final fence = _fence;
    final row = await transport.workspaceRead(
      () => transport.sendRequest('officialFleet.$command', {
        'sourceRef': source,
        ...args,
      }, timeout: const Duration(seconds: 20)),
    );
    if (fence != _fence || !supports(command)) {
      throw const CommunityFailure('identityUnavailable');
    }
    if (row['schemaVersion'] != 1 || row['sourceRef'] != source) {
      throw const CommunityFailure('dataInvalid');
    }
    if (command != 'getMembers' && row['state'] != 'available') {
      throw CommunityFailure(
        row['state'] == 'notAllowed' ? 'notAllowed' : 'unavailable',
      );
    }
    if (command == 'getMembers') {
      parseOfficialFleetMembers(
        row,
        OfficialFleetMemberDirectoryQuery(
          sourceRef: source,
          pageNumber: args['pageNumber'] as int? ?? 1,
          pageSize: 25,
        ),
      );
    }
    if (command == 'readMemberRoles' && row['targetRef'] != args['targetRef']) {
      throw const CommunityFailure('dataInvalid');
    }
    validateGovernanceRead(command, row);
    return row;
  }

  @override
  Future<String> write(
    String command,
    String source,
    GovernanceRow intent,
  ) async {
    if (!supports(command)) throw const CommunityFailure('upgradeRequired');
    final fields = switch (command) {
      'writeRankPolicy' => {'rows'},
      'updateRolePermissions' => {
        'roleKey',
        'expectedPermissionVersion',
        'enabled',
        'permissions',
      },
      'assignRole' => {
        'targetRef',
        'expectedTargetMembershipEpoch',
        'roleKey',
        'expectedRolePermissionVersion',
        'parts',
      },
      'revokeRole' => {'grantId', 'expectedGrantVersion'},
      'manageRoleTemplates' =>
        intent['action'] == 'create'
            ? {'editRef', 'requestId', 'action', 'metadata', 'permissions'}
            : {'editRef', 'requestId', 'action', 'metadata', 'roleRef'},
      _ => <String>{},
    };
    if (command != 'manageRoleTemplates') {
      fields.addAll({'operationId', 'expectedPolicyRevision'});
    }
    if (fields.length != intent.length ||
        !fields.containsAll(intent.keys) ||
        !RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(source)) {
      throw const CommunityFailure('dataInvalid');
    }
    final fence = _fence;
    GovernanceRow row;
    try {
      row = await transport.sendRequest('officialFleet.$command', {
        'sourceRef': source,
        ...intent,
      }, timeout: const Duration(seconds: 20));
    } on CommunityFailure {
      rethrow;
    } on BridgeRemoteException catch (error) {
      if (fence != _fence) throw const CommunityFailure('identityUnavailable');
      if (error.code == 'communities.notAllowed') {
        return 'notAllowed';
      }
      if (error.code == 'communities.refreshRequired') {
        return 'conflict';
      }
      if (const {
        'communities.upgradeRequired',
        'communities.dataInvalid',
        'communities.identityUnavailable',
        'account.reauthorization_required',
        'official_fleet.identity_unavailable',
      }.contains(error.code)) {
        throw CommunityFailure(switch (error.code) {
          'communities.upgradeRequired' => 'upgradeRequired',
          'communities.dataInvalid' => 'dataInvalid',
          _ => 'identityUnavailable',
        });
      }
      return 'operationOutcomeUnknown';
    } on Object {
      if (fence != _fence) throw const CommunityFailure('identityUnavailable');
      return 'operationOutcomeUnknown';
    }
    if (fence != _fence) throw const CommunityFailure('identityUnavailable');
    if (command == 'manageRoleTemplates') {
      if (row['requestId'] != intent['requestId'] ||
          row['schemaVersion'] != 1 ||
          row['sourceRef'] != source ||
          row['editRef'] != intent['editRef'] ||
          row['action'] != intent['action']) {
        return 'operationOutcomeUnknown';
      }
      return _roleTemplateStatus(row);
    }
    final state = row['state'];
    if (row['schemaVersion'] != 1 ||
        row['operationId'] != null &&
            row['operationId'] != intent['operationId'] ||
        !const {
          'accepted',
          'duplicate',
          'invalid',
          'notAllowed',
          'conflict',
          'unavailable',
          'storageLimitReached',
          'operationOutcomeUnknown',
        }.contains(state) ||
        const {'accepted', 'duplicate'}.contains(state) &&
            (row['operationId'] != intent['operationId'] ||
                row['policyRevision'] is! int ||
                row['auditSequence'] is! int ||
                intent['expectedPolicyRevision'] is! int ||
                row['policyRevision'] !=
                    (intent['expectedPolicyRevision'] as int) + 1 ||
                row['auditSequence'] != row['policyRevision'])) {
      return 'operationOutcomeUnknown';
    }
    return state as String;
  }

  @override
  Future<String> roleTemplateOutcome(String source, String requestId) async {
    const command = 'readRoleTemplateOutcome';
    if (!supports(command)) throw const CommunityFailure('upgradeRequired');
    final fence = _fence;
    GovernanceRow row;
    try {
      row = await transport.sendRequest('officialFleet.$command', {
        'kind': 'query',
        'requestId': requestId,
      }, timeout: const Duration(seconds: 20));
    } on CommunityFailure {
      rethrow;
    } on Object {
      if (fence != _fence) throw const CommunityFailure('identityUnavailable');
      return 'operationOutcomeUnknown';
    }
    if (fence != _fence) throw const CommunityFailure('identityUnavailable');
    if (row['schemaVersion'] != 1 || row['requestId'] != requestId) {
      return 'operationOutcomeUnknown';
    }
    if (row['error'] == governanceOutcomeNotFound) {
      return governanceOutcomeNotFound;
    }
    return row['sourceRef'] == source
        ? _roleTemplateStatus(row)
        : 'operationOutcomeUnknown';
  }

  static String _roleTemplateStatus(GovernanceRow row) =>
      switch (row['status']) {
        'accepted'
            when row['revision'] is int && (row['revision'] as int) >= 0 =>
          'accepted',
        'rejected' => switch (row['error']) {
          'rolesChanged' || 'refreshRequired' => 'conflict',
          'notAllowed' => 'notAllowed',
          _ => 'unavailable',
        },
        _ => 'operationOutcomeUnknown',
      };
}

void validateGovernanceRead(String command, GovernanceRow row) {
  void require(bool valid) {
    if (!valid) throw const FormatException();
  }

  void revision(String name) =>
      require(row[name] is int && (row[name] as int) >= 0);
  switch (command) {
    case 'readRankPolicy':
      revision('policyRevision');
      final rows = governanceRows(row['rows']);
      require(
        rows.length == 4 &&
            rows.map((r) => r['rankValue']).toSet().containsAll([2, 3, 4, 5]),
      );
      for (final r in rows) {
        require(['announcements', 'rally', 'audit'].every((k) => r[k] is bool));
      }
      require(row['write'] is Map && (row['write'] as Map)['reason'] is String);
    case 'readRoleTemplates':
      revision('revision');
      require(row['editRef'] is String);
      for (final r in governanceRows(row['roles'])) {
        require(
          r['roleKey'] is String &&
              r['roleRef'] is String &&
              r['permissionVersion'] is int &&
              r['enabled'] is bool,
        );
        governanceRows(r['permissions']);
      }
      governanceRows(row['creationCapabilities']);
    case 'readMemberRoles':
      revision('policyRevision');
      require(
        row['targetRef'] is String &&
            row['membershipEpoch'] is String &&
            row['rootActivationId'] is String &&
            row['rootActivationVersion'] is int,
      );
      for (final r in governanceRows(row['grants'])) {
        require(
          r['grantId'] is String &&
              r['version'] is int &&
              r['roleKey'] is String &&
              r['revoked'] is bool,
        );
      }
    case 'readGovernanceAudit':
      revision('policyRevision');
      revision('offset');
      for (final r in governanceRows(row['items'])) {
        require(
          r['kind'] is String &&
              r['occurredAtUtc'] is String &&
              DateTime.tryParse(r['occurredAtUtc'] as String) != null &&
              r['actorDisplay'] is String &&
              r['targetDisplay'] is String,
        );
      }
      require(row['nextOffset'] == null || row['nextOffset'] is int);
    case 'getMembers':
      governanceRows(row['members']);
  }
}
