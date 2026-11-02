// 0.7.2 G1 合约 (approved preview contracts-preview, 2026-10-21): open list
// with filters, detail panel with role actions, 我发布的 / 我参与的, publish.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_test.dart' show FixturePort;

final _expire = DateTime.now()
    .add(const Duration(days: 2, hours: 1))
    .millisecondsSinceEpoch;

MarketRow _contract(
  int id,
  String type,
  String title, {
  Object? uec,
  String? note,
  bool mine = false,
  int status = 1,
  bool applied = false,
}) => {
  'id': id,
  'number': 'CT-20261021000$id',
  'type': type,
  'title': title,
  'rewardType': uec == null ? 'ITEMS' : 'UEC',
  'rewardUec': ?uec,
  'rewardNote': ?note,
  'slots': 3,
  'taken': 0,
  'minReputation': 50,
  'location': '哈索 · 斯坦顿',
  'expireTime': _expire,
  'creator': 'K***r',
  'creatorOnline': true,
  'creatorReputation': 80,
  'creatorChat': 'c' * 32,
  'status': status,
  'mine': mine,
  'applied': applied,
  'eligible': true,
  'description': '目标会在本周六 20:00 前后从哈索出发。\n拦截后需要提供截图作为完成凭证。',
};

class ContractsPort extends FixturePort implements MarketplaceContractsPort {
  final calls = <(String, MarketRow)>[];
  bool applied = false;
  @override
  bool get contractsSupported => true;
  @override
  Future<MarketRow> contracts(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add((operation, input));
    switch (operation) {
      case 'list':
        return {
          'rows': [
            _contract(
              17,
              'BOUNTY',
              '找到并拦截 @R***m 的货船（Hull C，哈索航线）',
              uec: 2500000,
              applied: applied,
            ),
            _contract(18, 'SERVICE', '帮忙从新巴贝奇运 96 SCU 医疗物资到洛维尔', uec: 380000),
            _contract(
              19,
              'COOPERATION',
              '周末舰队采矿：需要 2 名 Prospector 和 1 名护航',
              note: '按产量分成（量子燃料 + 矿石 30%）',
            ),
          ],
          'total': 3,
        };
      case 'mine':
        return input['scope'] == 'participated'
            ? {
                'rows': [
                  _contract(30, 'BOUNTY', '清剿克罗地区海盗前哨', uec: 900000, status: 2),
                ],
                'total': 1,
              }
            : {
                'rows': [
                  _contract(
                    31,
                    'COOPERATION',
                    '周末舰队采矿',
                    note: '分成',
                    mine: true,
                  ),
                  _contract(
                    32,
                    'SERVICE',
                    '运 40 SCU 钛到微科星',
                    uec: 200000,
                    mine: true,
                    status: 3,
                  ),
                ],
                'total': 2,
              };
      case 'detail':
        return {
          'contract': _contract(
            input['id'] as int,
            'BOUNTY',
            '找到并拦截 @R***m 的货船（Hull C，哈索航线）',
            uec: 2500000,
            applied: applied,
          ),
          'milestones': [
            {
              'id': 1,
              'order': 1,
              'title': '确认目标航线',
              'status': 1,
              'completeTime': _expire,
            },
            {'id': 2, 'order': 2, 'title': '拦截并提交截图', 'status': 0},
          ],
          'participants': {'rows': const [], 'total': 0},
          if (applied) 'me': {'id': 6, 'status': 0},
        };
      case 'apply':
        applied = true;
        return {'confirmed': true, 'participantId': 6};
      case 'create':
        return {'id': 99};
    }
    return {'confirmed': true};
  }
}

Future<void> _render(WidgetTester tester, String name) async {
  const out = String.fromEnvironment('OUT');
  if (out.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('contracts-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _app(Widget child) => RepaintBoundary(
  key: const Key('contracts-render'),
  child: scopedApp(
    Scaffold(
      backgroundColor: const Color(0xFF0B1118),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: child,
      ),
    ),
    InteractionSuite.scan,
  ),
);

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('OUT').isEmpty) return;
    for (final (family, file) in [
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final bytes = File(file).readAsBytesSync();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final width in [1100.0, 1440.0, 2500.0]) {
    testWidgets('the sort buttons and publish reach the right edge at $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final market = MarketplaceController(ContractsPort());
      addTearDown(market.dispose);
      await tester.pumpWidget(_app(MarketplaceContractsPage(market)));
      await tester.pumpAndSettle();
      final publish = tester.getTopRight(
        find.byKey(const Key('market-contracts-publish')),
      );
      expect(publish.dx, closeTo(width - 24, 1));
      expect(
        tester.getTopLeft(find.textContaining('最新发布').first).dx,
        lessThan(tester.getTopLeft(
          find.byKey(const ValueKey(('market-contracts-sort', 'new'))),
        ).dx),
        reason: 'the count stays left of the sort buttons',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open contracts: cards, filters, detail, apply once', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    final port = ContractsPort();
    final market = MarketplaceController(port);
    addTearDown(market.dispose);
    await tester.pumpWidget(_app(MarketplaceContractsPage(market)));
    await tester.pumpAndSettle();
    expect(find.text('找到并拦截 @R***m 的货船（Hull C，哈索航线）'), findsOneWidget);
    expect(
      find.text('按产量分成（量子燃料 + 矿石 30%）'),
      findsOneWidget,
      reason: 'item reward in gold',
    );
    expect(port.calls.first.$2, {
      'page': 1,
      'status': 1,
    }, reason: 'recruiting by default');
    await _render(tester, 'contracts-public');

    await tester.tap(
      find.byKey(const ValueKey(('market-contracts-filter', 'type', 'BOUNTY'))),
    );
    await tester.pumpAndSettle();
    expect(port.calls.last.$2, {'page': 1, 'type': 'BOUNTY', 'status': 1});
    await tester.tap(
      find.byKey(
        const ValueKey(('market-contracts-filter', 'reward', 'ITEMS')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('找到并拦截 @R***m 的货船（Hull C，哈索航线）'),
      findsNothing,
      reason: 'reward filter is local',
    );
    await tester.tap(
      find.byKey(const ValueKey(('market-contracts-filter', 'reward', 'all'))),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey(('market-contract-card', '17'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认目标航线'), findsOneWidget);
    expect(find.text('还没有人报名。'), findsOneWidget);
    await _render(tester, 'contracts-detail');

    await tester.tap(
      find.byKey(const ValueKey(('market-contract-action', 'apply'))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('market-contract-input')),
      '  有 F7C Hornet  ',
    );
    await tester.tap(find.byKey(const Key('market-contract-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(port.calls.where((x) => x.$1 == 'apply').single.$2, {
      'id': 17,
      'message': '有 F7C Hornet',
    });
    expect(
      find.byKey(const ValueKey(('market-contract-action', 'apply'))),
      findsNothing,
      reason: 'applied: the panel re-read',
    );
    expect(
      find.byKey(const ValueKey(('market-contract-action', 'quit'))),
      findsOneWidget,
    );
  });

  testWidgets('mine: grouped by state; publish checks SCM limits first', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    final port = ContractsPort();
    final market = MarketplaceController(port);
    addTearDown(market.dispose);
    await tester.pumpWidget(_app(MarketplaceContractsPage(market)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('market-contracts-view', 1))));
    await tester.pumpAndSettle();
    expect(find.text('周末舰队采矿'), findsOneWidget);
    expect(find.text('运 40 SCU 钛到微科星'), findsOneWidget);
    await _render(tester, 'contracts-mine');

    await tester.tap(find.byKey(const ValueKey(('market-contracts-view', 0))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-contracts-publish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-contract-publish-submit')));
    await tester.pumpAndSettle();
    expect(
      port.calls.where((x) => x.$1 == 'create'),
      isEmpty,
      reason: 'title and reward are required',
    );
    await tester.enterText(
      find.byKey(const Key('market-contract-publish-title')),
      '帮忙从新巴贝奇运 96 SCU 医疗物资到洛维尔',
    );
    await tester.enterText(
      find.byKey(const Key('market-contract-publish-uec')),
      '380000',
    );
    await _render(tester, 'contracts-publish');
    await tester.tap(find.byKey(const Key('market-contract-publish-submit')));
    await tester.pumpAndSettle();
    final created =
        port.calls.where((x) => x.$1 == 'create').single.$2['contract'] as Map;
    expect(created['type'], 'SERVICE');
    expect(created['rewardUec'], 380000);
    expect(created['slots'], 1);
    expect(
      created['expireTime'] as int,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
  });
}
