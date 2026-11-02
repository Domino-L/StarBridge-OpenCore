import 'community_ships_port.dart';

/// The owner view lists the whole inventory, so a ship may sit on a page not
/// loaded here: locate it by name, which the details reauthorize as usual.
/// Null when it is not found or the read fails; [isCurrent] ends a stale search.
Future<CommunityShipsPage?> locateCommunityShipPage(
  CommunityShipsPort port,
  String targetRef,
  CommunitySharedShip ship,
  String culture, {
  required bool Function() isCurrent,
}) async {
  final name = ship.displayName.isEmpty ? ship.code : ship.displayName;
  try {
    var offset = 0;
    for (var step = 0; step < 5; step++) {
      final page = await port.readShips(
        targetRef,
        offset: offset,
        query: CommunityShipQuery(text: name, culture: culture),
      );
      if (!isCurrent()) return null;
      if (page.ships.any((s) => s.shipRef == ship.shipRef)) return page;
      if (page.next == null) return null;
      offset = page.next!;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// What a newly read [page] says about the ship held in the right column.
/// Null: nothing, it is another filter or page. Otherwise the page to show it
/// from, or [page] with [gone] true when the same list no longer has it.
({CommunityShipsPage page, bool gone})? communityShipSelectionAfter(
  CommunityShipsPage page,
  CommunityShipsPage? held,
  String? selected,
) => selected == null ||
        held == null ||
        page.query != held.query ||
        page.offset != held.offset
    ? null
    : (page: page, gone: !page.ships.any((s) => s.shipRef == selected));
