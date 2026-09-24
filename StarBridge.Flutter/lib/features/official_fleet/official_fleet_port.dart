import 'official_fleet_models.dart';

abstract interface class OfficialFleetPort {
  Stream<void> get invalidations;

  Future<OfficialFleetSnapshot> read();

  Future<void> close();
}
