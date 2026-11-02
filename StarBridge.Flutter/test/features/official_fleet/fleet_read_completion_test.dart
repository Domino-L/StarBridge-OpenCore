import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';

void main() {
  for (final transient in [false, true]) {
    for (final synchronous in [false, true]) {
      test(
        'hard invalidation at read completion settles the new identity (transient=$transient, sync=$synchronous)',
        () async {
          final port = _Port();
          final module = createOfficialFleetModule(
            port,
            UnavailableOfficialFleetOverviewAdapter(),
            UnavailableOfficialFleetMembersAdapter(),
            UnavailableOfficialFleetShipsAdapter(),
          );
          addTearDown(module.dispose);
          var invalidated = false;
          module.projection.addListener(() {
            final value = module.projection.value;
            if (!invalidated &&
                value.availability == OfficialFleetAvailability.available &&
                (!transient || value.refreshFailed)) {
              invalidated = true;
              if (synchronous) {
                port.changes.add(null);
              } else {
                scheduleMicrotask(() => port.changes.add(null));
              }
            }
          });
          await module.initialize();
          if (transient) {
            port.transientNext = true;
            await module.refresh();
          }
          await Future<void>.delayed(Duration.zero);
          expect(invalidated, isTrue);
          expect(port.reads, transient ? 3 : 2);
          expect(
            module.projection.value.availability,
            OfficialFleetAvailability.available,
          );
          expect(module.projection.value.isRefreshing, isFalse);
          expect(module.projection.value.refreshFailed, isFalse);
          expect(module.contextRevision, 1);
        },
      );
    }
  }
}

final class _Port implements OfficialFleetPort {
  final changes = StreamController<void>.broadcast(sync: true);
  int reads = 0;
  bool transientNext = false;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OfficialFleetSnapshot> read() async {
    reads++;
    if (transientNext) {
      transientNext = false;
      return const OfficialFleetSnapshot.unavailable(
        failureKey: 'officialFleet.error.transient',
        transientFailure: true,
      );
    }
    return InMemoryOfficialFleetAdapter.forReview(signedIn: true).read();
  }

  @override
  Future<void> close() => changes.close();
}
