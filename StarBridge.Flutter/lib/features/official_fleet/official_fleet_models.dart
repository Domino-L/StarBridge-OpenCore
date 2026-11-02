import 'package:flutter/foundation.dart';

enum OfficialFleetAvailability {
  loading,
  signedOut,
  notMember,
  unavailable,
  available,
}

enum OfficialFleetFreshness { live }

enum OfficialFleetProfileReadState {
  deferred,
  unknown,
  available,
  transientFailure,
  unavailable,
  forbidden,
  invalid,
}

enum OfficialFleetWorkspaceSection {
  overview,
  operations,
  members,
  channel,
  ships,
  broadcasts,
  manage,
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

  /// The membership logo, else the fleet's public RSI logo (RSI's default
  /// logo for fleets that never uploaded one).
  String? get displayLogoUrl => logoUrl ?? profile?.logoUrl;

  OfficialFleetSummary.withProfile(OfficialFleetSummary value, this.profile)
    : sourceRef = value.sourceRef,
      sid = value.sid,
      name = value.name,
      logoUrl = value.logoUrl,
      officialRankName = value.officialRankName,
      officialRankValue = value.officialRankValue;
}

@immutable
final class OfficialFleetProfileDetails {
  const OfficialFleetProfileDetails({
    this.bannerUrl,
    this.backgroundUrl,
    this.logoUrl,
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

  /// The RSI organization page background, drawn dimmed behind the page.
  final String? backgroundUrl;
  final String? logoUrl;
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
      profileReadState = OfficialFleetProfileReadState.unknown,
      profileObservedAtUtc = null,
      transientFailure = false,
      discardContext = true,
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
       profileReadState = OfficialFleetProfileReadState.unknown,
       profileObservedAtUtc = null,
       transientFailure = false,
       discardContext = true,
       fleet = null,
       failureKey = null;

  const OfficialFleetSnapshot.unavailable({
    required this.failureKey,
    this.transientFailure = false,
    this.discardContext = false,
  }) : availability = OfficialFleetAvailability.unavailable,
       profileReadState = OfficialFleetProfileReadState.unknown,
       profileObservedAtUtc = null,
       fleet = null,
       freshness = null,
       resourceVersion = null,
       observedAtUtc = null;

  const OfficialFleetSnapshot.available({
    required this.fleet,
    required this.freshness,
    required this.observedAtUtc,
    this.resourceVersion,
    this.profileReadState = OfficialFleetProfileReadState.unknown,
    this.profileObservedAtUtc,
  }) : availability = OfficialFleetAvailability.available,
       transientFailure = false,
       discardContext = false,
       failureKey = null;

  final OfficialFleetAvailability availability;
  final bool transientFailure, discardContext;
  final OfficialFleetProfileReadState profileReadState;
  final DateTime? profileObservedAtUtc;
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
      profileReadState = OfficialFleetProfileReadState.unknown,
      profileObservedAtUtc = null,
      isRefreshing = false,
      isProfileReading = false,
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
    required this.profileReadState,
    required this.profileObservedAtUtc,
    this.isProfileReading = false,
  }) : isRefreshing = false;

  OfficialFleetProjection.refreshing(OfficialFleetProjection value)
    : this.retained(value, failureKey: value.failureKey, isRefreshing: true);

  OfficialFleetProjection.retained(
    OfficialFleetProjection value, {
    required this.failureKey,
    this.isRefreshing = false,
    this.isProfileReading = false,
  }) : availability = value.availability,
       profileReadState = value.profileReadState,
       profileObservedAtUtc = value.profileObservedAtUtc,
       fleet = value.fleet,
       freshness = value.freshness,
       resourceVersion = value.resourceVersion,
       observedAtUtc = value.observedAtUtc;

  factory OfficialFleetProjection.fromSnapshot(
    OfficialFleetSnapshot value, {
    OfficialFleetProjection? previous,
    bool isProfileReading = false,
  }) {
    final current = value.fleet;
    final old = previous?.fleet;
    final retainProfile =
        value.availability == OfficialFleetAvailability.available &&
        (value.profileReadState ==
                OfficialFleetProfileReadState.transientFailure ||
            value.profileReadState == OfficialFleetProfileReadState.deferred) &&
        current != null &&
        current.profile == null &&
        previous?.availability == OfficialFleetAvailability.available &&
        old != null &&
        old.sourceRef == current.sourceRef &&
        old.sid == current.sid &&
        old.profile != null;
    return OfficialFleetProjection._(
      availability: value.availability,
      fleet: retainProfile
          ? OfficialFleetSummary.withProfile(current, old.profile)
          : current,
      profileReadState: value.profileReadState,
      isProfileReading: isProfileReading,
      profileObservedAtUtc: retainProfile
          ? previous!.profileObservedAtUtc
          : value.profileObservedAtUtc,
      freshness: value.freshness,
      resourceVersion: value.resourceVersion,
      observedAtUtc: value.observedAtUtc,
      failureKey: value.failureKey,
    );
  }

  final OfficialFleetAvailability availability;
  final bool isRefreshing;
  final bool isProfileReading;
  final OfficialFleetProfileReadState profileReadState;
  final DateTime? profileObservedAtUtc;
  bool get profileRefreshFailed =>
      availability == OfficialFleetAvailability.available &&
      profileReadState != OfficialFleetProfileReadState.available &&
      profileReadState != OfficialFleetProfileReadState.deferred &&
      profileReadState != OfficialFleetProfileReadState.unknown;
  bool get profileRetained =>
      (profileReadState == OfficialFleetProfileReadState.transientFailure ||
          profileReadState == OfficialFleetProfileReadState.deferred) &&
      fleet?.profile != null;
  bool get refreshFailed =>
      availability == OfficialFleetAvailability.available && failureKey != null;
  final OfficialFleetSummary? fleet;
  final OfficialFleetFreshness? freshness;
  final int? resourceVersion;
  final DateTime? observedAtUtc;
  final String? failureKey;
}
