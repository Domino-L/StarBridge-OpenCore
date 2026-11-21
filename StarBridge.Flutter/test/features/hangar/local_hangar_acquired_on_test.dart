import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/legacy_profile_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_inventory_projection.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';

// User 11-12: "个人机库的加入时间应该展示官网机库的入库时间 而非导入客户端的时间".
void main() {
  test('Host pledge dates read as local calendar dates', () {
    expect(parseAcquiredOn('2024-09-01'), DateTime(2024, 9, 1));
    expect(parseAcquiredOn('2020-02-29'), DateTime(2020, 2, 29));
    for (final value in <Object?>[
      null,
      '',
      'Sep 01, 2024',
      '2021-02-29',
      '2024-13-01',
      '0001-01-01T00:00:00+00:00',
      20240901,
    ]) {
      expect(parseAcquiredOn(value), isNull, reason: '$value');
    }
  });

  test('0.7.2 profile time is never shown as the official date', () {
    // 0.7.2 wrote the import moment when RSI showed no date.
    final ship = profileHangarShip({
      'code': 'fixture',
      'displayName': 'Fixture',
      'importedAt': '2023-05-04T00:00:00+08:00',
    }, 'legacy-1');
    expect(ship.acquiredOn, isNull);
    expect(ship.addedAt, isNotNull);
    final unknown = profileHangarShip({
      'code': 'fixture',
      'displayName': 'Fixture',
      'importedAt': '0001-01-01T00:00:00+00:00',
    }, 'legacy-2');
    expect(unknown.acquiredOn, isNull);
  });

  testWidgets('recently acquired sort uses the pledge date, unknown last', (
    tester,
  ) async {
    late LocalHangarCopy copy;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            copy = LocalHangarCopy(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final ships = [
      LocalHangarShip(
        id: 'a-unknown',
        title: 'Unknown',
        addedAt: DateTime.utc(2026, 11, 1),
      ),
      LocalHangarShip(
        id: 'b-old',
        title: 'Old',
        addedAt: DateTime.utc(2026, 11, 2),
        acquiredOn: DateTime(2015, 3, 1),
      ),
      LocalHangarShip(
        id: 'c-new',
        title: 'New',
        addedAt: DateTime.utc(2026, 10, 1),
        acquiredOn: DateTime(2024, 9, 1),
      ),
      const LocalHangarShip(id: 'd-unknown', title: 'Unknown too'),
    ];
    final projection = LocalHangarInventoryProjection(
      source: ships,
      copy: copy,
      query: '',
      favoritesOnly: false,
      category: null,
      size: null,
      status: null,
      sort: 'added',
    );
    expect(projection.ships.map((s) => s.id), [
      'c-new',
      'b-old',
      'a-unknown',
      'd-unknown',
    ]);
  });
}
