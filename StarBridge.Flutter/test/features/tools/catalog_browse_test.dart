import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/catalog_strings.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/tools/catalog_controller.dart';
import 'package:starbridge_flutter/features/tools/catalog_details.dart';
import 'package:starbridge_flutter/features/tools/catalog_page.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';

import 'catalog_samples.dart';

Widget app(
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
void size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// Brings [finder] on screen. Narrow pages are lazy lists: at 320 wide and 2x
/// text the page header alone can fill the viewport, so a row further down is
/// not built until the list scrolls toward it.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
}

Future<void> tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  // Tall rows near the end of a narrow list settle back after ensureVisible;
  // tap only once the scroll position is final.
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await settle(tester);
}

Future<void> disposePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

final class HeldDetailsPort extends SampleCatalogPort {
  final held = Completer<CatalogRow>();
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) {
    if (operation == 'missions.detail' &&
        parameters['guid'] == '00000000-0000-0000-0000-000000000072') {
      return held.future;
    }
    return super.read(operation, parameters, refresh: refresh);
  }
}

final class HeldRefreshDetailPort extends SampleCatalogPort {
  final held = Completer<CatalogRow>();
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) {
    if (operation == 'missions.detail' && refresh) {
      calls.add((
        operation: operation,
        parameters: parameters,
        refresh: refresh,
      ));
      return held.future;
    }
    return super.read(operation, parameters, refresh: refresh);
  }
}

void main() {
  test('late detail cannot replace a newer selection', () async {
    final port = HeldDetailsPort();
    final c = CatalogController(CatalogKind.missions, port);
    final old = c.select('00000000-0000-0000-0000-000000000072');
    await c.select(missionGuid);
    port.held.complete({
      ...missionSample,
      'missionGuid': '00000000-0000-0000-0000-000000000072',
      'titleCn': '过期示意合约',
    });
    await old;
    expect(c.selectedKey, missionGuid);
    expect(c.detail['titleCn'], '示意合约');
    c.dispose();
  });
  test('failed pagination keeps the successful page number', () async {
    final port = SampleCatalogPort();
    final c = CatalogController(CatalogKind.missions, port);
    await c.loadPage();
    port.failures['missions.page'] = const CatalogFailure();
    await c.go(2);
    expect(c.page, 1);
    expect(c.rows.single['missionGuid'], missionGuid);
    c.dispose();
  });
  test(
    'source failure retains previously successful blueprint sources',
    () async {
      final port = SampleCatalogPort();
      final c = CatalogController(CatalogKind.blueprints, port);
      await c.select(73);
      port.failures['blueprints.missions'] = const CatalogFailure();
      await c.select(73, refresh: true);
      expect(c.sources.single['missionGuid'], missionGuid);
      expect(c.error, isNotNull);
      c.dispose();
    },
  );
  test('hidden route does not send its delayed filter read', () async {
    final port = SampleCatalogPort();
    final c = CatalogController(CatalogKind.missions, port);
    final start = c.start();
    await Future<void>.delayed(Duration.zero);
    c.setVisible(false);
    await start;
    expect(port.calls.map((r) => r.operation), ['missions.page']);
    c.dispose();
  });
  test('all catalogue interface strings have three translations', () {
    expect(catalogZhCn.keys.toSet(), catalogZhTw.keys.toSet());
    expect(catalogEn.keys.toSet(), catalogZhCn.keys.toSet());
    expect(catalogZhCn.values.any((v) => v.contains('数据来自')), isFalse);
    expect(
      catalogName({'title': 'Fallback', 'titleCn': ''}, 'zh', 'title'),
      'Fallback',
    );
    expect(catalogName(missionSample, 'en', 'title'), 'Sample contract');
    expect(catalogName(missionSample, 'zh', 'title'), '示意合约');
    expect(catalogChance(0), '0%');
    expect(catalogChance(1), '100%');
    expect(catalogChance(0.125), '12.5%');
  });

  testWidgets(
    'tools expose four cards in order and open the two independent routes',
    (tester) async {
      size(tester, 1440);
      final destinations = <String>[];
      final port = SampleCatalogPort();
      final features = createToolsFeatures(createCatalog: () => port);
      expect(toolEntries.map((e) => e.id), [
        'exec-hangar',
        'missions',
        'blueprints',
        'key-bindings',
      ]);
      await tester.pumpWidget(
        app(
          Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (intent) {
                  destinations.add(intent.route);
                  return null;
                },
              ),
            },
            child: const ToolsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
      for (final id in ['missions', 'blueprints']) {
        await tester.ensureVisible(find.byKey(Key('tool-$id')));
        await tester.tap(find.byKey(Key('tool-$id')));
        await tester.pumpAndSettle();
        final feature = features.singleWhere((f) => f.route == '/tools/$id');
        expect(feature.buildDestination, isNotNull);
      }
      expect(destinations, ['/tools/missions', '/tools/blueprints']);
      await disposePage(tester);
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    for (final kind in CatalogKind.values) {
      for (final width in [320.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '${kind.name} ${locale.toLanguageTag()} width $width scale $scale list and detail',
            (tester) async {
              size(tester, width);
              final port = SampleCatalogPort();
              await tester.pumpWidget(
                app(
                  CatalogPage(kind: kind, port: port),
                  locale: locale,
                  scale: scale,
                ),
              );
              await settle(tester);
              if (width == 320) {
                final filterLabel = AppStrings.resolve(locale)
                    .text('catalog.filters');
                await tester.tap(find.text(filterLabel));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                await tester.tap(find.text(filterLabel));
                await tester.pumpAndSettle();
              }
              final id = kind == CatalogKind.missions ? missionGuid : 73;
              await tap(tester, Key('catalog-row-$id'));
              expect(find.byKey(const Key('catalog-detail')), findsOneWidget);
              final english = locale.languageCode == 'en';
              expect(
                find.text(
                  kind == CatalogKind.missions
                      ? (english ? 'Deliver sample cargo.' : '运送示意货物。')
                      : (english ? 'Shell ×3' : '外壳 ×3'),
                ),
                findsOneWidget,
              );
              if (kind == CatalogKind.blueprints) {
                expect(
                  find.byKey(Key('catalog-link-missions-$missionGuid')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('catalog-image-placeholder')),
                  findsWidgets,
                );
              } else {
                expect(
                  find.byKey(const Key('catalog-link-blueprints-73')),
                  findsOneWidget,
                );
              }
              expect(tester.takeException(), isNull);
              await disposePage(tester);
            },
          );
        }
      }
    }
  }

  for (final start in CatalogKind.values) {
    testWidgets(
      '${start.name} cross-link reads target detail directly and back preserves selection',
      (tester) async {
        size(tester, 1440);
        final port = SampleCatalogPort();
        final id = start == CatalogKind.missions ? missionGuid : 73;
        final target = start == CatalogKind.missions
            ? CatalogKind.blueprints
            : CatalogKind.missions;
        final targetId = start == CatalogKind.missions ? 73 : missionGuid;
        await tester.pumpWidget(app(CatalogPage(kind: start, port: port)));
        await settle(tester);
        await tap(tester, Key('catalog-row-$id'));
        final beforePages = port.calls
            .where((c) => c.operation.endsWith('.page'))
            .length;
        await tap(tester, Key('catalog-link-${target.name}-$targetId'));
        expect(
          port.calls.where((c) => c.operation.endsWith('.page')).length,
          beforePages,
        );
        expect(find.byType(CatalogPage), findsOneWidget);
        expect(
          tester.widget<CatalogPage>(find.byType(CatalogPage)).kind,
          target,
        );
        await tap(tester, const Key('catalog-back'));
        expect(
          tester.widget<CatalogPage>(find.byType(CatalogPage)).kind,
          start,
        );
        expect(
          find.byKey(Key('catalog-link-${target.name}-$targetId')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await disposePage(tester);
      },
    );
  }

  test('a newer action retires a pending refresh re-selection', () async {
    final port = SampleCatalogPort();
    final c = CatalogController(CatalogKind.missions, port);
    await c.loadPage();
    await c.select(missionGuid);
    final pending = c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    c.closeDetail();
    await pending;
    expect(c.hasDetail, isFalse);
    expect(
      port.calls.where((x) => x.operation == 'missions.detail' && x.refresh),
      isEmpty,
    );
    c.dispose();
  });

  test(
    'switching detail while refresh re-reads it retires the refresh',
    () async {
      final port = HeldRefreshDetailPort();
      final c = CatalogController(CatalogKind.missions, port);
      await c.loadPage();
      await c.select(missionGuid);
      final pending = c.refresh();
      while (!port.held.isCompleted &&
          !port.calls.any(
            (x) => x.operation == 'missions.detail' && x.refresh,
          )) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      c.closeDetail();
      port.held.complete(missionSample);
      await pending;
      expect(c.hasDetail, isFalse);
      expect(
        port.calls.where((x) => x.operation == 'missions.filters' && x.refresh),
        isEmpty,
      );
      c.dispose();
    },
  );

  testWidgets('narrow search text survives detail and back; time limit shows', (
    tester,
  ) async {
    size(tester, 320);
    final port = SampleCatalogPort();
    await tester.pumpWidget(
      app(CatalogPage(kind: CatalogKind.missions, port: port)),
    );
    await settle(tester);
    final filterLabel = AppStrings.resolve(const Locale('zh', 'CN'))
        .text('catalog.filters');
    await tester.tap(find.text(filterLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-search')), 'Sample');
    await settle(tester);
    await tap(tester, const Key('catalog-row-$missionGuid'));
    expect(find.textContaining('600 分'), findsOneWidget);
    await tap(tester, const Key('catalog-back'));
    await tester.tap(find.text(filterLabel));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('catalog-search')))
          .controller
          ?.text,
      'Sample',
    );
    await disposePage(tester);
  });

  testWidgets('narrow detail back returns to the existing list', (
    tester,
  ) async {
    size(tester, 320);
    final port = SampleCatalogPort();
    await tester.pumpWidget(
      app(CatalogPage(kind: CatalogKind.missions, port: port)),
    );
    await settle(tester);
    await tap(tester, const Key('catalog-row-$missionGuid'));
    await tap(tester, const Key('catalog-back'));
    expect(find.byKey(const Key('catalog-row-$missionGuid')), findsOneWidget);
    expect(
      port.calls.where((c) => c.operation == 'missions.page'),
      hasLength(1),
    );
    await disposePage(tester);
  });

  for (final kind in CatalogKind.values) {
    testWidgets(
      '${kind.name} failure and rate limit retain previous successful results',
      (tester) async {
        size(tester, 1440);
        final port = SampleCatalogPort();
        await tester.pumpWidget(app(CatalogPage(kind: kind, port: port)));
        await settle(tester);
        final id = kind == CatalogKind.missions ? missionGuid : 73;
        for (final limited in [false, true]) {
          port.failures['${kind.name}.page'] = CatalogFailure(
            limited ? 'catalog.rate_limited' : 'catalog.unavailable',
          );
          await tap(tester, const Key('catalog-refresh'));
          expect(find.text(limited ? '请稍后再试' : '暂时读不到，请稍后再试'), findsOneWidget);
          expect(find.byKey(Key('catalog-row-$id')), findsOneWidget);
        }
        expect(port.calls.last.refresh, isTrue);
        await disposePage(tester);
      },
    );
    testWidgets('${kind.name} empty results', (tester) async {
      final port = SampleCatalogPort()..empty = true;
      await tester.pumpWidget(app(CatalogPage(kind: kind, port: port)));
      await settle(tester);
      expect(
        find.text(kind == CatalogKind.missions ? '没有找到符合条件的合约' : '没有找到符合条件的蓝图'),
        findsOneWidget,
      );
      await disposePage(tester);
    });
  }

  testWidgets('search waits 400ms, filters and paging use exact parameters', (
    tester,
  ) async {
    size(tester, 1440);
    final port = SampleCatalogPort();
    await tester.pumpWidget(
      app(CatalogPage(kind: CatalogKind.missions, port: port)),
    );
    await settle(tester);
    final pages = port.calls
        .where((c) => c.operation == 'missions.page')
        .length;
    await tester.enterText(find.byKey(const Key('catalog-search')), '示意');
    await tester.pump(const Duration(milliseconds: 399));
    expect(
      port.calls.where((c) => c.operation == 'missions.page').length,
      pages,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(port.calls.last.parameters['keyword'], '示意');
    await tester.tap(find.text('只看有蓝图奖励的'));
    await settle(tester);
    expect(port.calls.last.parameters['hasBlueprintRewards'], isTrue);
    await tap(tester, const Key('catalog-next'));
    expect(port.calls.last.parameters['pageNo'], 2);
    await disposePage(tester);
  });

  testWidgets(
    'website button delegates the selected item without a real browser',
    (tester) async {
      size(tester, 1440);
      final port = SampleCatalogPort();
      await tester.pumpWidget(
        app(
          CatalogPage(kind: CatalogKind.blueprints, port: port, selection: 73),
        ),
      );
      await settle(tester);
      await tap(tester, const Key('catalog-open-website'));
      expect(port.opened, [CatalogKind.blueprints]);
      expect(port.calls.any((c) => c.operation.endsWith('.page')), isFalse);
      await disposePage(tester);
    },
  );

  test('detail failures retain successful detail and sources', () async {
    final port = SampleCatalogPort();
    final c = CatalogController(CatalogKind.missions, port);
    await c.select(missionGuid);
    port.failures['missions.detail'] = const CatalogFailure();
    await c.select(missionGuid, refresh: true);
    expect(c.detail['titleCn'], '示意合约');
    expect(c.error, isNotNull);
    c.dispose();
  });
}
