import 'official_fleet_models.dart';

/// Optional second phase. Identity is already confirmed; this returns public
/// content only and cannot update membership, rank or communication authority.
abstract interface class OfficialFleetProfilePort {
  bool get supportsDeferredProfile;
  Future<OfficialFleetPublicProfile> readProfile(String sourceRef);
  Future<void> cancelProfileRead();
}

final class OfficialFleetPublicProfile {
  const OfficialFleetPublicProfile({
    required this.sourceRef,
    required this.state,
    this.sid,
    this.profile,
    this.observedAtUtc,
    this.failureKey,
    this.ownerUnavailable = false,
    this.discardContext = false,
    this.discarded = false,
  });
  final String sourceRef;
  final String? sid;
  final OfficialFleetProfileReadState state;
  final OfficialFleetProfileDetails? profile;
  final DateTime? observedAtUtc;
  final String? failureKey;
  final bool ownerUnavailable, discardContext, discarded;
}
