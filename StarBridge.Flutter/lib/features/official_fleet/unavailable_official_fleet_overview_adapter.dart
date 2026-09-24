import 'official_fleet_overview_models.dart';
import 'official_fleet_overview_port.dart';

final class UnavailableOfficialFleetOverviewAdapter
    implements OfficialFleetOverviewPort {
  @override
  Stream<void> get invalidations => const Stream<void>.empty();

  @override
  Future<OfficialFleetOverviewSnapshot> read(String sourceRef) async =>
      const OfficialFleetOverviewSnapshot.unavailable(
        failureKey: 'officialFleet.overview.error.contractUnavailable',
      );

  @override
  Future<void> close() async {}
}
