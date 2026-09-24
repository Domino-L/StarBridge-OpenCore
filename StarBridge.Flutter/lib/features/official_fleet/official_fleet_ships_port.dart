import 'official_fleet_ships_models.dart';

abstract interface class OfficialFleetShipsPort {
  Stream<void> get invalidations;

  Future<OfficialFleetShipsSnapshot> read(OfficialFleetShipsQuery query);

  Future<void> close();
}
