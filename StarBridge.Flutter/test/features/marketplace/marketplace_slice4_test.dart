// Local UI fixtures only. Never registered by production composition.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

class ListingsFixture implements MarketplaceListingsPort {
  final calls = <String>[];
  bool fail = false;
  final rows = <MarketRow>[
    for (final r in [
      ('科力晶（单个矿块）', 'sell', 1250000, 5, 702, true, 1200000),
      ('TS-35 婆娑罗（3.5倍光学）', 'sell', 2900000, 2, null, true, 2900000),
      ('被辐射的瓦拉卡蠕虫珍珠（AAA级）', 'buy', 950000, 10, null, true, 1000000),
      ('HG-15 猎人（1.5倍全息）', 'sell', 1600000, 1, null, false, 1500000),
    ])
      {
        'id': r.$1,
        'itemId': r.$1,
        'name': r.$1,
        'side': r.$2,
        'price': r.$3,
        'quantity': r.$4,
        'quality': r.$5,
        'visible': r.$6,
        'best': r.$7,
        'location': '1',
        'expiry': '10/24 到期',
      },
  ];
  @override
  Future<MarketRow> read() async {
    if (fail) throw StateError('fixture read failure');
    return {
      'rows': rows.map((r) => Map<String, Object?>.from(r)).toList(),
      'limit': 20,
      'items': [
        for (final r in rows)
          {
            'id': r['itemId'],
            'name': r['name'],
            'best': r['best'],
            'sellCount': 4,
            'buyCount': 2,
            'hasQuality': r['quality'] != null,
          },
      ],
      'locations': [
        {'id': '1', 'name': '新巴贝奇'},
      ],
      'tradeWindow': '每天 19:00–22:00',
      'manifests': [
        {
          'id': 'M1',
          'name': '瞄具打包',
          'updated': '10/09 更新',
          'items': [rows[1], rows[3]],
        },
      ],
    };
  }

  @override
  Future<void> write(String op, MarketRow input) async {
    calls.add('$op:${input['id']}');
    if (op == 'visibility' && input['id'] == rows[1]['id']) {
      throw const MarketplaceTradeError('marketplace.listing_has_ongoing');
    }
    if (op == 'visibility') {
      rows.firstWhere((r) => r['id'] == input['id'])['visible'] =
          input['visible'];
    }
  }
}

Widget preview(Widget child, AppearanceMode appearance) => RepaintBoundary(
  key: const Key('listing-preview'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(appearance),
      const Locale('zh', 'CN'),
    ),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('MARKET_SLICE4_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('listing-preview')),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory(
      '../.artifacts/trading-hall-intake-20261015/slice4-round1/renders',
    );
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('MARKET_SLICE4_CAPTURE')) return;
    for (final p in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Microsoft YaHei UI', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      await (FontLoader(p.$1)..addFont(rootBundle.load(p.$2))).load();
    }
  });
  test('publishing boundaries and barter omit monetary amount', () {
    final d = ListingDraft(item: {'id': 1}, location: '1', price: '0');
    expect(d.validation, isNotNull);
    d.price = '1';
    d.quantity = '1000000';
    expect(d.validation, isNotNull);
    d.quantity = '999999';
    d.price = '1000000000000000';
    expect(d.validation, isNull);
    d.price = 'NaN';
    expect(d.validation, isNotNull);
    d.side = 'barter';
    d.price = '';
    d.wanted = '2';
    expect(d.validation, isNull);
    expect(d.toInput().containsKey('price'), isFalse);
    expect(d.toInput()['wanted'], [{'itemId': 2, 'quantity': 1}]);
    d.location = '';
    expect(d.validation, isNotNull);
  });
  test(
    'selected visibility runs sequentially and preserves partial outcomes',
    () async {
      final p = ListingsFixture();
      final controller = MarketplaceListingsController(p);
      await controller.refresh();
      final result = await controller.setVisibility(
        controller.rows.take(3).toList(),
        false,
      );
      expect(p.calls, hasLength(3));
      expect(result.map((r) => r['success']), [true, false, true]);
      p.fail = true;
      await controller.refresh();
      expect(controller.rows, hasLength(4));
      expect(controller.error, isNotNull);
      controller.dispose();
    },
  );
  for (final width in [1280.0, 900.0]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('slice 4 fixture $width ${mode.name}', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = MarketplaceListingsController(ListingsFixture());
        await tester.pumpWidget(preview(MarketplaceListingsPage(c), mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, 'listings-${width.toInt()}-${mode.name}');
        await tester.tap(find.text('发布挂单'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('publish-step-0')), findsOneWidget);
        await capture(tester, 'publish1-${width.toInt()}-${mode.name}');
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('科力晶（单个矿块）'),
          ),
        );
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('publish-step-2')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'publish3-${width.toInt()}-${mode.name}');
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      });
    }
  }
}
