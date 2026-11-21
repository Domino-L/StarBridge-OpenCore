import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contract_detail.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_mine.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_editor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_errors.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_publish_entry.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_recovery.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_entry.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_view.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile_summary.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_warehouse_page.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart' show scopedApp;
import 'marketplace_test.dart' show FixturePort;
import 'marketplace_contracts_page_test.dart' show ContractsPort;
import 'marketplace_write_signin_fixtures.dart';
import '../friends/social_layout_test.dart' show size;

Widget app(Widget child) => scopedApp(child, InteractionSuite.standard);

Future<void> openDialog(WidgetTester tester, Future<void> Function(BuildContext) open) async {
  size(tester, const Size(1280, 1000));
  await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
    onPressed: () => open(context), child: const Text('open'),
  ))));
  // Localizations load asynchronously: let the first frame build.
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class FirstContactPort implements MarketplaceChatPort {
  final calls = <String>[];
  bool opened = false;
  bool failOpen = false;
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => const Stream.empty();
  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    calls.add(operation);
    const row = {'ref': 'new-peer', 'name': 'New trader', 'unread': 0};
    if (operation == 'open') {
      expect(input['ref'], 'new-peer');
      if (failOpen) throw const MarketplaceTradeError('marketplace.unavailable');
      opened = true;
      return row;
    }
    return {'rows': operation == 'conversations' && opened ? [row] : []};
  }
}

/// Records what each send carried (CX-HALL-FIX2-REVIEW P2: attachments).
class _SendPort implements MarketplaceChatPort {
  final sends = <MarketRow>[];
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => const Stream.empty();
  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    if (operation == 'send') {
      sends.add({...input});
      return {'status': 'sent'};
    }
    return {'rows': operation == 'conversations' ? [
      {'ref': 'peer-a', 'name': 'A', 'unread': 0},
      {'ref': 'peer-b', 'name': 'B', 'unread': 0},
    ] : <MarketRow>[]};
  }
}

void main() {
  // Written before the U6 fix. The original entry only requested a ref;
  // no conversation row existed, so the view could not build its composer.
  testWidgets('first private contact opens a conversation and composer', (tester) async {
    final port = FirstContactPort();
    final chat = MarketplaceChatController(port);
    final market = MarketplaceController(FixturePort())..tradeChat = chat;
    addTearDown(market.dispose);
    addTearDown(chat.dispose);
    await tester.pumpWidget(app(Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => messageTradeCounterparty(context, market, {
          'counterpartyChat': 'new-peer', 'orderId': 1,
        }),
        child: const Text('contact'),
      ),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('contact'));
    await tester.pumpAndSettle();
    expect(port.calls, contains('open'));
    await tester.pumpWidget(app(Scaffold(body:
      MarketplaceTradeChatView(chat, header: const SizedBox.shrink()),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-chat-input')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('an order picked for one conversation never rides along to another', () async {
    final port = _SendPort();
    final chat = MarketplaceChatController(port);
    addTearDown(chat.dispose);
    chat.requestOpen('peer-a', attach: const MarketChatAttachment('SO7', 'order 7'));
    await chat.open('peer-b');
    expect(chat.attachment, isNull);
    await chat.send('hello B');
    expect(port.sends.single['orderNumber'], isNull);
    // Picked inside the open conversation, it goes with that conversation.
    chat.attachment = const MarketChatAttachment('SO8', 'order 8');
    await chat.send('hello again B');
    expect(port.sends.last['orderNumber'], 'SO8');
  });

  test('closing another conversation keeps an order picked for a pending one', () async {
    final port = _SendPort();
    final chat = MarketplaceChatController(port);
    addTearDown(chat.dispose);
    await chat.open('peer-b');
    chat.requestOpen('peer-a', attach: const MarketChatAttachment('SO7', 'order 7'));
    await chat.close();
    await chat.open('peer-a');
    expect(chat.attachment?.orderNumber, 'SO7');
    await chat.send('hello A');
    expect(port.sends.single['orderNumber'], 'SO7');
  });

  test('batch results tell refused, unconfirmed and unsent rows apart', () async {
    final refused = ListingWritePort()
      ..failure = const MarketplaceTradeError('marketplace.reauthorize_required');
    final c = MarketplaceListingsController(refused);
    addTearDown(c.dispose);
    final rows = [refused.row, {...refused.row, 'id': 2, 'name': 'Second'}];
    final first = await c.setVisibility(rows, false);
    expect(first.map((r) => r['state']), ['rejected', 'rejected']);
    expect(c.writeUncertain, isFalse);
    refused.failure = TimeoutException('fixture');
    final second = await c.setVisibility(rows, false);
    expect(second.map((r) => r['state']), ['uncertain', 'skipped']);
    expect(c.writeUncertain, isTrue);
  });

  testWidgets('failed first contact stays on the trade with an explanation', (tester) async {
    final port = FirstContactPort()..failOpen = true;
    final chat = MarketplaceChatController(port);
    final market = MarketplaceController(FixturePort())..tradeChat = chat;
    addTearDown(market.dispose);
    addTearDown(chat.dispose);
    var destinations = 0;
    market.openDestination = (_) { destinations++; };
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () => messageTradeCounterparty(context, market, {'counterpartyChat': 'new-peer'}),
      child: const Text('contact'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('contact'));
    await tester.pump();
    expect(find.text('暂时打不开会话，请稍后再试。'), findsOneWidget);
    expect(destinations, 0);
    expect(chat.pendingRef, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final action in ['cancel', 'create']) {
    testWidgets('reopened $action dialog can inspect a shared uncertain write', (tester) async {
      final port = WritePort()..failure = TimeoutException('fixture');
      final market = MarketplaceController(port);
      addTearDown(market.dispose);
      await market.trades.submit('cancel', {'transactionNumber': 'T1'});
      expect(market.trades.writeUncertain, isTrue);
      await openDialog(tester, (context) => action == 'cancel'
          ? tradeDialog(context, market, action, port.row)
          : confirmMarketTrade(context, market, {
              'orderNumber': 'O1', 'creatorType': 1,
              'locationId': 1, 'availableQuantity': 2, 'unitPrice': 10,
            }));
      expect(find.textContaining('不要重复提交'), findsOneWidget);
      final submit = find.byKey(Key(action == 'cancel'
          ? 'market-trade-action-submit' : 'market-confirm-submit'));
      expect(submit, findsNothing);
      await tester.tap(find.text('刷新交易单'));
      await tester.pumpAndSettle();
      expect(market.trades.writeUncertain, isFalse);
      // The checked dialog closes; a new one offers submission again.
      expect(find.byType(Dialog), findsNothing);
      expect(port.writes, 1);
      await openDialog(tester, (context) => action == 'cancel'
          ? tradeDialog(context, market, action, port.row)
          : confirmMarketTrade(context, market, {
              'orderNumber': 'O1', 'creatorType': 1,
              'locationId': 1, 'availableQuantity': 2, 'unitPrice': 10,
            }));
      expect(submit, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final failure in <Object>[
    const MarketplaceTradeError('marketplace.reauthorize_required'),
    const FormatException('marketplace.offline'),
    const MarketplaceTradeError('marketplace.invalid_request'),
  ]) {
    testWidgets('preflight rejection is definite for trades and listings: $failure', (tester) async {
      final code = marketplaceFailureCode(failure);
      final port = WritePort()..failure = failure;
      final market = MarketplaceController(port);
      final lp = ListingWritePort()..failure = failure;
      final listings = MarketplaceListingsController(lp);
      addTearDown(market.dispose);
      addTearDown(listings.dispose);
      var logins = 0;
      market.login = (_) async { logins++; };
      listings.login = market.login;
      await market.trades.submit('create', {});
      await listings.write('create', {});
      expect(market.trades.writeUncertain, isFalse);
      expect(listings.writeUncertain, isFalse);
      expect(market.trades.writeErrorCode, code);
      expect(listings.errorCode, code);
      await tester.pumpWidget(app(TradeFailure(market, writing: true, retry: () {})));
      await tester.pumpAndSettle();
      final message = tradeError(failure, writing: true);
      expect(find.text(message), findsOneWidget);
      if (code == 'marketplace.reauthorize_required') {
        await tester.tap(find.text('重新授权'));
        expect(logins, 1);
      }
      await tester.pumpWidget(app(Builder(builder: (context) => Column(children: [
        Text(listingErrorText(context, code, '')),
        if (marketplaceNeedsLogin(code)) MarketplaceAuthNotice(code, login: listings.login),
      ]))));
      await tester.pumpAndSettle();
      expect(find.text(message), findsWidgets);
      if (code == 'marketplace.reauthorize_required') {
        await tester.tap(find.text('重新授权'));
        expect(logins, 2);
      }
      await listings.setVisibility([lp.row], false);
      expect(listings.writeUncertain, isFalse);
      expect(listings.errorCode, code);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // The Host returns these after a request may already have reached SCM,
  // so a write stays uncertain (no blind retry, no duplicate trade).
  // Also the port's own check on a response that already came back.
  for (final failure in <Object>[
    const MarketplaceTradeError('marketplace.unavailable'),
    const MarketplaceTradeError('marketplace.context_changed'),
    const FormatException('marketplace.unavailable'),
  ]) {
    test('after sending, $failure keeps a write uncertain', () async {
      final port = WritePort()..failure = failure;
      final market = MarketplaceController(port);
      final lp = ListingWritePort()..failure = failure;
      final listings = MarketplaceListingsController(lp);
      addTearDown(market.dispose);
      addTearDown(listings.dispose);
      await market.trades.submit('create', {});
      await listings.write('create', {});
      expect(market.trades.writeUncertain, isTrue);
      expect(listings.writeUncertain, isTrue);
    });
  }

  testWidgets('uncertain listing disables actions and one inspection unlocks them', (tester) async {
    size(tester, const Size(1280, 1000));
    final port = ListingWritePort()..failure = TimeoutException('fixture');
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(MarketplaceListingsPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<(String, Object?)>(('market-listing-select', 1))));
    await tester.pumpAndSettle();
    await c.write('update', {'id': 1});
    await tester.pumpAndSettle();
    expect(find.text('请先刷新核对上次操作结果，再编辑或发布挂单'), findsOneWidget);
    for (final key in ['market-listing-edit', 'market-listing-more']) {
      final icon = find.byWidgetPredicate((w) => w is StarBridgeNativeIconAction &&
          (w.key == ValueKey<(String, Object?)>((key, 1)) ||
              w.controlKey == ValueKey<(String, Object?)>((key, 1))));
      expect(tester.widget<StarBridgeNativeIconAction>(icon).onActivate, isNull);
    }
    for (final label in ['发布挂单', '上架', '下架', '复制为新挂单']) {
      final buttons = find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(buttons, findsWidgets);
      for (final button in tester.widgetList<ButtonStyleButton>(buttons)) {
        expect(button.onPressed, isNull);
      }
    }
    expect(await c.setVisibility([port.row], true), isEmpty);
    expect(find.textContaining('成功 0'), findsNothing);
    final reads = port.reads;
    await tester.tap(find.text('已核对，继续操作'));
    await tester.pumpAndSettle();
    expect(port.reads, reads + 1);
    expect(c.writeUncertain, isFalse);
    expect(port.writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('publish review inspects uncertainty without repeating a write', (tester) async {
    final port = ListingWritePort()..failure = TimeoutException('fixture');
    final c = MarketplaceListingsController(port);
    addTearDown(c.dispose);
    await c.write('create', {});
    await openDialog(tester, (context) => showDialog<void>(
      context: context,
      builder: (_) => ListingPublishDialog(c, ListingDraft(
        item: {'id': 1, 'name': 'Fixture'}, price: '10', location: '1',
      ), initialStep: 3),
    ));
    expect(find.text('刷新核对'), findsOneWidget);
    await tester.tap(find.text('刷新核对'));
    await tester.pumpAndSettle();
    expect(c.writeUncertain, isFalse);
    expect(port.writes, 1);
    // The listing may already exist: the wizard closes rather than offering
    // 发布 again (CX-HALL-FIX2-REVIEW P1).
    expect(find.byType(ListingPublishDialog), findsNothing);
    expect(find.text('发布'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('listing editor reauthorization action calls the supplied login', (tester) async {
    final p = ListingWritePort()..failure = const MarketplaceTradeError('marketplace.reauthorize_required');
    final c = MarketplaceListingsController(p);
    addTearDown(c.dispose);
    var logins = 0;
    c.login = (_) async { logins++; };
    await openDialog(tester, (context) => editListing(context, c, p.row));
    await tester.tap(find.byKey(const Key('market-listing-save')));
    await tester.pumpAndSettle();
    expect(c.writeUncertain, isFalse);
    expect(find.text('需要重新授权 SCM 才能操作'), findsWidgets);
    await tester.tap(find.text('重新授权'));
    expect(logins, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('failed listing readback never unlocks an uncertain write', () async {
    final p = ListingWritePort()..failure = TimeoutException('fixture');
    final c = MarketplaceListingsController(p);
    await c.write('create', {});
    await c.refresh();
    p.readFailure = true;
    await c.inspectUncertainWrite();
    expect(c.writeUncertain, isTrue);
    c.dispose();
  });

  for (final remaining in [0, 3, 10]) {
    testWidgets('editor preserves expiry choice for $remaining remaining days', (tester) async {
      final now = DateTime.utc(2026, 11, 14);
      final expiry = remaining == 0 ? null : now.add(Duration(days: remaining)).toIso8601String();
      final expected = remaining == 0 ? 0 : remaining <= 7 ? 7 : 14;
      expect(listingExpiryDays(expiry, now: now), expected);
      final p = ListingWritePort();
      p.row['expiry'] = remaining == 0 ? null : DateTime.now().add(Duration(days: remaining)).toIso8601String();
      final c = MarketplaceListingsController(p);
      addTearDown(c.dispose);
      await openDialog(tester, (context) => editListing(context, c, p.row));
      expect(find.text('保存后有效期从现在重新计算'), findsOneWidget);
      await tester.tap(find.byKey(const Key('market-listing-save')));
      await tester.pumpAndSettle();
      expect(p.lastInput?['expiryDays'], expected);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // SCM stores a permanent listing as 9999-12-31 23:59:59 (epoch ms or text).
  for (final permanent in <Object>[253402271999000, '9999-12-31 23:59:59']) {
    testWidgets('permanent listing ($permanent) stays permanent after a price-only edit', (tester) async {
      expect(listingExpiryDays(permanent, now: DateTime.utc(2026, 11, 14)), 0);
      final p = ListingWritePort();
      p.row['expiry'] = permanent;
      final c = MarketplaceListingsController(p);
      addTearDown(c.dispose);
      await openDialog(tester, (context) => editListing(context, c, p.row));
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.tap(find.byKey(const Key('market-listing-save')));
      await tester.pumpAndSettle();
      expect(p.lastInput?['price'], 25);
      expect(p.lastInput?['expiryDays'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('signed out hall shows login instead of an endless progress bar', (tester) async {
    final (c, close) = await signedOutHall();
    addTearDown(close);
    var logins = 0;
    c.login = (_) async { logins++; };
    await c.refreshMyOrders();
    expect(c.myListingsError, 'marketplace.sign_in_required');
    await tester.pumpWidget(app(MarketMyListingsStrip(c)));
    await tester.pumpAndSettle();
    expect(find.text('登录 SCM 后可以发布和管理挂单'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('登录'));
    expect(logins, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('banner todo remains unknown until a successful list read', (tester) async {
    size(tester, const Size(1280, 900));
    final p = WritePort();
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    Widget banner() => app(MarketHallHead(c, search: const SizedBox.shrink(), onRefresh: null));
    Finder todoValue() => find.descendant(
      of: find.ancestor(of: find.text('待我处理'), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Stat')),
      matching: find.text('—'),
    );
    await tester.pumpWidget(banner());
    await tester.pumpAndSettle();
    expect(todoValue(), findsOneWidget);
    expect(c.trades.listLoaded, isFalse);
    await c.trades.refresh();
    p.listFailure = true;
    await c.trades.refresh();
    await tester.pumpWidget(banner());
    expect(c.trades.listFailed, isTrue);
    expect(todoValue(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final code in ['marketplace.sign_in_required', 'marketplace.reauthorize_required']) {
    for (final page in ['contracts', 'warehouse', 'reviews', 'reports', 'blocks']) {
      testWidgets('$page offers the correct login action for $code', (tester) async {
        size(tester, const Size(1280, 1000));
        final port = ReadAuthPort(code);
        final market = MarketplaceController(port);
        final records = MarketplaceRecordsController(port);
        addTearDown(market.dispose);
        addTearDown(records.dispose);
        var logins = 0;
        market.login = (_) async { logins++; };
        await tester.pumpWidget(app(switch (page) {
          'contracts' => MarketplaceContractsPage(market),
          'warehouse' => MarketplaceWarehousePage(market),
          'reviews' => MarketplaceReviewsView(records, login: market.login),
          _ => MarketplaceReportsBlocksView(records, login: market.login),
        }));
        await tester.pumpAndSettle();
        if (page == 'blocks') {
          await tester.tap(find.text('黑名单'));
          await tester.pumpAndSettle();
        }
        final label = code.endsWith('sign_in_required') ? '登录' : '重新授权';
        expect(find.text(label), findsWidgets);
        await tester.tap(find.text(label).first);
        expect(logins, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('trade write failure does not masquerade as list loading failure', (tester) async {
    final port = WritePort();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await c.trades.refresh();
    port.failure = const MarketplaceTradeError('marketplace.trade_rejected');
    await c.trades.submit('cancel', {'transactionNumber': 'T1'});
    expect(c.trades.listFailed, isFalse);
    await tester.pumpWidget(app(MarketplaceTradesPage(c)));
    await tester.pumpAndSettle();
    expect(find.text('加载失败 · 重试'), findsNothing);
    port.listFailure = true;
    await c.trades.refresh();
    await tester.pumpAndSettle();
    expect(find.text('加载失败 · 重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mine in [false, true]) {
    testWidgets('contract eligibility without fictional approval for creator=$mine', (tester) async {
      final port = ContractsPort();
      final market = MarketplaceController(port);
      final c = MarketplaceContractsController(port);
      addTearDown(market.dispose);
      addTearDown(c.dispose);
      await c.open(17);
      c.detail = {...c.detail!,
        'contract': {...(c.detail!['contract'] as Map).cast<String, Object?>(), 'mine': mine, 'eligible': false},
        'participants': {'rows': [{'id': 1, 'name': 'Applicant', 'status': 0}], 'total': 1},
      };
      await openDialog(tester, (context) => showContractDetail(context, market, c));
      if (mine) {
        expect(find.text('报名需要在 SCM 网站审核'), findsNothing);
      } else {
        final button = find.descendant(
          of: find.byKey(const ValueKey(('market-contract-action', 'apply'))),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('failed spaces expose a working retry', (tester) async {
    size(tester, const Size(1280, 900));
    final p = ReadAuthPort('marketplace.unavailable')..spacesOnly = true;
    final c = MarketplaceController(p);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(MarketplaceWarehousePage(c)));
    await tester.pumpAndSettle();
    expect(find.text('暂时读不到仓位，请重试'), findsOneWidget);
    final before = p.spaceReads;
    await tester.tap(find.byKey(const Key('market-warehouse-spaces-retry')));
    await tester.pumpAndSettle();
    expect(p.spaceReads, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow item failure exposes retry instead of a loading name', (tester) async {
    size(tester, const Size(700, 1000));
    final c = MarketplaceController(FixturePort())..itemId = 1;
    c.failures.add('item');
    addTearDown(c.dispose);
    await tester.pumpWidget(app(MarketplaceItemPage(c)));
    await tester.pumpAndSettle();
    expect(find.text('暂不可用'), findsWidgets);
    expect(find.text('重试'), findsWidgets);
    expect(find.text('正在读取…'), findsNothing);
    await tester.tap(find.text('重试').first);
    await tester.pumpAndSettle();
    expect(c.failures.contains('item'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final card in [false, true]) {
    testWidgets('overlay profile summary hides edit, card=$card', (tester) async {
      final (c, close) = await signedOutHall();
      c.profileEditedInClient = true;
      addTearDown(close);
      await tester.pumpWidget(app(TradeProfileSummary(c, card: card)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('market-trade-profile-summary-edit')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('overlay publish entry does not offer profile editing', (tester) async {
    final (c, close) = await signedOutHall();
    c.profileEditedInClient = true;
    addTearDown(close);
    await openDialog(tester, (context) => openMarketPublish(context, c,
      item: {'id': 1, 'name': 'Fixture'},
    ));
    expect(find.byKey(const Key('market-publish-profile')), findsNothing);
    await tester.tap(find.byKey(const Key('market-publish-cancel')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
