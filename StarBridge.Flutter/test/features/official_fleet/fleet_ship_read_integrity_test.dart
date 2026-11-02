import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_port.dart';

void main() {
  for (final mismatch in [
    'source',
    'search',
    'filter',
    'page',
    'size',
    'duplicate',
    'emptyRef',
  ]) {
    test(
      'ship refresh rejects $mismatch before publishing a snapshot',
      () async {
        final port = _Port();
        final module = createOfficialFleetShipsModule(port);
        addTearDown(module.dispose);
        await module.open('officialFleet:7');
        final current = module.projection.value;
        expect(current.ships, isNotEmpty);
        port.pending = Completer<OfficialFleetShipsSnapshot>();
        final refreshing = module.refresh();
        final query = switch (mismatch) {
          'source' => const OfficialFleetShipsQuery(
            sourceRef: 'officialFleet:8',
          ),
          'search' => current.query!.copyWith(search: 'another query'),
          'filter' => current.query!.copyWith(
            filter: OfficialFleetShipFilter.requestable,
          ),
          'page' => current.query!.copyWith(pageNumber: 2),
          'size' => current.query!.copyWith(pageSize: 50),
          _ => current.query!,
        };
        final old = current.ships.first;
        final ships = switch (mismatch) {
          'duplicate' => [old, old],
          'emptyRef' => [
            OfficialFleetSharedShip(
              shipRef: '',
              displayName: old.displayName,
              modelCode: old.modelCode,
              ownerDisplay: old.ownerDisplay,
              ownerCallsign: old.ownerCallsign,
              size: old.size,
              roleLabel: old.roleLabel,
              catalogStatus: old.catalogStatus,
              requestState: old.requestState,
              priceUsd: old.priceUsd,
            ),
          ],
          _ => current.ships,
        };
        port.pending!.complete(
          OfficialFleetShipsSnapshot.available(
            query: query,
            ships: ships,
            totalCount: current.totalCount,
            requestableCount: current.requestableCount,
            ownerCount: current.ownerCount,
            totalValueUsd: current.totalValueUsd,
            totalPages: current.totalPages,
            sizeCounts: current.sizeCounts,
          ),
        );
        await refreshing;
        expect(
          module.projection.value.availability,
          OfficialFleetShipsAvailability.unavailable,
        );
        expect(module.projection.value.ships, isEmpty);
        expect(module.projection.value.isRefreshing, isFalse);
      },
    );
  }
}

final class _Port implements OfficialFleetShipsPort {
  final delegate = InMemoryOfficialFleetShipsAdapter.forReview();
  Completer<OfficialFleetShipsSnapshot>? pending;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetShipsSnapshot> read(OfficialFleetShipsQuery query) =>
      pending?.future ?? delegate.read(query);
  @override
  Future<void> close() => delegate.close();
}
