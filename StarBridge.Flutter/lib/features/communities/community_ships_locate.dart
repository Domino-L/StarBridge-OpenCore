import 'communities_module.dart';
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

/// Reads the list again from the top (the first page names the current
/// revision; later pages are read against it) and finds the page that now
/// holds [shipRef]. The Host keeps a ship's reference for its whole process,
/// so only the reference is matched: two ships alike are never guessed
/// between (user report 2026-11-15; review R1). Null when it is not there;
/// every failed read (account, permission, transport) still ends it as such.
Future<CommunityShipsPage?> relocateCommunityShip(
  CommunityShipsPort port,
  CommunityShipsPage held,
  String shipRef, {
  required void Function() checkCurrent,
}) async {
  try {
    String? revision;
    Future<CommunityShipsPage?> read(int offset) async {
      final page = await port.readShips(
        held.targetRef,
        offset: offset,
        revision: revision,
        query: held.query,
      );
      checkCurrent();
      if (page.targetRef != held.targetRef ||
          page.query != held.query ||
          page.offset != offset ||
          revision != null && page.revision != revision) {
        return null;
      }
      revision ??= page.revision;
      return page;
    }

    bool holds(CommunityShipsPage page) =>
        page.ships.any((s) => s.shipRef == shipRef);
    final first = await read(0);
    if (first == null || holds(first)) return first;
    // Its own place first, however deep (review R2), then the pages next to
    // it, where a few additions or removals move a ship (review R3), then the
    // top of the list. Six more reads at most.
    final candidates = <int>[];
    void add(int offset) {
      if (offset > 0 &&
          offset < first.matchedCount &&
          !candidates.contains(offset)) {
        candidates.add(offset);
      }
    }

    add(held.offset);
    add(held.offset + 20);
    add(held.offset - 20);
    for (var offset = 20; candidates.length < 6; offset += 20) {
      if (offset >= first.matchedCount) break;
      add(offset);
    }
    for (final offset in candidates) {
      final page = await read(offset);
      if (page == null || holds(page)) return page;
    }
  } on CommunityFailure catch (e) {
    // Only "changed again" means not found here. A failed read stays a failed
    // read (retry, not "the library changed"; review R4 P2).
    if (e.code == 'shipsChanged') return null;
    rethrow;
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
) =>
    selected == null ||
        held == null ||
        page.query != held.query ||
        page.offset != held.offset
    ? null
    : (page: page, gone: !page.ships.any((s) => s.shipRef == selected));

/// The same question over every page now held. The ship may have moved to
/// another loaded page; it is gone only when no page of the same list holds it
/// and one covers its old place (review R1: one page alone never decides).
({CommunityShipsPage page, bool gone})? communityShipSelectionAcross(
  List<CommunityShipsPage> pages,
  CommunityShipsPage? held,
  String? selected,
) {
  if (selected == null || held == null) return null;
  final same = pages.where((p) => p.query == held.query);
  final holding = same
      .where((p) => p.ships.any((s) => s.shipRef == selected))
      .firstOrNull;
  if (holding != null) return (page: holding, gone: false);
  final covering = same.where((p) => p.offset == held.offset).firstOrNull;
  return covering == null ? null : (page: covering, gone: true);
}
