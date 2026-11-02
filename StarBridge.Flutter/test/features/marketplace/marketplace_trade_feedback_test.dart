import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';

import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trades_test.dart' show TradesPort;

void main() {
  testWidgets('sign-in calls existing seam; forbidden copies safe diagnosis', (
    tester,
  ) async {
    const privateTradeNumber = 'SYNTHETIC_PRIVATE_TRADE_DIAGNOSTIC_42';
    final port = TradesPort();
    port.row['transactionNumber'] = privateTradeNumber;
    final c = MarketplaceController(port);
    c.trades.rows = [Map<String, Object?>.from(port.row)];
    c.trades.detail = Map<String, Object?>.from(port.row);
    int logins = 0;
    c.login = (_) async {
      logins++;
    };
    c.trades.errorCode = 'marketplace.sign_in_required';
    c.trades.error = '请先登录 SCM，再打开我的交易。';
    await tester.pumpWidget(
      preview(TradeFailure(c, retry: () {}), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 SCM'));
    expect(logins, 1);
    c.trades.errorCode = 'marketplace.forbidden';
    c.trades.error = '交易功能暂时不可用，请稍后再试；一直这样请联系支持';
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      preview(TradeFailure(c, retry: () {}), AppearanceMode.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();
    expect(clipboard, contains('code=403'));
    expect(clipboard, isNot(contains(privateTradeNumber)));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  testWidgets('trade steps and countdown expose whole meanings', (
    tester,
  ) async {
    final p = TradesPort(), c = MarketplaceController(TradesPort());
    final semantics = tester.ensureSemantics();
    c.trades.detail = {
      ...p.row,
      'actorRole': 'buyer',
      'deliveryStatus': 2,
      'receiptDeadline': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 19, minutes: 29))
          .toIso8601String(),
    };
    await tester.pumpWidget(preview(TradeSheet(c), AppearanceMode.dark));
    await tester.pump();
    expect(find.bySemanticsLabel('第 3 步，共 5 步，已发货'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('待我收货，剩余 19 小时')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    semantics.dispose();
  });
  testWidgets(
    'confirmation focuses first enabled control and restores trigger',
    (tester) async {
      final c = MarketplaceController(TradesPort());
      final trigger = FocusNode();
      await tester.pumpWidget(
        preview(
          Builder(
            builder: (context) => TextButton(
              focusNode: trigger,
              onPressed: () => confirmMarketTrade(context, c, {
                'availableQuantity': 1,
                'locationId': 1,
                'creatorType': 1,
                'unitPrice': 1,
              }),
              child: const Text('打开确认'),
            ),
          ),
          AppearanceMode.dark,
        ),
      );
      trigger.requestFocus();
      await tester.pump();
      await tester.tap(find.text('打开确认'));
      await tester.pumpAndSettle();
      expect(trigger.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(trigger.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      trigger.dispose();
      c.dispose();
    },
  );
}
