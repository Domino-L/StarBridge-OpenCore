import 'official_fleet_ships_models.dart';
import 'official_fleet_ships_port.dart';

final class UnavailableOfficialFleetShipsAdapter
    implements OfficialFleetShipsPort {
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetShipsSnapshot> read(
    OfficialFleetShipsQuery query,
  ) async => OfficialFleetShipsSnapshot.unavailable(
    query: query,
    failureKey: 'officialFleet.ships.error.contractUnavailable',
  );

  @override
  Future<void> close() async {}
}
