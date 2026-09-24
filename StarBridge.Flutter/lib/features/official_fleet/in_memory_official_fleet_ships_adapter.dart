import 'official_fleet_ships_models.dart';
import 'official_fleet_ships_port.dart';

final class InMemoryOfficialFleetShipsAdapter
    implements OfficialFleetShipsPort {
  const InMemoryOfficialFleetShipsAdapter(this._ships);

  factory InMemoryOfficialFleetShipsAdapter.forReview() =>
      const InMemoryOfficialFleetShipsAdapter(_reviewShips);

  final List<OfficialFleetSharedShip> _ships;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetShipsSnapshot> read(OfficialFleetShipsQuery query) async {
    final normalizedSearch = query.search.toLowerCase();
    final filtered =
        _ships.where((ship) {
          final matchesSearch =
              normalizedSearch.isEmpty ||
              ship.displayName.toLowerCase().contains(normalizedSearch) ||
              ship.modelCode.toLowerCase().contains(normalizedSearch) ||
              ship.ownerDisplay.toLowerCase().contains(normalizedSearch) ||
              ship.ownerCallsign.toLowerCase().contains(normalizedSearch) ||
              ship.roleLabel.toLowerCase().contains(normalizedSearch);
          final matchesFilter = switch (query.filter) {
            OfficialFleetShipFilter.all => true,
            OfficialFleetShipFilter.requestable =>
              ship.requestState == OfficialFleetShipRequestState.requestable,
            OfficialFleetShipFilter.sharedByMe =>
              ship.requestState == OfficialFleetShipRequestState.ownedByViewer,
          };
          return matchesSearch && matchesFilter;
        }).toList()..sort((left, right) {
          final requestState = left.requestState.index.compareTo(
            right.requestState.index,
          );
          if (requestState != 0) {
            return requestState;
          }
          final name = left.displayName.compareTo(right.displayName);
          return name != 0 ? name : left.shipRef.compareTo(right.shipRef);
        });
    final start = (query.pageNumber - 1) * query.pageSize;
    final pageShips = start >= filtered.length
        ? const <OfficialFleetSharedShip>[]
        : filtered.sublist(
            start,
            (start + query.pageSize).clamp(0, filtered.length),
          );
    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length + query.pageSize - 1) ~/ query.pageSize);
    final sizeCounts = <OfficialFleetShipSize, int>{};
    for (final ship in _ships) {
      sizeCounts.update(ship.size, (count) => count + 1, ifAbsent: () => 1);
    }
    return OfficialFleetShipsSnapshot.available(
      query: query,
      ships: pageShips,
      totalCount: _ships.length,
      requestableCount: _ships
          .where(
            (ship) =>
                ship.requestState == OfficialFleetShipRequestState.requestable,
          )
          .length,
      ownerCount: _ships.map((ship) => ship.ownerCallsign).toSet().length,
      totalValueUsd: _ships.fold<int>(
        0,
        (total, ship) => total + ship.priceUsd,
      ),
      totalPages: totalPages,
      sizeCounts: sizeCounts,
    );
  }

  @override
  Future<void> close() async {}
}

const _reviewShips = <OfficialFleetSharedShip>[
  OfficialFleetSharedShip(
    shipRef: 'ship:carrack-1',
    displayName: '克拉克',
    modelCode: 'Anvil Carrack',
    ownerDisplay: '多米诺',
    ownerCallsign: 'domino_CN',
    size: OfficialFleetShipSize.large,
    roleLabel: '远征',
    catalogStatus: OfficialFleetShipCatalogStatus.flightReady,
    requestState: OfficialFleetShipRequestState.ownedByViewer,
    priceUsd: 600,
  ),
  OfficialFleetSharedShip(
    shipRef: 'ship:vulture-1',
    displayName: '秃鹫',
    modelCode: 'Drake Vulture',
    ownerDisplay: '远航者',
    ownerCallsign: 'Citizen-2802',
    size: OfficialFleetShipSize.small,
    roleLabel: '打捞',
    catalogStatus: OfficialFleetShipCatalogStatus.flightReady,
    requestState: OfficialFleetShipRequestState.requestable,
    priceUsd: 175,
  ),
  OfficialFleetSharedShip(
    shipRef: 'ship:zeus-mr-1',
    displayName: '宙斯 Mk II MR',
    modelCode: 'RSI Zeus Mk II MR',
    ownerDisplay: '北辰',
    ownerCallsign: 'Citizen-2801',
    size: OfficialFleetShipSize.medium,
    roleLabel: '多用途',
    catalogStatus: OfficialFleetShipCatalogStatus.concept,
    requestState: OfficialFleetShipRequestState.unavailable,
    priceUsd: 190,
  ),
  OfficialFleetSharedShip(
    shipRef: 'ship:polaris-1',
    displayName: '北极星',
    modelCode: 'RSI Polaris',
    ownerDisplay: '星港守望',
    ownerCallsign: 'Citizen-2803',
    size: OfficialFleetShipSize.capital,
    roleLabel: '军用',
    catalogStatus: OfficialFleetShipCatalogStatus.flightReady,
    requestState: OfficialFleetShipRequestState.requestable,
    priceUsd: 975,
  ),
  OfficialFleetSharedShip(
    shipRef: 'ship:super-hornet-1',
    displayName: 'F7C-M 超级大黄蜂 Mk II',
    modelCode: 'Anvil F7C-M Super Hornet Mk II',
    ownerDisplay: '曙光',
    ownerCallsign: 'Citizen-2800',
    size: OfficialFleetShipSize.small,
    roleLabel: '战斗',
    catalogStatus: OfficialFleetShipCatalogStatus.flightReady,
    requestState: OfficialFleetShipRequestState.requestable,
    priceUsd: 185,
  ),
  OfficialFleetSharedShip(
    shipRef: 'ship:ironclad-assault-1',
    displayName: '铁甲突袭',
    modelCode: 'Drake Ironclad Assault',
    ownerDisplay: '多米诺',
    ownerCallsign: 'domino_CN',
    size: OfficialFleetShipSize.large,
    roleLabel: '运输',
    catalogStatus: OfficialFleetShipCatalogStatus.concept,
    requestState: OfficialFleetShipRequestState.ownedByViewer,
    priceUsd: 535,
  ),
];
