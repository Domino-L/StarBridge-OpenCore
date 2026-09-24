import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';

void main() {
  test('ships module preserves source-scoped server query semantics', () async {
    final module = createOfficialFleetShipsModule(
      InMemoryOfficialFleetShipsAdapter.forReview(),
    );
    addTearDown(module.dispose);

    await module.open('officialFleet:7');
    expect(
      module.projection.value.availability,
      OfficialFleetShipsAvailability.available,
    );
    expect(module.projection.value.totalCount, 6);
    expect(module.projection.value.requestableCount, 3);
    expect(module.projection.value.ownerCount, 5);
    expect(module.projection.value.totalValueUsd, 2660);
    expect(module.projection.value.query?.sourceRef, 'officialFleet:7');

    await module.setFilter(OfficialFleetShipFilter.requestable);
    expect(module.projection.value.ships, hasLength(3));
    expect(
      module.projection.value.ships.every(
        (ship) =>
            ship.requestState == OfficialFleetShipRequestState.requestable,
      ),
      isTrue,
    );

    await module.search('秃鹫');
    expect(module.projection.value.ships, hasLength(1));
    expect(module.projection.value.ships.single.modelCode, 'Drake Vulture');
  });
}
