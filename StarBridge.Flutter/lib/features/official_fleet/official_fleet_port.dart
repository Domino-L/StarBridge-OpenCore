import 'official_fleet_models.dart';

abstract interface class OfficialFleetPort {
  Stream<void> get invalidations;

  Future<OfficialFleetSnapshot> read();

  Future<void> close();
}

/// Optional public navigation capability. The Host owns the official URL.
abstract interface class OfficialFleetWebsitePort {
  bool get supportsWebsite;
  Future<bool> openWebsite(String sid);
}
