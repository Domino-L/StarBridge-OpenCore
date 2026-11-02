// Trade reminders (CX-T23, user 10-28): clicking a trade card goes through the
// shared desktop-activation path, then opens 我的交易 and, with a ref, that
// transaction's sheet; a trade-chat card opens the conversation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../settings/desktop_notification_test.dart' show DesktopFake;
import '../friends/social_layout_test.dart' show loadFonts;
import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trades_test.dart' show TradesPort;

class _TradeDesktop extends DesktopFake
    implements
        DesktopNotificationActivationPort,
        DesktopNotificationDiagnostics,
        DesktopNotificationDestinationPort,
        DesktopNotificationTargetPort {
  final clicks = StreamController<DesktopReminderActivation>.broadcast();
  DesktopNotificationTarget? target;
  int consumed = 0;
  @override
  Stream<DesktopReminderActivation> get activations => clicks.stream;
  @override
  bool isCurrent(DesktopReminderActivation value) => value.generation == 1;
  @override
  Future<bool> consume(DesktopReminderActivation value) async => false;
  @override
  Future<String?> consumeDestination(DesktopReminderActivation value) async =>
      (await consumeTarget(value))?.destination;
  @override
  Future<DesktopNotificationTarget?> consumeTarget(
    DesktopReminderActivation value,
  ) async {
    consumed++;
    return target;
  }

  @override
  Future<DesktopNotificationTestResult> testDesktop() async =>
      const DesktopNotificationTestResult(false, 'doNotDisturb');
}

/// Trades whose detail can also be read by a reminder's opaque ref.
class _RefTrades extends TradesPort {
  final refs = <String>[];
  bool refFails = false;
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) {
    if (op == 'detail' && input['transactionRef'] is String) {
      refs.add(input['transactionRef'] as String);
      if (refFails) {
        return Future.error(
          const MarketplaceTradeError('marketplace.not_found'),
        );
      }
      return Future.value({...row, 'transactionNumber': 'T7'});
    }
    if (op == 'detail' && input['transactionNumber'] is String) {
      return Future.value({
        ...row,
        'transactionNumber': input['transactionNumber'],
      });
    }
    return super.trade(op, input);
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('a trade card opens 我的交易 in the hall', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = _TradeDesktop()
      ..target = (destination: 'myTrades', ref: null);
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      desktopNotifications: desktop,
      marketplacePortFactory: _RefTrades.new,
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    desktop.clicks.add(DesktopReminderActivation('a' * 32, 1));
    await tester.pumpAndSettle();
    expect(desktop.consumed, 1, reason: 'consumed once through the shell');
    expect(find.byType(MarketplaceTradesPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await desktop.clicks.close();
  });

  testWidgets('a ref opens that transaction\'s sheet, once', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _RefTrades();
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await c.trades.refresh();
    await tester.pumpWidget(
      preview(Scaffold(body: MarketplaceTradesPage(c)), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    c.trades.requestOpen('b' * 32);
    await tester.pumpAndSettle();
    expect(port.refs, ['b' * 32]);
    expect(find.byType(TradeSheet), findsOneWidget);
    expect(c.trades.detail?['transactionNumber'], 'T7');
    expect(c.trades.pendingRef, isNull, reason: 'taken once');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ref that no longer resolves leaves the list as it was', (
    tester,
  ) async {
    final port = _RefTrades()..refFails = true;
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      preview(Scaffold(body: MarketplaceTradesPage(c)), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    c.trades.requestOpen('c' * 32);
    await tester.pumpAndSettle();
    expect(find.byType(TradeSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
