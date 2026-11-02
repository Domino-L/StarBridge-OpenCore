import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'marketplace_test.dart' show FixturePort;
import 'marketplace_snapshot_test.dart' show SnapshotPort;

const output = '../.artifacts/trading-hall-intake-20261015/slice2-round3';

class MarketSnapshotPort extends FixturePort {
  MarketSnapshotPort(this.snapshot, this.hall);
  final SnapshotPort hall;
  final Map<String, dynamic> snapshot;
  bool fail = false;
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) async {
    if (page > 1) {
      return MarketRead({'rows': <MarketRow>[], 'total': 0}, DateTime.now());
    }
    if (fail) throw StateError('offline replay');
    final key = operation == 'marketItems'
        ? (options.containsKey('minOrderCount') ? 'items' : 'allItems')
        : operation == 'marketOrders'
        ? 'orders'
        : operation;
    final raw =
        snapshot[operation == 'latest'
                ? (side == 1
                      ? 'sell'
                      : side == 0
                      ? 'buy'
                      : 'barter')
                : key]
            as Map?;
    if (raw == null) {
      return hall.read(
        operation,
        id: id,
        keyword: keyword,
        category: category,
        side: side,
        page: page,
        language: language,
        options: options,
      );
    }
    final base = operation == 'latest'
        ? await hall.read(operation, side: side)
        : null;
    return MarketRead({
      ...Map<String, Object?>.from(raw['data'] as Map),
      if (base != null) 'rows': base.rows,
    }, DateTime.parse(raw['readAt']));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('market-window')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('$output/renders').create(recursive: true);
    await File('$output/renders/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('MARKET_SLICE2_ROUND3_SNAPSHOT')) return;
  late Map<String, dynamic> snapshot;
  late Map<String, dynamic> hall;
  setUpAll(() async {
    snapshot = jsonDecode(
      await File('$output/scm-snapshot.json').readAsString(),
    );
    snapshot.addAll(
      jsonDecode(
        (await File(
          '$output/search-snapshot.json',
        ).readAsString()).replaceAll('\ufeff', ''),
      ),
    );
    final overview = File('$output/overview.json');
    if (await overview.exists()) {
      snapshot.addAll(
        jsonDecode((await overview.readAsString()).replaceAll('\ufeff', '')),
      );
    }
    hall = jsonDecode(
      await File(
        '../.artifacts/trading-hall-intake-20261015/round2/scm-snapshot.json',
      ).readAsString(),
    );
    for (final pair in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      await (FontLoader(pair.$1)..addFont(rootBundle.load(pair.$2))).load();
    }
  });
  for (final width in [900, 1280]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('SCM market whole window $width ${mode.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width.toDouble(), 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = InMemoryAppPreferences();
        await prefs.setAppearanceMode(mode);
        await prefs.setLocale(const Locale('zh', 'CN'));
        final port = MarketSnapshotPort(snapshot, SnapshotPort(hall));
        port.prefs = {
          ...port.prefs,
          'recentSearches': ['科力晶', 'P6-LR'],
          'recentItems': [1, 2],
        };
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          shellChrome: InMemoryShellChrome(
            initial: InMemoryShellChrome.hostConnectedProjection,
          ),
          preferences: prefs,
          marketplacePortFactory: () => port,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('market-window'),
            child: StarBridgeApp(composition: composition),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final c = tester
            .widget<MarketplacePage>(find.byType(MarketplacePage))
            .controller;
        await shot(tester, 'context-$width-${mode.name}');
        final field = find.byKey(const Key('marketplace-search'));
        await tester.tap(field);
        await tester.pumpAndSettle();
        await shot(tester, 'search-recent-$width-${mode.name}');
        await tester.enterText(field, '科');
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
        await shot(tester, 'search-typing-$width-${mode.name}');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await c.marketCategory(31);
        await c.browser.choose(kind: 'orders');
        await shot(tester, 'orders-$width-${mode.name}');
        final rows = c.browser.result!.rows.take(5).toList();
        for (final status in ['loading', 'failed', 'end']) {
          c.browser.result = MarketRead({
            'rows': rows,
            'total': status == 'end' ? rows.length : 28,
          }, DateTime.now());
          c.browser.loading = status == 'loading';
          c.browser.failed = status == 'failed';
          c.browser.setLayout('rows');
          await tester.pumpAndSettle();
          final scroll = tester.widget<CustomScrollView>(
            find.byKey(const ValueKey('market-results')),
          );
          scroll.controller!.jumpTo(
            scroll.controller!.position.maxScrollExtent,
          );
          await tester.pump();
          await shot(tester, 'bottom-$status-$width-${mode.name}');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
