// 0.7.2 G2 仓储 (read only; approved preview warehouse-preview, 2026-10-21).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_warehouse_page.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_test.dart' show FixturePort;

class WarehousePort extends FixturePort implements MarketplaceWarehousePort {
  final calls = <(String, MarketRow)>[];
  @override
  bool get warehouseSupported => true;
  @override
  Future<MarketRow> warehouse(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add((operation, input));
    return switch (operation) {
      'spaces' => {
        'rows': [
          {
            'id': 3,
            'name': '默认仓位',
            'isDefault': true,
            'location': '新巴贝奇',
            'locationPath': '新巴贝奇 · 微科星',
            'lines': 18,
            'onHand': 340,
            'reserved': 28,
            'available': 312,
          },
          {
            'id': 4,
            'name': '矿石仓',
            'locationPath': '洛维尔 · 斯坦顿',
            'lines': 6,
            'available': 96,
          },
        ],
      },
      'summary' => {
        'items': 24,
        'onHand': 436,
        'reserved': 28,
        'available': 408,
      },
      'inventory' => {
        'rows': [
          {
            'id': 1,
            'itemName': '科力晶（单个矿块）',
            'qualityData': '{"type":"material","quality":880}',
            'onHand': 24,
            'reserved': 8,
            'available': 16,
            'space': '默认仓位',
          },
          {
            'id': 2,
            'itemName': '实准 枪口补偿器 3',
            'onHand': 12,
            'reserved': 0,
            'available': 12,
            'space': '默认仓位',
          },
        ],
        'total': 2,
      },
      'ledger' => {
        'rows': [
          {
            'id': 70,
            'operationType': 'STOCK_OUT',
            'itemName': '科力晶（单个矿块）',
            'deltaOnHand': -8,
            'space': '默认仓位',
            'businessNo': 'TX88',
            'time': 1760000000000,
          },
          {
            'id': 71,
            'operationType': 'STOCK_IN',
            'itemName': '实准 枪口补偿器 3',
            'deltaOnHand': 12,
            'space': '默认仓位',
            'time': 1760000000000,
          },
        ],
        'total': 2,
      },
      _ => {
        'rows': [
          {
            'id': 40,
            'businessNo': 'SO88',
            'itemName': '科力晶（单个矿块）',
            'quantity': 8,
            'orderStatus': '上架中',
          },
        ],
        'more': false,
      },
    };
  }
}

Future<void> _render(WidgetTester tester, String name) async {
  const out = String.fromEnvironment('OUT');
  if (out.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('warehouse-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('audit2 warehouse quantities, labels, real quality and partial escrow', (tester) async {
    size(tester, const Size(1440, 1000));
    final market = MarketplaceController(AuditWarehousePort());
    addTearDown(market.dispose);
    await tester.pumpWidget(scopedApp(Scaffold(body: MarketplaceWarehousePage(market)), InteractionSuite.scan));
    await tester.pumpAndSettle();
    expect(find.text('18 行 · 可用 312'), findsOneWidget);
    expect(find.text('锁定'), findsOneWidget);
    expect(find.textContaining('44136'), findsNothing);
    expect(find.text('品质 880'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<(String, int)>(('market-warehouse-view', 1))));
    await tester.pumpAndSettle();
    expect(find.text('账本（只显示最近 30 天）'), findsOneWidget);
    for (final text in ['移动 50', '锁定 +16', '锁定 -16', '库存锁定', '释放锁定', '交易扣减', '容器迁移']) {
      expect(find.text(text), findsWidgets);
    }
    // The count rides inside the tab title: "托管 1+" (one row, more pages).
    expect(find.text('托管 1+'), findsOneWidget);
  });

  setUpAll(() async {
    if (const String.fromEnvironment('OUT').isEmpty) return;
    for (final (family, file) in [
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      final bytes = File(file).readAsBytesSync();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  testWidgets('spaces, items with escrow, ledger, escrow; read only', (
    tester,
  ) async {
    size(tester, const Size(1440, 800));
    final port = WarehousePort();
    final market = MarketplaceController(port);
    addTearDown(market.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('warehouse-render'),
        child: scopedApp(
          Scaffold(
            backgroundColor: const Color(0xFF0B1118),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: MarketplaceWarehousePage(market),
            ),
          ),
          InteractionSuite.scan,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('科力晶（单个矿块）'), findsOneWidget);
    expect(find.byKey(const Key('market-warehouse-readonly')), findsOneWidget);
    await _render(tester, 'warehouse-assets');

    await tester.tap(
      find.byKey(const ValueKey(('market-warehouse-space', '3'))),
    );
    await tester.pumpAndSettle();
    expect(port.calls.where((x) => x.$1 == 'inventory').last.$2['spaceId'], 3);

    await tester.tap(find.byKey(const ValueKey(('market-warehouse-view', 1))));
    await tester.pumpAndSettle();
    expect(find.text('-8'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    await _render(tester, 'warehouse-ledger');

    await tester.tap(find.byKey(const ValueKey(('market-warehouse-view', 2))));
    await tester.pumpAndSettle();
    expect(find.text('#SO88'), findsOneWidget);
    expect(port.calls.map((c) => c.$1).toSet(), {
      'spaces',
      'summary',
      'inventory',
      'ledger',
      'escrow',
    }, reason: 'reads only');
  });
}

class AuditWarehousePort extends WarehousePort {
  @override
  Future<MarketRow> warehouse(String operation, [MarketRow input = const {}]) async {
    if (operation == 'ledger') {
      return {
        'rows': <MarketRow>[
          {'id': 1, 'operationType': 'TRANSFER', 'itemName': '矿石', 'deltaOnHand': 0, 'movedQuantity': 50, 'from': 'A', 'to': 'B'},
          {'id': 2, 'operationType': 'RESERVE', 'itemName': '矿石', 'deltaOnHand': 0, 'deltaReserved': 16},
          {'id': 3, 'operationType': 'RELEASE', 'itemName': '矿石', 'deltaOnHand': 0, 'deltaReserved': -16},
          {'id': 4, 'operationType': 'CONSUME', 'itemName': '矿石', 'deltaOnHand': -8},
          {'id': 5, 'operationType': 'CONTAINER_TRANSFER', 'itemName': '矿石', 'deltaOnHand': 0, 'movedQuantity': 50, 'from': 'A', 'to': 'B'},
          // A transfer whose space names SCM left empty still shows its moved quantity.
          {'id': 6, 'operationType': 'TRANSFER', 'itemName': '矿石', 'deltaOnHand': 0, 'movedQuantity': 7},
        ], 'total': 6,
      };
    }
    if (operation == 'escrow') return {'rows': <MarketRow>[{'id': 40, 'quantity': 8}], 'next': 41, 'more': true};
    return super.warehouse(operation, input);
  }
}