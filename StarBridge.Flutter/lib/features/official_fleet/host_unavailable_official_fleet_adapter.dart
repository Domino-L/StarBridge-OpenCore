import 'official_fleet_models.dart';
import 'official_fleet_port.dart';

final class HostUnavailableOfficialFleetAdapter implements OfficialFleetPort {
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetSnapshot> read() async =>
      const OfficialFleetSnapshot.unavailable(
        failureKey: 'officialFleet.error.hostUnavailable',
      );

  @override
  Future<void> close() async {}
}
