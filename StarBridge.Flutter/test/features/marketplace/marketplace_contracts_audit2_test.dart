import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contract_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import '../../design_system/interaction/interaction_batch3i_test.dart' show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_test.dart' show FixturePort;

class _Port extends FixturePort implements MarketplaceContractsPort {
  bool mine = true;
  int status = 2, participantStatus = 3, taken = 1;
  bool? eligible;
  String? error;
  bool failRefresh = false;
  final calls = <(String, MarketRow)>[];
  @override
  bool get contractsSupported => true;
  @override
  Future<MarketRow> contracts(String operation, [MarketRow input = const {}]) async {
    calls.add((operation, input));
    if (operation == 'detail') {
      if (failRefresh) throw const MarketplaceTradeError('marketplace.unavailable');
      final person = <String, Object?>{'reference': 'opaque-person', 'name': 'A***r',
        'status': participantStatus, 'reviewedByCreator': false, 'reviewedByParticipant': false};
      return {
        'contract': {'id': 17, 'title': '合约测试', 'type': 'SERVICE', 'status': status,
          'mine': mine, 'taken': taken, 'slots': 3, 'eligible': eligible,
          'fleet': true, 'fleetSid': 'TESTFLEET', 'creator': 'K***l'},
        'participants': {'rows': [person], 'total': 1},
        if (!mine && participantStatus != 0) 'me': person,
      };
    }
    if (operation == 'list') {
      return {
        'rows': [{'id': 17, 'title': '合约测试', 'type': 'SERVICE', 'status': 2,
          'rewardType': 'UEC', 'rewardUec': 10}], 'total': 40,
      };
    }
    if (operation == 'mine') return {'rows': <MarketRow>[], 'total': 0};
    if (error != null) throw MarketplaceTradeError(error!);
    return {'confirmed': true};
  }
}

Finder _action(String op) => find.byKey(ValueKey<(String, String)>(('market-contract-action', op)));
Finder get _remove => find.byKey(const ValueKey<(String, String)>(('market-contract-remove', 'opaque-person')));

Future<MarketplaceContractsController> _detail(WidgetTester tester, _Port port) async {
  size(tester, const Size(1440, 1000));
  final market = MarketplaceController(port);
  final c = MarketplaceContractsController(port);
  addTearDown(market.dispose);
  addTearDown(c.dispose);
  await c.open(17);
  await tester.pumpWidget(scopedApp(Scaffold(body: Builder(builder: (context) =>
    TextButton(onPressed: () => showContractDetail(context, market, c), child: const Text('open')))), InteractionSuite.scan));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (final state in [1, 3, 4, 5]) {
    testWidgets('remove active participant $state, confirm once', (tester) async {
      final port = _Port()..participantStatus = state;
      await _detail(tester, port);
      expect(_remove, findsOneWidget);
      expect(_action('apply'), findsNothing);
      expect(find.textContaining('TESTFLEET'), findsOneWidget);
      expect(find.textContaining('报名需要在 SCM 网站审核'), findsNothing);
      await tester.ensureVisible(_remove);
      await tester.tap(_remove);
      await tester.pumpAndSettle();
      expect(find.text('移出 A***r'), findsOneWidget);
      expect(find.text('对方会被移出这个合约，名额释放；对方会在 SCM 看到被移除和原因。'), findsOneWidget);
      expect(find.text('可选，例如联系不上或中途退出'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('market-contract-input'))).maxLength, 200);
      final confirm = find.descendant(of: find.byKey(const Key('market-contract-dialog-confirm')), matching: find.byType(StarBridgeActionButton));
      final button = tester.widget<StarBridgeActionButton>(confirm);
      expect(button.nativeStyle!.backgroundColor!.resolve({}), Theme.of(tester.element(confirm)).colorScheme.error);
      await tester.enterText(find.byKey(const Key('market-contract-input')), ' 联系不上 ');
      await tester.tap(find.byKey(const Key('market-contract-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(port.calls.where((x) => x.$1 == 'remove').single.$2,
        {'id': 17, 'participantRef': 'opaque-person', 'reason': '联系不上'});
    });
  }
  for (final (mine, status, person) in <(bool, int, int)>[
    (false, 2, 3), (true, 3, 4), (true, 4, 3), (true, 2, 0), (true, 2, 2), (true, 2, 6),
  ]) {
    testWidgets('remove hidden for $mine/$status/$person', (tester) async {
      await _detail(tester, _Port()..mine = mine..status = status..participantStatus = person);
      expect(_remove, findsNothing);
    });
  }
  testWidgets('uncertain remove blocks replay until explicit successful refresh', (tester) async {
    final port = _Port()..error = 'marketplace.trade_rejected';
    final c = await _detail(tester, port);
    await tester.ensureVisible(_remove);
    await tester.tap(_remove);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-contract-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('操作结果不确定，请刷新核对参与者状态，再决定下一步。'), findsWidgets);
    expect(c.needsReconcile, isTrue);
    expect(await c.act('remove', {'participantRef': 'opaque-person'}), isFalse);
    expect(port.calls.where((x) => x.$1 == 'remove'), hasLength(1));
    port.failRefresh = true;
    await c.refreshDetail();
    expect(c.needsReconcile, isTrue);
    port.failRefresh = false;
    port.participantStatus = 2;
    await tester.tap(find.text('刷新核对'));
    await tester.pumpAndSettle();
    expect(_remove, findsNothing);
    expect(c.needsReconcile, isFalse);
  });
  testWidgets('running publisher can cancel and complete only with participants', (tester) async {
    final port = _Port()..taken = 0;
    final c = await _detail(tester, port);
    expect(_action('cancel'), findsOneWidget);
    expect(_action('complete'), findsNothing);
    port.taken = 1;
    await c.refreshDetail();
    await tester.pumpAndSettle();
    expect(_action('complete'), findsOneWidget);
  });
  for (final eligible in <bool?>[false, null, true]) {
    testWidgets('running contract applies with reputation $eligible', (tester) async {
      await _detail(tester, _Port()..mine = false..participantStatus = 0..eligible = eligible);
      final button = tester.widget<StarBridgeActionButton>(find.descendant(of: _action('apply'), matching: find.byType(StarBridgeActionButton)));
      expect(button.onActivate != null, eligible != false);
    });
  }
  testWidgets('running participant can quit', (tester) async {
    await _detail(tester, _Port()..mine = false);
    expect(_action('quit'), findsOneWidget);
    expect(_action('apply'), findsNothing);
  });
  testWidgets('local filter empty state keeps count clear and paging reachable', (tester) async {
    size(tester, const Size(1440, 1000));
    final port = _Port();
    final market = MarketplaceController(port);
    addTearDown(market.dispose);
    await tester.pumpWidget(scopedApp(Scaffold(body: MarketplaceContractsPage(market)), InteractionSuite.scan));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<(String, String, String)>(('market-contracts-filter', 'reward', 'ITEMS'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('本页 0 个（共 40 个）'), findsOneWidget);
    expect(find.text('这一页没有符合条件的合约'), findsOneWidget);
    expect(find.text('已报名'), findsNothing);
    await tester.tap(find.byKey(const Key('market-contracts-more')));
    await tester.pumpAndSettle();
    expect(port.calls.where((x) => x.$1 == 'list').last.$2['page'], 2);
    await tester.tap(find.byKey(const Key('market-contracts-clear')));
    await tester.pumpAndSettle();
    expect(find.text('这一页没有符合条件的合约'), findsNothing);
  });
  test('attention counts actions across scopes, deduplicates, marks partial reads', () {
    final c = MarketplaceContractsController(_Port());
    addTearDown(c.dispose);
    c.created.page = c.participated.page = 1;
    c.created.rows = [{'id': 1, 'attention': true, 'attentionComplete': true},
      {'id': 2, 'applications': 100, 'attention': false, 'attentionComplete': true}];
    c.created.total = 2;
    c.participated.rows = [{'id': 3, 'attention': true, 'attentionComplete': true}];
    c.participated.total = 2;
    expect(c.attention, 2);
    expect(c.attentionIncomplete, isTrue);
    c.participated.total = 1;
    expect(c.attentionIncomplete, isFalse);
    c.created.rows = [{'id': 1, 'attention': false, 'attentionComplete': false}];
    expect(c.attentionIncomplete, isTrue);
  });
  for (final code in ['marketplace.reauthorize_required', 'marketplace.invalid_request',
    'marketplace.offline', 'marketplace.sign_in_required', 'marketplace.forbidden', 'marketplace.unavailable']) {
    test('write outcome classification $code', () async {
      final c = MarketplaceContractsController(_Port()..error = code);
      addTearDown(c.dispose);
      await c.open(17);
      expect(await c.act('remove', {'participantRef': 'opaque-person'}), isFalse);
      expect(c.resultUnknown, !const ['marketplace.reauthorize_required',
        'marketplace.invalid_request', 'marketplace.offline'].contains(code));
    });
  }
  test('all new contract copy has three languages', () {
    for (final key in ['移出参与者', '移出 {name}', '刷新核对', '待我处理 {n}',
      '本页 {n} 个（共 {total} 个）· {sort}', '这一页没有符合条件的合约', '清除筛选', '加载更多']) {
      expect(contractCopy[key], hasLength(3));
      expect(contractCopy[key]!.every((text) => text.isNotEmpty), isTrue);
    }
  });
}