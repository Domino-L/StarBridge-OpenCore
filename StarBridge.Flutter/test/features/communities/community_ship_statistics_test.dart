import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;

class _Port implements CommunityShipsPort {
  final offsets = <int>[];
  bool changed = false, duplicate = false, denied = false;
  @override
  bool get shipsAvailable => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    offsets.add(offset);
    if (denied && offset > 0) throw StateError('Permission revoked');
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'targetRef': targetRef,
      'query': query!.toPayload(),
      'revision': (changed && offset > 0 ? 'e' : 'b') * 64,
      'offset': offset,
      'totalCount': 25,
      'matchedCount': 25,
      'next': offset == 0 ? 20 : null,
      'ships': List.generate(
        offset == 0 ? 20 : 5,
        (i) => shipRow()
          ..['shipRef'] = (duplicate ? i : offset + i)
              .toRadixString(16)
              .padLeft(32, '0')
          ..['catalogPriceUsd'] = offset == 0 ? '10' : '100',
      ),
    });
  }
}

void main() {
  test('availability partitions ownership while loaner categories count candidates', () {
    Map<String, Object?> row(int id, String? status, {bool online = true}) =>
        shipRow()
          ..['shipRef'] = '$id'.padLeft(32, '0')
          ..['catalogStatus'] = status
          ..['ownerOnline'] = online
          ..['roleCategory'] = 'exploration';
    final stats = CommunityShipStatistics([
      CommunitySharedShip.parse(row(1, 'Flyable')),
      CommunitySharedShip.parse(
        row(2, 'Concept')
          ..['loaners'] = [
            {
              'code': 'loaner-a',
              'displayName': 'A',
              'catalogStatus': 'Flyable',
              'roleCategory': 'industrial',
            },
            {
              'code': 'loaner-b',
              'displayName': 'B',
              'catalogStatus': 'Flyable',
              'roleCategory': 'support',
            },
            {
              'code': 'loaner-c',
              'displayName': 'C',
              'catalogStatus': 'Concept',
              'roleCategory': 'combat',
            },
          ],
      ),
      CommunitySharedShip.parse(row(3, 'Flyable', online: false)),
      CommunitySharedShip.parse(
        row(4, 'Concept'),
      ), // Missing data != unavailable.
      CommunitySharedShip.parse(row(5, 'Concept')..['loaners'] = <Object?>[]),
      CommunitySharedShip.parse(row(6, 'Flyable')..['roleCategory'] = null),
    ]);
    expect(stats.available.length, 3);
    expect(stats.ownerOffline, 1);
    expect(stats.notFlyable, 1);
    expect(stats.availabilityUnknown, 1);
    expect(
      stats.available.length +
          stats.ownerOffline +
          stats.notFlyable +
          stats.availabilityUnknown,
      stats.ships.length,
    );
    expect(stats.candidateRoles, {
      'exploration': 1,
      'industrial': 1,
      'support': 1,
      'unknown': 1,
    });
    expect(stats.hasDispatchLoaners, isTrue);
    expect(stats.ships.length, 6);
    expect(stats.candidates.length, 4);
    expect(stats.roles, {'exploration': 5, 'unknown': 1});
    expect(CommunityShipStatistics([]).candidateRoles, isEmpty);
    expect(CommunityShipStatistics([]).hasDispatchLoaners, isFalse);
  });
  test('size-category intersections reconcile rows, columns and unknowns', () {
    final stats = CommunityShipStatistics([
      for (var i = 0; i < 5; i++)
        CommunitySharedShip.parse(
          shipRow()
            ..['shipRef'] = '$i'.padLeft(32, '0')
            ..['catalogSpec'] = i < 3 ? 'large' : null
            ..['roleCategory'] = i.isEven ? 'combat' : 'unrecognized',
        ),
    ]);
    expect(stats.countAt('large', 'combat'), 2);
    expect(stats.countAt('large', 'unknown'), 1);
    expect(stats.countAt('unknown', 'combat'), 1);
    expect(stats.countAt('unknown', 'unknown'), 1);
    expect(stats.countAt('small', 'combat'), 0);
    for (final size in stats.sizes.keys) {
      expect(
        CommunityShipStatistics.roleOrder.fold(
          0,
          (n, role) => n + stats.countAt(size, role),
        ),
        stats.sizes[size],
      );
    }
    for (final role in stats.roles.keys) {
      expect(
        CommunityShipStatistics.sizeOrder.fold(
          0,
          (n, size) => n + stats.countAt(size, role),
        ),
        stats.roles[role],
      );
    }
  });
  test(
    'models use catalog code, sharing members use owner reference, not labels',
    () {
      final stats = CommunityShipStatistics([
        for (var i = 0; i < 3; i++)
          CommunitySharedShip.parse(
            shipRow()
              ..['shipRef'] = '$i'.padLeft(32, '0')
              ..['ownerMemberRef'] = (i == 2 ? 'e' : 'd') * 32
              ..['code'] = i == 2 ? 'aurora' : (i == 0 ? 'carrack' : 'CARRACK')
              ..['displayName'] = 'Same display name',
          ),
      ]);
      expect(stats.ships.length, 3);
      expect(stats.modelCount, 2);
      expect(stats.sharingMemberCount, 2);
      expect(CommunityShipStatistics([]).modelCount, 0);
    },
  );
  test('statistics include all 25 instances, not just first 20', () async {
    final port = _Port();
    final first = await port.readShips('a' * 32, query: CommunityShipQuery());
    final stats = await readCommunityShipStatistics(
      port,
      'a' * 32,
      'zh-CN',
      checkCurrent: () {},
      firstPage: first,
    );
    expect(port.offsets, [0, 20]);
    expect(stats.ships.length, 25);
    expect(stats.totalCents, 70000);
    expect(stats.sizes, {'large': 25});
    expect(stats.roles, {'utility': 25});
    expect(stats.available.length, 25);
  });
  test(
    'filtered first page is not reused for full-library statistics',
    () async {
      final port = _Port();
      final first = await port.readShips(
        'a' * 32,
        query: CommunityShipQuery(text: 'filter'),
      );
      final stats = await readCommunityShipStatistics(
        port,
        'a' * 32,
        'zh-CN',
        checkCurrent: () {},
        firstPage: first,
      );
      expect(port.offsets, [0, 0, 20]);
      expect(stats.ships.length, 25);
    },
  );
  for (final fault in ['changed', 'duplicate', 'denied']) {
    test('no partial statistics when $fault occurs on next page', () async {
      final port = _Port()
        ..changed = fault == 'changed'
        ..duplicate = fault == 'duplicate'
        ..denied = fault == 'denied';
      await expectLater(
        readCommunityShipStatistics(
          port,
          'a' * 32,
          'zh-CN',
          checkCurrent: () {},
        ),
        throwsA(anything),
      );
    });
  }
  test('cancellation prevents additional page reads', () async {
    final port = _Port();
    await expectLater(
      readCommunityShipStatistics(
        port,
        'a' * 32,
        'zh-CN',
        checkCurrent: () => throw StateError('stale'),
      ),
      throwsStateError,
    );
    expect(port.offsets, [0]);
  });
  test(
    'known values and owner references preserve honest totals and availability',
    () {
      CommunitySharedShip ship(
        String ref,
        String? price, {
        bool online = true,
        String status = 'Flyable',
        String size = 'large',
        String owner = 'd',
      }) => CommunitySharedShip.parse(
        shipRow()
          ..['shipRef'] = ref * 32
          ..['ownerMemberRef'] = owner * 32
          ..['ownerOnline'] = online
          ..['catalogPriceUsd'] = price
          ..['catalogStatus'] = status
          ..['catalogSpec'] = size,
      );
      final stats = CommunityShipStatistics([
        ship('1', r'$1,000'),
        ship('2', null, status: 'Concept'),
        ship('3', '-1', online: false),
        ship('4', '0', owner: 'e'),
        ship('5', '250', size: 'capital', owner: 'e'),
      ]);
      expect(stats.totalCents, 125000);
      expect(stats.pricedCount, 3);
      expect(stats.mostValuable!.shipRef, '1' * 32);
      expect(stats.topOwner!.length, 3);
      expect(stats.owners.length, 2); // Same callsign does not merge owners.
      expect(stats.preferred!.shipRef, '5' * 32);
      expect(stats.ownerOffline, 1);
      expect(stats.availabilityUnknown, 1); // No Loaner data is not a negative.
      expect(stats.available.length, 3);
    },
  );
}
