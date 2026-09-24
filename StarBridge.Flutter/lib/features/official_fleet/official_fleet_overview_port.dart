import 'official_fleet_overview_models.dart';

abstract interface class OfficialFleetOverviewPort {
  Stream<void> get invalidations;

  Future<OfficialFleetOverviewSnapshot> read(String sourceRef);
  Future<void> close();
}
