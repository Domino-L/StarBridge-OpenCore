import 'dart:convert';

import '../communities/communities_module.dart';

enum OrganizationDecisionState { allowed, denied, unavailable }

final class OrganizationGovernanceDecision {
  const OrganizationGovernanceDecision(this.key, this.state, this.reason);
  final String key, reason;
  final OrganizationDecisionState state;
}

/// A read observation only. Capability use, root controls and later mutations
/// retain separate authorization. No delegate permission is inferred from use.
final class OrganizationGovernanceContext {
  const OrganizationGovernanceContext._(
    this.sourceRef,
    this.policyRevision,
    this.capabilities,
    this.rootProviderState,
    this.rootControls,
    this.role,
    this.membershipUpdatedAt,
  );
  final String sourceRef, rootProviderState;

  /// leader (SCM rank 1), admin (≤3), editor (≤4) or member. Display only:
  /// every entry still follows the relay's decisions. Older relays omit it.
  final String? role;

  /// When the member evidence was last refreshed, if the relay reported it.
  final DateTime? membershipUpdatedAt;
  final int policyRevision;
  final List<OrganizationGovernanceDecision> capabilities, rootControls;
  static const capabilityKeys = {
    'announcements.manage',
    'audit.view',
    'organization.roles.manage',
  };
  static const rootKeys = {'activate', 'recover', 'delegate'};
  static const roles = {'leader', 'admin', 'editor', 'member'};
  static const _required = {
    'schemaVersion',
    'sourceRef',
    'policyRevision',
    'capabilities',
    'rootAuthority',
  };

  /// Any decision held back only because the member evidence is too old.
  bool get evidenceStale => [
    ...capabilities,
    ...rootControls,
  ].any((d) => d.reason == 'membershipEvidenceStale');
  factory OrganizationGovernanceContext.parse(
    Map<String, Object?> row,
    String source,
  ) {
    void shape(Map<String, Object?> value, Set<String> keys) {
      if (value.length != keys.length ||
          !value.keys.toSet().containsAll(keys)) {
        throw const FormatException();
      }
    }

    final optional = row.keys.toSet().difference(_required);
    if (!row.keys.toSet().containsAll(_required) ||
        !const {'role', 'membershipUpdatedAt'}.containsAll(optional)) {
      throw const FormatException();
    }
    final role = row['role'], updated = row['membershipUpdatedAt'];
    if ((row.containsKey('role') &&
            (role is! String || !roles.contains(role))) ||
        (row.containsKey('membershipUpdatedAt') &&
            (updated is! String || DateTime.tryParse(updated) == null))) {
      throw const FormatException();
    }
    final revision = row['policyRevision'];
    if (utf8.encode(jsonEncode(row)).length > 16 * 1024 ||
        row['schemaVersion'] != 1 ||
        row['sourceRef'] != source ||
        !RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(source) ||
        revision is! int ||
        revision < 0 ||
        revision > 0x7fffffffffffffff) {
      throw const FormatException();
    }
    List<OrganizationGovernanceDecision> decisions(
      Object? raw,
      String field,
      Set<String> keys,
    ) {
      if (raw is! List || raw.length != keys.length) {
        throw const FormatException();
      }
      final seen = <String>{};
      return List.unmodifiable(
        raw.map((value) {
          if (value is! Map<String, Object?>) throw const FormatException();
          shape(value, {field, 'state', 'reason'});
          final key = value[field],
              reason = value['reason'],
              state = value['state'];
          if (key is! String ||
              !keys.contains(key) ||
              !seen.add(key) ||
              reason is! String ||
              reason.isEmpty ||
              reason.length > 128 ||
              !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(reason) ||
              state is! String ||
              !OrganizationDecisionState.values.any((v) => v.name == state)) {
            throw const FormatException();
          }
          return OrganizationGovernanceDecision(
            key,
            OrganizationDecisionState.values.byName(state),
            reason,
          );
        }),
      );
    }

    final root = row['rootAuthority'];
    if (root is! Map<String, Object?>) throw const FormatException();
    shape(root, {'providerState', 'controls'});
    final provider = root['providerState'];
    if (provider is! String ||
        !const {'unconfigured', 'unavailable', 'observed'}.contains(provider)) {
      throw const FormatException();
    }
    return OrganizationGovernanceContext._(
      source,
      revision,
      decisions(
        row['capabilities'],
        'capability',
        row['capabilities'] is List && (row['capabilities'] as List).length == 4
            ? {...capabilityKeys, 'rally.manage'}
            : capabilityKeys,
      ),
      provider,
      decisions(root['controls'], 'action', rootKeys),
      role as String?,
      updated is String ? DateTime.parse(updated).toUtc() : null,
    );
  }
}

/// accepted, duplicate, invalid, identityUnavailable, notAllowed, conflict,
/// unavailable, storageLimitReached or outcomeUnknown (keep the operation id
/// and retry it; never show success).
final class OrganizationActivationOutcome {
  const OrganizationActivationOutcome(this.state, {this.policyRevision});
  final String state;
  final int? policyRevision;
  bool get succeeded => state == 'accepted' || state == 'duplicate';
  static const states = {
    'accepted',
    'duplicate',
    'invalid',
    'identityUnavailable',
    'notAllowed',
    'conflict',
    'unavailable',
    'storageLimitReached',
    'outcomeUnknown',
  };
}

abstract interface class OrganizationGovernancePort {
  bool get available;
  Stream<void> get invalidations;
  Future<OrganizationGovernanceContext> read(String sourceRef);

  /// Host and relay accept per-leader activation (advertised after a context
  /// read that carried a role).
  bool get canActivate;

  /// Enables (or revokes) the caller's own management. Identity, rank and
  /// evidence epoch come from the relay, never from the client.
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  });
  Future<void> close();
}

final class UnavailableOrganizationGovernance
    implements OrganizationGovernancePort {
  const UnavailableOrganizationGovernance();
  @override
  bool get available => false;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) =>
      Future.error(const CommunityFailure('upgradeRequired'));
  @override
  bool get canActivate => false;
  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) => Future.error(const CommunityFailure('upgradeRequired'));
  @override
  Future<void> close() async {}
}
