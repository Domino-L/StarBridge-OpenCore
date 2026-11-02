import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'marketplace_test.dart' as fixture;

void main() {
  for (final ready in [false, true]) {
    testWidgets('market primary paint records ${ready ? 'data' : 'waiting'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<void>();
      final port = fixture.FixturePort()..readGate = ready ? null : gate;
      final controller = MarketplaceController(port);
      if (ready) await controller.initialize();
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
      metrics.route('/marketplace');
      await runZoned(
        () => tester.pumpWidget(
          fixture.app(
            controller,
            AppearanceMode.dark,
            const Locale('zh', 'CN'),
          ),
        ),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await runZoned(
        () => tester.pump(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      expect(tester.takeException(), isNull);
      expect(find.text('大厅'), findsWidgets);
      final paints = events.where((e) => e['kind'] == 'contentPaint').toList();
      expect(
        paints,
        isNotEmpty,
        reason: 'Visible market needs its own content marker.',
      );
      expect(paints.last['status'], ready ? 'data' : 'waiting');
      expect(paints.last['route'], '/marketplace');
      expect(events.where((e) => e['kind'] == 'contentRaster'), isEmpty);
      controller.dispose();
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox());
    });
  }

  final read = MarketRead({
    'rows': [fixture.FixturePort.item(1)],
  }, DateTime.utc(2026, 10, 17));
  final empty = MarketRead(const {'rows': <MarketRow>[]}, read.readAt);
  final cases = <(String, String, void Function(MarketplaceController))>[
    (
      'hall child categories do not count as displayed roots',
      'empty',
      (c) {
        for (final key in ['categories', 'trending', 'latest']) {
          c.blocks[key] = empty;
        }
        c.blocks['categories'] = MarketRead(const {
          'rows': [
            {'id': 2, 'parentId': 1, 'name': 'internal-hidden-child'},
          ],
        }, read.readAt);
      },
    ),
    (
      'hall empty',
      'empty',
      (c) {
        for (final key in ['categories', 'trending', 'latest']) {
          c.blocks[key] = empty;
        }
      },
    ),
    (
      'hall unavailable',
      'unavailable',
      (c) {
        c.blocks.clear();
        c.failures.addAll(['categories', 'trending', 'latest']);
      },
    ),
    (
      'hall partial',
      'partial',
      (c) {
        c.blocks.remove('latest');
        c.failures.add('latest');
      },
    ),
    (
      'hall old content refresh',
      'data',
      (c) {
        c.loading.addAll(['categories', 'trending', 'latest']);
      },
    ),
    ('hall stale', 'partial', (c) => c.failures.add('latest')),
    (
      'hidden hall does not ready catalog',
      'waiting',
      (c) {
        c.keyword = 'internal-fixture-query';
        c.loading.add('catalog');
      },
    ),
    (
      'catalog empty',
      'empty',
      (c) {
        c.keyword = 'internal-fixture-query';
        c.blocks['catalog'] = empty;
      },
    ),
    (
      'catalog unavailable',
      'unavailable',
      (c) {
        c.keyword = 'internal-fixture-query';
        c.failures.add('catalog');
      },
    ),
    (
      'catalog stale',
      'partial',
      (c) {
        c.keyword = 'internal-fixture-query';
        c.blocks['catalog'] = read;
        c.failures.add('catalog');
      },
    ),
    (
      'placeholder tab ignores hidden cache',
      'unavailable',
      (c) => c.mainTab = 2,
    ),
    (
      'item identity and selected offers',
      'data',
      (c) {
        c.itemId = 1;
        c.blocks['item'] = MarketRead(fixture.FixturePort.item(1), read.readAt);
        c.blocks['sell'] = read;
      },
    ),
    (
      'item selected offers missing',
      'partial',
      (c) {
        c.itemId = 1;
        c.blocks['item'] = MarketRead(fixture.FixturePort.item(1), read.readAt);
        c.itemTab = 1;
        c.failures.add('buy');
      },
    ),
    ('item pending ignores hall', 'waiting', (c) => c.itemId = 1),
    (
      'browser pending ignores hall',
      'waiting',
      (c) {
        c.mainTab = 1;
        c.browser.loading = true;
      },
    ),
    (
      'browser data',
      'data',
      (c) {
        c.mainTab = 1;
        c.browser.result = read;
      },
    ),
    (
      'browser empty',
      'empty',
      (c) {
        c.mainTab = 1;
        c.browser.result = empty;
      },
    ),
    (
      'browser unavailable',
      'unavailable',
      (c) {
        c.mainTab = 1;
        c.browser.failed = true;
      },
    ),
    (
      'browser stale',
      'partial',
      (c) {
        c.mainTab = 1;
        c.browser.result = read;
        c.browser.failed = true;
      },
    ),
  ];
  for (final (name, expected, configure) in cases) {
    testWidgets('selected primary content: $name', (tester) async {
      _size(tester);
      final controller = MarketplaceController(fixture.FixturePort());
      await controller.initialize();
      configure(controller);
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
      metrics.route('/marketplace');
      await _show(tester, controller, metrics);
      expect(tester.takeException(), isNull);
      final paint = events.lastWhere((e) => e['kind'] == 'contentPaint');
      expect(paint['status'], expected);
      expect(events.toString(), isNot(contains('internal-fixture-query')));
      controller.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('independent browser completion updates the measured scene', (
    tester,
  ) async {
    _size(tester);
    final port = fixture.FixturePort();
    final controller = MarketplaceController(port);
    await controller.initialize();
    controller.mainTab = 1;
    var parentNotifications = 0;
    controller.addListener(() => parentNotifications++);
    final events = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
    metrics.route('/marketplace');
    await _show(tester, controller, metrics);
    expect(
      events.lastWhere((e) => e['kind'] == 'contentPaint')['status'],
      'waiting',
    );
    await runZoned(() async {
      await controller.browser.reload();
      await tester.pump();
    }, zoneValues: {loadingMetricsZoneKey: metrics});
    expect(
      events.lastWhere((e) => e['kind'] == 'contentPaint')['status'],
      'empty',
    );
    expect(parentNotifications, 0);
    expect(tester.takeException(), isNull);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _show(
  WidgetTester tester,
  MarketplaceController controller,
  LoadingMetrics metrics,
) => runZoned(() async {
  await tester.pumpWidget(
    fixture.app(controller, AppearanceMode.dark, const Locale('zh', 'CN')),
  );
  await tester.pump();
}, zoneValues: {loadingMetricsZoneKey: metrics});
