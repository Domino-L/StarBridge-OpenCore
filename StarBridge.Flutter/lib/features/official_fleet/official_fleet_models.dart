import 'package:flutter/foundation.dart';

enum OfficialFleetAvailability {
  loading,
  signedOut,
  notMember,
  unavailable,
  available,
}

enum OfficialFleetFreshness { live }

enum OfficialFleetWorkspaceSection {
  overview,
  operations,
  members,
  channel,
  ships,
  broadcasts,
  profile,
}

@immutable
final class OfficialFleetSummary {
  const OfficialFleetSummary({
    required this.sourceRef,
    required this.sid,
    required this.name,
    required this.officialRankName,
    required this.officialRankValue,
    this.logoUrl,
    this.profile,
  });

  final String sourceRef;
  final String sid;
  final String name;
  final String? logoUrl;
  final String? officialRankName;
  final int? officialRankValue;
  final OfficialFleetProfileDetails? profile;
}

@immutable
final class OfficialFleetProfileDetails {
  const OfficialFleetProfileDetails({
    this.bannerUrl,
    this.recruitingLabel,
    this.memberCount,
    this.rsiDescription,
    this.scmSupplementalDescription,
    this.primaryFocusLabel,
    this.secondaryFocusLabel,
    this.languageLabels = const <String>[],
    this.organizationModelLabel,
    this.commitmentLabel,
    this.roleplayLabel,
    this.archetypeLabel,
    this.tags = const <String>[],
    this.starBridgeRoleName,
  });

  final String? bannerUrl;
  final String? recruitingLabel;
  final int? memberCount;
  final String? rsiDescription;
  final String? scmSupplementalDescription;
  final String? primaryFocusLabel;
  final String? secondaryFocusLabel;
  final List<String> languageLabels;
  final String? organizationModelLabel;
  final String? commitmentLabel;
  final String? roleplayLabel;
  final String? archetypeLabel;
  final List<String> tags;
  final String? starBridgeRoleName;

  bool get hasNarrative =>
      rsiDescription != null || scmSupplementalDescription != null;

  bool get hasFocus => primaryFocusLabel != null || secondaryFocusLabel != null;

  bool get hasAttributes =>
      languageLabels.isNotEmpty ||
      organizationModelLabel != null ||
      commitmentLabel != null ||
      roleplayLabel != null ||
      archetypeLabel != null;
}

@immutable
final class OfficialFleetSnapshot {
  const OfficialFleetSnapshot.signedOut()
    : availability = OfficialFleetAvailability.signedOut,
      fleet = null,
      freshness = null,
      resourceVersion = null,
      observedAtUtc = null,
      failureKey = null;

  const OfficialFleetSnapshot.notMember({
    required this.freshness,
    required this.observedAtUtc,
    this.resourceVersion,
  }) : availability = OfficialFleetAvailability.notMember,
       fleet = null,
       failureKey = null;

  const OfficialFleetSnapshot.unavailable({required this.failureKey})
    : availability = OfficialFleetAvailability.unavailable,
      fleet = null,
      freshness = null,
      resourceVersion = null,
      observedAtUtc = null;

  const OfficialFleetSnapshot.available({
    required this.fleet,
    required this.freshness,
    required this.observedAtUtc,
    this.resourceVersion,
  }) : availability = OfficialFleetAvailability.available,
       failureKey = null;

  final OfficialFleetAvailability availability;
  final OfficialFleetSummary? fleet;
  final OfficialFleetFreshness? freshness;
  final int? resourceVersion;
  final DateTime? observedAtUtc;
  final String? failureKey;
}

@immutable
final class OfficialFleetProjection {
  const OfficialFleetProjection.loading()
    : availability = OfficialFleetAvailability.loading,
      fleet = null,
      freshness = null,
      resourceVersion = null,
      observedAtUtc = null,
      failureKey = null;

  const OfficialFleetProjection._({
    required this.availability,
    required this.fleet,
    required this.freshness,
    required this.resourceVersion,
    required this.observedAtUtc,
    required this.failureKey,
  });

  factory OfficialFleetProjection.fromSnapshot(OfficialFleetSnapshot value) =>
      OfficialFleetProjection._(
        availability: value.availability,
        fleet: value.fleet,
        freshness: value.freshness,
        resourceVersion: value.resourceVersion,
        observedAtUtc: value.observedAtUtc,
        failureKey: value.failureKey,
      );

  final OfficialFleetAvailability availability;
  final OfficialFleetSummary? fleet;
  final OfficialFleetFreshness? freshness;
  final int? resourceVersion;
  final DateTime? observedAtUtc;
  final String? failureKey;
}
