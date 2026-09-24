import 'communities_module.dart';
import 'community_ships_port.dart';
import '../../shared/ships/ship_catalog_display.dart';

/// Read-only presentation of one complete, authorized WPF-style inventory.
class CommunityShipStatistics {
  CommunityShipStatistics(Iterable<CommunitySharedShip> source)
    : ships = List.unmodifiable(source) {
    for (final ship in ships) {
      sizes.update(size(ship), (n) => n + 1, ifAbsent: () => 1);
      roles.update(role(ship), (n) => n + 1, ifAbsent: () => 1);
      sizeRoles
          .putIfAbsent(size(ship), () => <String, int>{})
          .update(role(ship), (n) => n + 1, ifAbsent: () => 1);
      owners.putIfAbsent(ship.ownerMemberRef, () => []).add(ship);
      final cents = price(ship);
      if (cents != null) {
        pricedCount++;
        totalCents += cents;
        if (mostValuable == null || cents > price(mostValuable!)!) {
          mostValuable = ship;
        }
      }
      if (!ship.ownerOnline) {
        ownerOffline++;
      } else if (flyable(ship) ||
          concept(ship) &&
              (ship.loaners?.any((item) => flyable(item.forDispatch(ship))) ??
                  false)) {
        available.add(ship);
        availableRoles.update(role(ship), (n) => n + 1, ifAbsent: () => 1);
        if (concept(ship)) {
          candidates.addAll(
            ship.loaners!.map((item) => item.forDispatch(ship)).where(flyable),
          );
        } else {
          candidates.add(ship);
        }
      } else if (concept(ship) &&
          ship.loaners != null &&
          ship.loaners!.every(
            (item) => const {
              'concept',
              '概念',
            }.contains(item.catalogStatus?.toLowerCase()),
          )) {
        notFlyable++;
      } else {
        // Missing matrix or unresolved replacement status is not a negative.
        availabilityUnknown++;
      }
    }
    candidates.sort((a, b) {
      final spec = sizeRank(b).compareTo(sizeRank(a));
      if (spec != 0) return spec;
      final value = (price(b) ?? 0).compareTo(price(a) ?? 0);
      if (value != 0) return value;
      return a.shipRef.compareTo(b.shipRef);
    });
  }
  final List<CommunitySharedShip> ships;
  static const sizeOrder = [
    'capital',
    'large',
    'medium',
    'small',
    'ground-large',
    'ground-medium',
    'ground-small',
    'unknown',
  ];
  static const roleOrder = [
    'combat',
    'transport',
    'industrial',
    'exploration',
    'support',
    'competition',
    'multi-role',
    'ground-combat',
    'ground-transport',
    'ground-industrial',
    'ground-exploration',
    'ground-support',
    'ground-competition',
    'utility',
    'unknown',
  ];
  final sizeRoles = <String, Map<String, int>>{};
  int countAt(String size, String role) => sizeRoles[size]?[role] ?? 0;
  // Catalog codes identify models; owned instances and loaners are not models.
  int get modelCount => ships
      .map((ship) => ship.code.trim().toLowerCase())
      .where((code) => code.isNotEmpty)
      .toSet()
      .length;
  int get sharingMemberCount => owners.length;
  final sizes = <String, int>{},
      roles = <String, int>{},
      availableRoles = <String, int>{};
  final owners = <String, List<CommunitySharedShip>>{};
  final available = <CommunitySharedShip>[];
  final candidates = <CommunitySharedShip>[];

  /// Presentation candidates include flyable loaners, not additional ownership
  /// or a claim that all alternatives can be dispatched simultaneously.
  Map<String, int> get candidateRoles {
    final counts = <String, int>{};
    for (final ship in candidates) {
      counts.update(role(ship), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  bool get hasDispatchLoaners => available.any(concept);
  int notFlyable = 0;
  int pricedCount = 0,
      totalCents = 0,
      ownerOffline = 0,
      availabilityUnknown = 0;
  CommunitySharedShip? mostValuable;
  CommunitySharedShip? get preferred => candidates.firstOrNull;
  List<CommunitySharedShip>? get topOwner {
    final sorted = owners.values.toList()
      ..sort((a, b) {
        final count = b.length.compareTo(a.length);
        return count != 0
            ? count
            : a.first.ownerMemberRef.compareTo(b.first.ownerMemberRef);
      });
    return sorted.firstOrNull;
  }

  static String owner(CommunitySharedShip ship) =>
      ship.ownerCallsign.isNotEmpty ? ship.ownerCallsign : ship.ownerGameName;
  static bool flyable(CommunitySharedShip ship) =>
      const {'flyable', '可飞', '可飛'}.contains(ship.catalogStatus?.toLowerCase());
  static bool concept(CommunitySharedShip ship) =>
      const {'concept', '概念'}.contains(ship.catalogStatus?.toLowerCase());
  static String size(CommunitySharedShip ship) =>
      switch (ship.displaySpec?.toLowerCase()) {
        'ground-small' => 'ground-small',
        'ground-medium' => 'ground-medium',
        'ground-large' => 'ground-large',
        'capital' || '旗舰级' || '旗艦級' => 'capital',
        'large' || '大型' => 'large',
        'medium' || '中型' => 'medium',
        'small' || '小型' => 'small',
        _ => 'unknown',
      };
  static int sizeRank(CommunitySharedShip ship) => const [
    'unknown',
    'small',
    'medium',
    'large',
    'capital',
  ].indexOf(size(ship).replaceFirst('ground-', ''));
  static String role(CommunitySharedShip ship) =>
      ShipCatalogDisplay.category(ship.displayCategory?.toLowerCase());
  static int? price(CommunitySharedShip ship) {
    return ShipCatalogDisplay.usdCents(ship.catalogPriceUsd);
  }
}

/// Uses the existing authorized read API, never a new backend or a current-page total.
Future<CommunityShipStatistics> readCommunityShipStatistics(
  CommunityShipsPort port,
  String targetRef,
  String culture, {
  required void Function() checkCurrent,
  CommunityShipsPage? firstPage,
}) async {
  final query = CommunityShipQuery(culture: culture);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  var page = firstPage?.query == query && firstPage?.offset == 0
      ? firstPage!
      : await port.readShips(targetRef, query: query);
  final revision = page.revision;
  final total = page.totalCount;
  final ships = <CommunitySharedShip>[];
  final seen = <String>{};
  var offset = 0;
  while (true) {
    checkCurrent();
    if (page.targetRef != targetRef ||
        page.query != query ||
        page.revision != revision ||
        page.totalCount != total ||
        page.matchedCount != total ||
        page.offset != offset) {
      throw const CommunityFailure('shipsChanged');
    }
    for (final ship in page.ships) {
      if (!seen.add(ship.shipRef)) throw const CommunityFailure('dataInvalid');
      ships.add(ship);
    }
    if (page.next == null) break;
    if (DateTime.now().isAfter(deadline) || ships.length >= 10000) {
      throw const CommunityFailure('statisticsUnavailable');
    }
    offset = page.next!;
    page = await port.readShips(
      targetRef,
      query: query,
      offset: offset,
      revision: revision,
    );
  }
  if (ships.length != total) throw const CommunityFailure('dataInvalid');
  return CommunityShipStatistics(ships);
}
