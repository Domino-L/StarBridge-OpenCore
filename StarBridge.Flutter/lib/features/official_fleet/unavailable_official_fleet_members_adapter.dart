import 'official_fleet_members_models.dart';
import 'official_fleet_members_port.dart';

final class UnavailableOfficialFleetMembersAdapter
    implements OfficialFleetMembersPort {
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async => OfficialFleetMemberDirectorySnapshot.unavailable(
    query: query,
    failureKey: 'officialFleet.members.error.contractUnavailable',
  );

  @override
  Future<void> close() async {}
}
