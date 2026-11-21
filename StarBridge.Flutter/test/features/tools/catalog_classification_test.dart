import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/tools/catalog_blueprint_categories.dart';
import 'package:starbridge_flutter/features/tools/catalog_blueprint_grid.dart';
import 'package:starbridge_flutter/features/tools/catalog_controller.dart';
import 'package:starbridge_flutter/features/tools/catalog_details.dart';
import 'package:starbridge_flutter/features/tools/catalog_detail_values.dart';
import 'package:starbridge_flutter/features/tools/catalog_filters.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_table.dart';
import 'package:starbridge_flutter/features/tools/mission_records_controller.dart';
import 'package:starbridge_flutter/features/tools/tools_style.dart';

import 'catalog_browse_test.dart' as browse;
import 'catalog_samples.dart';

Future<void> advance(WidgetTester tester) async {
  // Advance bridge microtasks and delayed filter reads without awaiting a
  // controller future on the widget test clock.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Widget filters(CatalogController controller) => browse.app(
  ListenableBuilder(
    listenable: controller,
    builder: (context, _) =>
        SingleChildScrollView(child: CatalogFilters(controller)),
  ),
);

Future<void> choose(WidgetTester tester, String key) async {
  await tester.pump();
  final target = find.byKey(Key('catalog-filter-$key'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await advance(tester);
}

final class HeldFiltersPort extends SampleCatalogPort {
  final held = Completer<CatalogRow>();
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) {
    if (operation == 'blueprints.filters' &&
        parameters['categoryName'] == 'FPSWeapons') {
      calls.add((
        operation: operation,
        parameters: {...parameters},
        refresh: refresh,
      ));
      return held.future;
    }
    return super.read(operation, parameters, refresh: refresh);
  }
}

final class LimitedFiltersPort extends SampleCatalogPort {
  LimitedFiltersPort(this.limitedReads);
  int limitedReads;
  int filterReads = 0;
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) {
    if (operation == 'blueprints.filters' &&
        parameters['categoryName'] == 'FPSWeapons') {
      filterReads++;
      if (limitedReads > 0) {
        limitedReads--;
        calls.add((
          operation: operation,
          parameters: {...parameters},
          refresh: refresh,
        ));
        return Future.error(const CatalogFailure('catalog.rate_limited'));
      }
    }
    return super.read(operation, parameters, refresh: refresh);
  }
}

void main() {
  test('stat display keeps numeric zero and negative values, omits unknowns and duplicate fire rate', () {
    expect(
      catalogStats({
        'baseStats': {
          'Armor_DamageMitigation': 0,
          'Armor_TemperatureMin': -30,
          'Weapon_ReloadSpeed': 'unknown',
          'Weapon_FireRate': 500,
          'unlisted': 12,
        },
        'weaponRawStats': {'rateOfFire': 600, 'dps': 0, 'unlisted': 99},
      }),
      {
        'Armor_DamageMitigation': '0 %',
        'Armor_TemperatureMin': '-30 °C',
        'dps': '0',
        'rateOfFire': '600 RPM',
      },
    );
    expect(catalogStats({'baseStats': {}, 'weaponRawStats': {}}), isEmpty);
  });
  testWidgets(
    'mission classification groups forward selections, clear and survive paging and refresh',
    (tester) async {
      final port = SampleCatalogPort();
      final c = CatalogController(CatalogKind.missions, port);
      unawaited(c.loadFilters());
      await tester.pumpWidget(filters(c));
      await advance(tester);
      for (final (field, value, label) in [
        ('category', 'Delivery', '运输类 (12)'),
        ('faction', 'Sample faction', '示意阵营 (8)'),
        ('issuer', 'Example issuer', '示意发布方 (5)'),
      ]) {
        expect(find.text(label), findsOneWidget);
        await choose(tester, '$field-$value');
        expect(
          tester
              .widget<ToolsOption>(
                find.byKey(Key('catalog-filter-$field-$value')),
              )
              .selected,
          isTrue,
        );
        expect(port.calls.last.parameters[field], value);
        expect(port.calls.last.parameters['pageNo'], 1);
      }
      unawaited(c.filter('system', 'Stanton'));
      await advance(tester);
      unawaited(c.go(2));
      await advance(tester);
      expect(port.calls.last.parameters, containsPair('pageNo', 2));
      for (final field in ['category', 'faction', 'issuer', 'system']) {
        expect(port.calls.last.parameters[field], c.options[field]);
      }
      unawaited(c.refresh());
      await advance(tester);
      expect(
        port.calls
            .where((call) => call.operation == 'missions.page')
            .last
            .refresh,
        isTrue,
      );
      await choose(tester, 'faction-Sample faction');
      expect(c.options.containsKey('faction'), isFalse);
      expect(port.calls.last.parameters.containsKey('faction'), isFalse);
      expect(port.calls.last.parameters['category'], 'Delivery');
      expect(port.calls.last.parameters['pageNo'], 1);
      await browse.disposePage(tester);
      c.dispose();
    },
  );

  testWidgets(
    'missing mission groups disappear; groups sort by count and expand after eight',
    (tester) async {
      final port = SampleCatalogPort()..missionFilters = {};
      final c = CatalogController(CatalogKind.missions, port);
      await tester.pumpWidget(filters(c));
      unawaited(c.loadFilters());
      await advance(tester);
      for (final field in ['category', 'faction', 'issuer']) {
        expect(find.byKey(Key('catalog-filter-$field')), findsNothing);
      }
      port.missionFilters = {
        for (final source in ['categories', 'factions', 'issuers'])
          source: List.generate(
            10,
            (i) => {
              'value': 'v$i',
              'label': 'Option $i',
              'labelCn': i == 9 ? '' : '选项 $i',
              'missionCount': i,
            },
          ),
      };
      unawaited(c.loadFilters());
      await advance(tester);
      for (final field in ['category', 'faction', 'issuer']) {
        final group = find.byKey(Key('catalog-filter-$field'));
        final options = tester.widgetList<ToolsOption>(
          find.descendant(of: group, matching: find.byType(ToolsOption)),
        );
        expect(options.map((o) => o.label), [
          '全部',
          'Option 9 (9)',
          '选项 8 (8)',
          '选项 7 (7)',
          '选项 6 (6)',
          '选项 5 (5)',
          '选项 4 (4)',
          '选项 3 (3)',
          '选项 2 (2)',
          '更多 (2)',
        ]);
        expect(find.byKey(Key('catalog-filter-$field-v0')), findsNothing);
        await choose(tester, '$field-more');
        expect(find.byKey(Key('catalog-filter-$field-v0')), findsOneWidget);
        expect(find.byKey(Key('catalog-filter-$field-more')), findsNothing);
      }
      await browse.disposePage(tester);
      c.dispose();
    },
  );

  testWidgets(
    'blueprint source categories stay fixed; scoped filters and child clearing',
    (tester) async {
      final port = SampleCatalogPort();
      final c = CatalogController(CatalogKind.blueprints, port);
      unawaited(c.loadFilters());
      await tester.pumpWidget(filters(c));
      await advance(tester);
      for (final field in ['subcategory', 'manufacturer', 'itemClass']) {
        expect(find.byKey(Key('catalog-filter-$field')), findsNothing);
      }
      expect(find.text('只看合约奖励'), findsNothing);
      List<String> categories() => tester
          .widgetList<ToolsOption>(
            find.descendant(
              of: find.byKey(const Key('catalog-filter-categoryName')),
              matching: find.byType(ToolsOption),
            ),
          )
          .map((o) => o.label)
          .toList();
      final before = categories();
      expect(before, ['全部', '武器', '护甲', '弹药', '舰船武器', '舰船组件', '任务物品']);
      expect(catalogBlueprintCategories, [
        'FPSWeapons',
        'FPSArmours',
        'Ammo',
        'ShipWeapons',
        'Components',
        'MissionItems',
      ]);
      await choose(tester, 'categoryName-FPSArmours');
      expect(find.text('头盔'), findsOneWidget);
      expect(
        find.byKey(const Key('catalog-filter-manufacturer')),
        findsOneWidget,
      );
      expect(find.text('军用'), findsOneWidget);
      await choose(tester, 'subcategory-helmet');
      final filterCall = port.calls
          .where((call) => call.operation == 'blueprints.filters')
          .last;
      expect(filterCall.parameters, {
        'categoryName': 'FPSArmours',
        'subcategory': 'helmet',
      });
      await choose(tester, 'manufacturer-armr');
      await choose(tester, 'itemClass-Military');
      expect(port.calls.last.parameters, containsPair('subcategory', 'helmet'));
      expect(port.calls.last.parameters, containsPair('manufacturer', 'armr'));
      expect(port.calls.last.parameters, containsPair('itemClass', 'Military'));
      port.blueprintRows = [
        {'id': 99, 'categoryName': 'UnknownFromNextPage'},
      ];
      unawaited(c.go(2));
      await advance(tester);
      expect(port.calls.last.parameters['pageNo'], 2);
      expect(categories(), before);
      expect(find.text('UnknownFromNextPage'), findsNothing);
      await choose(tester, 'categoryName-FPSWeapons');
      for (final field in ['subcategory', 'manufacturer', 'itemClass']) {
        expect(c.options.containsKey(field), isFalse);
        expect(
          port.calls
              .where((call) => call.operation == 'blueprints.page')
              .last
              .parameters
              .containsKey(field),
          isFalse,
        );
      }
      expect(c.page, 1);
      expect(find.text('狙击枪'), findsOneWidget);
      await choose(tester, 'categoryName-all');
      expect(find.byKey(const Key('catalog-filter-subcategory')), findsNothing);
      expect(port.calls.last.parameters.containsKey('subcategory'), isFalse);
      await browse.disposePage(tester);
      c.dispose();
    },
  );

  testWidgets('narrow 2x English blueprint filters fit with every group open', (
    tester,
  ) async {
    browse.size(tester, 320);
    final port = SampleCatalogPort()
      ..blueprintFilters = {
        'manufacturers': List.generate(10, (i) => 'Manufacturer number $i'),
        'itemClasses': List.generate(10, (i) => 'Item class number $i'),
      };
    final c = CatalogController(CatalogKind.blueprints, port);
    await tester.pumpWidget(
      browse.app(
        ListenableBuilder(
          listenable: c,
          builder: (context, _) =>
              SingleChildScrollView(child: CatalogFilters(c)),
        ),
        locale: const Locale('en', 'US'),
        scale: 2,
      ),
    );
    await choose(tester, 'categoryName-FPSArmours');
    await choose(tester, 'subcategory-helmet');
    await choose(tester, 'manufacturer-more');
    await choose(tester, 'itemClass-more');
    expect(
      find.byKey(
        const Key('catalog-filter-manufacturer-Manufacturer number 9'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await browse.disposePage(tester);
    c.dispose();
  });

  testWidgets(
    'subcategory changes clear manufacturer and class; long source lists expand',
    (tester) async {
      final port = SampleCatalogPort()
        ..blueprintFilters = {
          'manufacturers': List.generate(10, (i) => 'M$i'),
          'itemClasses': List.generate(10, (i) => 'C$i'),
        };
      final c = CatalogController(CatalogKind.blueprints, port);
      await tester.pumpWidget(filters(c));
      await choose(tester, 'categoryName-FPSWeapons');
      for (final (field, prefix) in [
        ('manufacturer', 'M'),
        ('itemClass', 'C'),
      ]) {
        expect(
          find.byKey(Key('catalog-filter-$field-${prefix}9')),
          findsNothing,
        );
        await choose(tester, '$field-more');
        await choose(tester, '$field-${prefix}9');
        expect(c.options[field], '${prefix}9');
      }
      await choose(tester, 'subcategory-rifle');
      expect(c.options.containsKey('manufacturer'), isFalse);
      expect(c.options.containsKey('itemClass'), isFalse);
      expect(port.calls.last.parameters, {
        'categoryName': 'FPSWeapons',
        'subcategory': 'rifle',
      });
      await browse.disposePage(tester);
      c.dispose();
    },
  );

  testWidgets(
    'rate-limited category filters retry quietly, at most three reads',
    (tester) async {
      final once = LimitedFiltersPort(1);
      final c = CatalogController(CatalogKind.blueprints, once);
      await tester.pumpWidget(filters(c));
      unawaited(c.filter('categoryName', 'FPSWeapons'));
      await advance(tester);
      await advance(tester);
      expect(once.filterReads, 2);
      expect(c.filters['manufacturers'], ['armr']);
      expect(c.error, isNull);
      await browse.disposePage(tester);
      c.dispose();

      final always = LimitedFiltersPort(99);
      final d = CatalogController(CatalogKind.blueprints, always);
      await tester.pumpWidget(filters(d));
      unawaited(d.filter('categoryName', 'FPSWeapons'));
      for (var i = 0; i < 4; i++) {
        await advance(tester);
      }
      expect(always.filterReads, 3);
      expect(d.error?.limited, isTrue);
      await browse.disposePage(tester);
      d.dispose();
    },
  );

  testWidgets('hiding the page ends a pending category filter retry', (
    tester,
  ) async {
    final port = LimitedFiltersPort(99);
    final c = CatalogController(CatalogKind.blueprints, port);
    await tester.pumpWidget(filters(c));
    unawaited(c.filter('categoryName', 'FPSWeapons'));
    // Page read, one-second wait, first (rate-limited) filters read.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(port.filterReads, 1);
    c.setVisible(false);
    c.setVisible(true);
    await advance(tester);
    await advance(tester);
    expect(port.filterReads, 1);
    expect(c.error, isNull);
    await browse.disposePage(tester);
    c.dispose();
  });

  testWidgets('late filter response cannot restore a previous category', (
    tester,
  ) async {
    final port = HeldFiltersPort();
    final c = CatalogController(CatalogKind.blueprints, port);
    await tester.pumpWidget(filters(c));
    unawaited(c.filter('categoryName', 'FPSWeapons'));
    await advance(tester);
    unawaited(c.filter('categoryName', 'FPSArmours'));
    await advance(tester);
    port.held.complete({
      'manufacturers': ['Late manufacturer'],
    });
    await advance(tester);
    expect(c.options['categoryName'], 'FPSArmours');
    expect(c.filters['manufacturers'], ['armr']);
    expect(find.text('Late manufacturer'), findsNothing);
    await browse.disposePage(tester);
    c.dispose();
  });

  for (final kind in CatalogKind.values) {
    testWidgets(
      '${kind.name} detail displays values and hides absent optional rows',
      (tester) async {
        final c = CatalogController(kind, SampleCatalogPort());
        c.showResolvedDetail(
          kind == CatalogKind.missions
              ? missionSample
              : {
                  ...blueprintSample,
                  'weaponRawStats': {
                    'dps': 123.5,
                    'damagePerShot': 20,
                    'rateOfFire': 600,
                  },
                },
        );
        await tester.pumpWidget(
          browse.app(
            SingleChildScrollView(
              child: CatalogDetails(c, onCrossLink: (_, _) {}),
            ),
          ),
        );
        await advance(tester);
        final labels = kind == CatalogKind.missions
            ? [
                '难度',
                '最低声望',
                '最高声望',
                '阵营',
                '取货次数',
                '卸货次数',
                '目的地',
                '遭遇舰船',
                '物品奖励',
              ]
            : ['种类', '物品类别', '属性', '伤害减免', '武器 DPS', '单发伤害'];
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        if (kind == CatalogKind.missions) {
          for (final value in [
            '标准 · 2',
            '见习 · 0',
            '示意目的地',
            '示意舰船',
            '示意补给 ×2',
          ]) {
            expect(find.text(value), findsOneWidget);
          }
        } else {
          expect(find.text('装甲'), findsOneWidget);
          expect(find.text('军用'), findsOneWidget);
          expect(find.text('123.5'), findsOneWidget);
        }
        c.showResolvedDetail(
          kind == CatalogKind.missions
              ? {'missionGuid': missionGuid, 'title': 'Sparse mission'}
              : {'id': 73, 'blueprintName': 'Sparse blueprint'},
        );
        await tester.pumpWidget(
          browse.app(
            SingleChildScrollView(
              child: CatalogDetails(c, onCrossLink: (_, _) {}),
            ),
          ),
        );
        await advance(tester);
        for (final label in labels) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('要求'), findsNothing);
        expect(tester.takeException(), isNull);
        await browse.disposePage(tester);
        c.dispose();
      },
    );
  }

  for (final compact in [false, true]) {
    for (final faction in [false, true]) {
      testWidgets('mission subtitle compact=$compact faction=$faction', (
        tester,
      ) async {
        browse.size(tester, compact ? 320 : 1440);
        final c = CatalogController(CatalogKind.missions, SampleCatalogPort());
        final records = MissionRecordsController(null);
        final row = {...missionSample};
        if (!faction) {
          row.remove('factionName');
          row.remove('factionNameCn');
        }
        await tester.pumpWidget(
          browse.app(
            CatalogTableRow(
              controller: c,
              row: row,
              records: records,
              compact: compact,
            ),
          ),
        );
        await advance(tester);
        final owner = faction ? '示意阵营' : '示意发布方';
        expect(
          find.text('${compact ? '运输 · ' : ''}$owner · Stanton'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await browse.disposePage(tester);
        records.dispose();
        c.dispose();
      });
    }
  }

  testWidgets(
    'blueprint card shows the item kind only when the code is known',
    (tester) async {
      final c = CatalogController(CatalogKind.blueprints, SampleCatalogPort());
      await tester.pumpWidget(
        browse.app(
          SingleChildScrollView(
            child: CatalogBlueprintCard(controller: c, row: blueprintSample),
          ),
        ),
      );
      await advance(tester);
      expect(find.text('护甲 · 装甲'), findsOneWidget);
      await tester.pumpWidget(
        browse.app(
          SingleChildScrollView(
            child: CatalogBlueprintCard(
              controller: c,
              row: {...blueprintSample}..remove('manufacturer'),
            ),
          ),
        ),
      );
      await advance(tester);
      expect(find.text('护甲'), findsOneWidget);
      expect(find.textContaining('装甲'), findsNothing);
      expect(find.textContaining('armr'), findsNothing);
      await browse.disposePage(tester);
      c.dispose();
    },
  );
}
