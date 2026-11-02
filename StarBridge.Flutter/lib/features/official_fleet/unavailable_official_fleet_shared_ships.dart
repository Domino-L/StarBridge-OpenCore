import '../communities/community_ships_port.dart';
import '../communities/communities_module.dart';

/// A missing public adapter is unavailable, never an empty pool or example data.
final class UnavailableOfficialFleetSharedShips implements CommunityShipsPort {
  const UnavailableOfficialFleetSharedShips();
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => false;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async => throw const CommunityFailure('unavailable');
}
