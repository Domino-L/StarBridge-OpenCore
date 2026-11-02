import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_reconciliation.dart';

import 'local_hangar_reconciliation_test.dart' as fixtures;

void main() {
  test(
    'history preserves every ID and sorts a copy without hiding owned models',
    () {
      final old = LocalHangarShip(
        id: 'old',
        title: 'Carrack',
        removedAt: DateTime.utc(2026, 1, 1),
      );
      final recent = LocalHangarShip(
        id: 'recent',
        title: 'Carrack',
        removedAt: DateTime.utc(2026, 2, 1),
      );
      final snapshot = LocalHangarSnapshot(
        revision: 2,
        ships: const [LocalHangarShip(id: 'current', title: 'Carrack')],
        formerShips: List.unmodifiable([old, recent]),
      );
      expect(snapshot.formerInstances.map((s) => s.id), ['recent', 'old']);
      expect(snapshot.formerShips, [old, recent]);
      expect(identical(snapshot.formerInstances.first, recent), isTrue);
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'localized groups have no conflicting numbers and single choices can be replaced $locale',
      (tester) async {
        tester.view.physicalSize = const Size(900, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = fixtures.ReviewPort()
          ..snapshot = LocalHangarSnapshot(
            revision: 4,
            ships: [
              for (final id in ['a', 'b', 'c', 'd'])
                LocalHangarShip(
                  id: id,
                  title: id == 'a' || id == 'b' ? 'Carrack' : 'Vulture',
                  cn: id == 'a' || id == 'b' ? '克拉克' : '秃鹫',
                  tw: id == 'a' || id == 'b' ? '克拉克' : '禿鷲',
                  addedAt: DateTime.utc(2026, 1, 1),
                  isFavorite: id == 'b',
                ),
            ],
          );
        await tester.pumpWidget(fixtures.shell(locale, port));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('local-hangar-review-removals')));
        await tester.pumpAndSettle();
        final dialog = find.byType(Dialog);
        final texts = tester
            .widgetList<Text>(
              find.descendant(of: dialog, matching: find.byType(Text)),
            )
            .map((t) => t.data ?? '')
            .toList();
        expect(texts.any((s) => s.contains('#')), isFalse);
        if (locale.languageCode == 'zh') {
          expect(
            texts.any((s) => s.contains('Carrack') || s.contains('Vulture')),
            isFalse,
          );
          expect(texts.any((s) => s.startsWith('克拉克 · 原有')), isTrue);
          expect(
            texts.any(
              (s) => s.startsWith(
                '${locale.countryCode == 'TW' ? '禿鷲' : '秃鹫'} · 原有',
              ),
            ),
            isTrue,
          );
        } else {
          expect(
            texts.any((s) => s.startsWith('Carrack · Previously')),
            isTrue,
          );
        }
        final a = find.byKey(const ValueKey('hangar-remove-a'));
        final b = find.byKey(const ValueKey('hangar-remove-b'));
        await tester.tap(
          find.ancestor(of: a, matching: find.byType(StarBridgeCheckboxTile)),
        );
        await tester.pump();
        expect(tester.widget<Checkbox>(a).value, isTrue);
        expect(tester.widget<Checkbox>(b).onChanged, isNotNull);
        await tester.tap(
          find.ancestor(of: b, matching: find.byType(StarBridgeCheckboxTile)),
        );
        await tester.pump();
        expect(tester.widget<Checkbox>(a).value, isFalse);
        expect(tester.widget<Checkbox>(b).value, isTrue);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('hangar-removal-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('hangar-removal-cancel')));
        await tester.pumpAndSettle();
        expect(port.writes, 0);
        expect(port.chosen, isNull);
      },
    );
  }

  testWidgets('multi-removal groups still require exactly enough choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = fixtures.ReviewPort()
      ..preview = const [
        LocalHangarRemovalGroup(
          id: 'a',
          requiredCount: 2,
          shipIds: ['a', 'b', 'c', 'd'],
        ),
      ];
    await tester.pumpWidget(fixtures.shell(const Locale('en'), port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local-hangar-review-removals')));
    await tester.pumpAndSettle();
    Finder row(String id) => find.byKey(ValueKey('hangar-remove-$id'));
    for (final id in ['a', 'b']) {
      await tester.tap(
        find.ancestor(
          of: row(id),
          matching: find.byType(StarBridgeCheckboxTile),
        ),
      );
      await tester.pump();
    }
    expect(tester.widget<Checkbox>(row('a')).value, isTrue);
    expect(tester.widget<Checkbox>(row('b')).value, isTrue);
    expect(tester.widget<Checkbox>(row('c')).onChanged, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('hangar-removal-confirm')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.ancestor(
        of: row('a'),
        matching: find.byType(StarBridgeCheckboxTile),
      ),
    );
    await tester.pump();
    expect(tester.widget<Checkbox>(row('c')).onChanged, isNotNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('hangar-removal-confirm')))
          .onPressed,
      isNull,
    );
  });
}
