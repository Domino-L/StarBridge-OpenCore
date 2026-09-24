import 'official_fleet_members_models.dart';

abstract interface class OfficialFleetMembersPort {
  Stream<void> get invalidations;

  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  );

  Future<void> close();
}
