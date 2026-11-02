import 'community_ship_statistics.dart';
import 'community_ships_port.dart';

/// The owner view filters the full inventory on the client, with the same
/// keys the server accepts for pages (option D, 2026-10-29).
bool communityShipMatchesFilter(CommunitySharedShip ship, String filter) =>
    switch (filter) {
      'all' => true,
      'flyable' => CommunityShipStatistics.flyable(ship),
      'concept' => CommunityShipStatistics.concept(ship),
      'unknown' =>
        !CommunityShipStatistics.flyable(ship) &&
            !CommunityShipStatistics.concept(ship),
      final size =>
        CommunityShipStatistics.size(ship).replaceFirst('ground-', '') == size,
    };

bool communityShipMatchesText(CommunitySharedShip ship, String text) =>
    text.isEmpty ||
    [
      ship.displayName,
      ship.code,
      ship.ownerCallsign,
      ship.ownerGameName,
      ship.displayRole ?? '',
      ship.manufacturer ?? '',
      ship.englishName ?? '',
    ].any((value) => value.toLowerCase().contains(text));

List<CommunitySharedShip> communityShipsFiltered(
  CommunityShipStatistics statistics,
  String filter,
  String search,
) {
  final text = search.trim().toLowerCase();
  return [
    for (final ship in statistics.ships)
      if (communityShipMatchesFilter(ship, filter) &&
          communityShipMatchesText(ship, text))
        ship,
  ];
}

/// Per filter key, for the chip labels.
Map<String, int> communityShipFilterCounts(CommunityShipStatistics stats) {
  var flyable = 0, concept = 0;
  for (final ship in stats.ships) {
    if (CommunityShipStatistics.flyable(ship)) {
      flyable++;
    } else if (CommunityShipStatistics.concept(ship)) {
      concept++;
    }
  }
  int size(String key) =>
      (stats.sizes[key] ?? 0) + (stats.sizes['ground-$key'] ?? 0);
  return {
    'all': stats.shipCount,
    'capital': size('capital'),
    'large': size('large'),
    'medium': size('medium'),
    'small': size('small'),
    'flyable': flyable,
    'concept': concept,
    'unknown': stats.shipCount - flyable - concept,
  };
}
