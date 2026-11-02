import '../../_support/development_fixture_path.dart';

import 'dart:async';
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
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../../support/remote_image_fixture.dart';
import 'marketplace_test.dart' show FixturePort;

const output = '../.artifacts/trading-hall-intake-20261015/round3';
final design = developmentFixturePath('StarBridge-DesignPreviews/TradingHall');

// Read only the SCM section, never the prototype's invented DEMO scenario.
class SnapshotPort extends FixturePort {
  SnapshotPort(this.snapshot) {
    prefs = {
      ...prefs,
      'favorites': [1, 2, 3, 4],
    };
  }
  final Map<String, dynamic> snapshot;
  String? art(Map row) => (row['art'] as String?)?.startsWith('img:') == true
      ? 'https://snapshot.invalid/${(row['art'] as String).substring(4)}'
      : null;
  MarketRow itemRow(Map row, int id) => {
    'id': id,
    'itemName': row['n'] ?? row['name'],
    'thumbnailUrl': art(row),
    'sellOrderCount': row['sell'],
    'buyOrderCount': row['buy'],
  };
  MarketRow quote(Map row, int side) => {
    ...itemRow(row, 1),
    'seller': row['who'],
    'point': row['rep'],
    'presence': 'offline',
    'remainingQuantity': row['q'],
    'unitPrice': row['p'],
    'creatorType': side,
    'displayType': side == 2 ? 3 : 1,
    // Snapshot has relative dates only. Reconstruct a day-level timestamp for this replay.
    'createTime': DateTime.now()
        .subtract(
          Duration(
            days:
                (int.tryParse((row['age'] as String? ?? '').split(' ').first) ??
                    1) *
                ((row['age'] as String? ?? '').contains('月') ? 30 : 1),
          ),
        )
        .toIso8601String(),
    'items': [
      {
        'itemId': 1,
        'itemName': row['n'] ?? snapshot['item']['name'],
        'thumbnailUrl': art(row),
        if (row['qb'] != null)
          'qualityData': jsonEncode({'type': 'material', 'quality': row['qb']}),
      },
    ],
  };
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
    await readGate?.future;
    if (operation == 'trend' && failTrend) {
      throw StateError('snapshot trend failure');
    }
    final watches = snapshot['watch'] as List;
    final item = snapshot['item'] as Map;
    final data = <String, Object?>{};
    switch (operation) {
      case 'categories':
        data['rows'] = [
          for (var i = 0; i < (snapshot['cats'] as List).length; i++)
            {'id': i + 1, 'parentId': 0, 'name': snapshot['cats'][i][1]},
        ];
      case 'trending':
        data['rows'] = [
          for (final row in snapshot['hot'])
            {...itemRow(row, 1), 'price': row['p'], 'changePercent': row['c']},
        ];
      case 'latest':
        data['rows'] = [
          for (final row
              in snapshot['latest'][side == 1
                  ? 's'
                  : side == 0
                  ? 'b'
                  : 'x'])
            quote(row, side),
        ];
      case 'item':
        data.addAll(
          id == 1
              ? {
                  'id': 1,
                  'itemName': item['name'],
                  'thumbnailUrl': art(item),
                  'sellOrderCount': 3,
                  'buyOrderCount': 0,
                }
              : itemRow(watches[(id - 1) % watches.length], id),
        );
      case 'offers':
        data['rows'] = side == 0
            ? [
                if (watches[(id - 1) % watches.length]['top'] != null)
                  {'unitPrice': watches[(id - 1) % watches.length]['top']},
              ]
            : id == 1
            ? [for (final row in item['offers']['sell']) quote(row, side)]
            : [
                if (watches[(id - 1) % watches.length]['p'] != null)
                  {'unitPrice': watches[(id - 1) % watches.length]['p']},
              ];
        data['total'] = (data['rows'] as List).length;
      case 'trend':
        data.addAll({'overallPrice': item['avg'], 'rows': <MarketRow>[]});
      case 'search':
        data['rows'] = [
          {'id': 50, 'itemName': snapshot['longName']},
          {'id': 1, 'itemName': item['name'], 'thumbnailUrl': art(item)},
        ];
      default:
        data['rows'] = <MarketRow>[];
    }
    return MarketRead(data, DateTime.now());
  }
}

class SnapshotClient implements HttpClient {
  SnapshotClient(this.images);
  final Map<String, List<int>> images;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async =>
      SnapshotRequest(images[uri.pathSegments.last]);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class SnapshotRequest implements HttpClientRequest {
  SnapshotRequest(this.bytes);
  final List<int>? bytes;
  @override
  Future<HttpClientResponse> close() async => SnapshotResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class SnapshotResponse extends Stream<List<int>> implements HttpClientResponse {
  SnapshotResponse(this.bytes);
  final List<int>? bytes;
  @override
  int get statusCode => bytes == null ? 404 : 200;
  @override
  int get contentLength => bytes?.length ?? 0;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes ?? <int>[]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('whole-window')),
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
  if (!const bool.fromEnvironment('MARKET_SNAPSHOT')) return;
  late Map<String, dynamic> snapshot;
  final images = <String, List<int>>{};
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    snapshot = jsonDecode(
      await File(
        '../.artifacts/trading-hall-intake-20261015/round2/scm-snapshot.json',
      ).readAsString(),
    );
    final source = jsonDecode(
      await File('$design/data/scm-pages-extract.json').readAsString(),
    ) as Map;
    snapshot['longName'] = (source['items'] as List)
        .map((row) => (row['text'] as String).split('|')[1].trim())
        .firstWhere((name) => name.contains('巧匠'));
    for (final file in Directory(
      '$design/data/img',
    ).listSync().whereType<File>()) {
      images[file.uri.pathSegments.last] = await file.readAsBytes();
    }
    for (final pair in [
      ('Source Sans 3', 'SourceSans3VF-Upright.ttf'),
      ('Saira', 'Saira-VF.ttf'),
      ('Rajdhani', 'Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'SourceCodeVF-Upright.ttf'),
    ]) {
      await (FontLoader(
        pair.$1,
      )..addFont(rootBundle.load('assets/fonts/${pair.$2}'))).load();
    }
  });
  for (final width in [900, 1280, 1600]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('SCM whole window $width ${mode.name}', (tester) async {
        tester.view.physicalSize = Size(width.toDouble(), 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = InMemoryAppPreferences();
        await preferences.setAppearanceMode(mode);
        await preferences.setLocale(const Locale('zh', 'CN'));
        final imageMode = ImageMode();
        final loader = RemoteImageLoader(
          mode: imageMode,
          createClient: () => SnapshotClient(images),
        );
        final port = SnapshotPort(snapshot);
        await tester.runAsync(() async {
          for (final name in images.keys) {
            await loader.load('https://snapshot.invalid/$name');
          }
        });
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          preferences: preferences,
          marketplacePortFactory: () => port,
          remoteImagesOverride: loader,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('whole-window'),
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
        if (width == 1280) {
          expect(tester.getTopLeft(find.text('最新上架')).dy, lessThan(800));
        }
        await shot(tester, 'hall-$width-${mode.name}');
        final scroll = find.byKey(const PageStorageKey('marketplace-hall'));
        // The sliver list builds lazily; below the fold the heading does not
        // exist yet, so scroll until it is built before ensureVisible.
        await tester.scrollUntilVisible(
          find.text('最新上架'),
          200,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
        );
        await tester.ensureVisible(find.text('最新上架'));
        await tester.pumpAndSettle();
        await shot(tester, 'latest-sell-$width-${mode.name}');
        await tester.drag(scroll, const Offset(0, -650));
        await tester.pumpAndSettle();
        await shot(tester, 'watch-$width-${mode.name}');
        for (final side in [0, 2]) {
          await c.setSide(side);
          await tester.pumpAndSettle();
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: scroll, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('最新上架'),
            200,
            scrollable: find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          );
          await tester.ensureVisible(find.text('最新上架'));
          await tester.pumpAndSettle();
          await shot(
            tester,
            'latest-${side == 0 ? 'buy' : 'barter'}-$width-${mode.name}',
          );
          if (side == 0) {
            position.jumpTo(730.0.clamp(0.0, position.maxScrollExtent));
            await tester.pumpAndSettle();
            await shot(tester, 'latest-buy-portrait-$width-${mode.name}');
          }
        }
        await c.browse(query: '巧匠');
        await tester.pumpAndSettle();
        await shot(tester, 'catalog-longname-$width-${mode.name}');
        await c.openItem(1);
        await tester.pumpAndSettle();
        expect(find.text('647'), findsOneWidget);
        expect(find.text('880'), findsOneWidget);
        expect(find.text('909'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'item-quality-$width-${mode.name}');
        {
          tester.view.physicalSize = Size(width.toDouble(), 2200);
          c.hall();
          await tester.pumpAndSettle();
          for (final side in [1, 0, 2]) {
            await c.setSide(side);
            await tester.pumpAndSettle();
            final position = tester
                .state<ScrollableState>(
                  find
                      .descendant(of: scroll, matching: find.byType(Scrollable))
                      .first,
                )
                .position;
            position.jumpTo(0);
            await tester.pumpAndSettle();
            await shot(
              tester,
              'full-${side == 1
                  ? 'sell'
                  : side == 0
                  ? 'buy'
                  : 'barter'}-$width-${mode.name}',
            );
          }
          tester.view.physicalSize = Size(width.toDouble(), 800);
          await c.openItem(1);
          await tester.pumpAndSettle();
        }
        if (width == 1280 && mode == AppearanceMode.dark) {
          c.selectItemTab(1);
          await tester.pumpAndSettle();
          await shot(tester, 'state-empty-buy-1280-dark');
          c.blocks.remove('trend');
          port.failTrend = true;
          await c.load('trend', 'trend', id: 1);
          c.selectItemTab(2);
          await tester.pumpAndSettle();
          await shot(tester, 'state-trend-failed-1280-dark');
          port.failTrend = false;
          port.readGate = Completer<void>();
          c.contextChanged();
          await tester.pumpAndSettle();
          await shot(tester, 'state-loading-1280-dark');
          port.readGate!.complete();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        imageMode.dispose();
      });
    }
  }
}
