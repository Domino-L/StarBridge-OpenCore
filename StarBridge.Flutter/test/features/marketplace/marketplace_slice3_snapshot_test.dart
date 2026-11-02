import 'package:starbridge_flutter/features/marketplace/marketplace_trade_copy.dart';

// Visual regression fixtures only. These are NOT real-account acceptance evidence.
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'marketplace_trades_test.dart' show TradesPort;

class VisualTradesPort extends TradesPort {
  final fixtures = <MarketRow>[
    for (final entry in [
      (1, 'seller', 1),
      (2, 'buyer', 1),
      (3, 'buyer', 1),
      (0, 'seller', 0),
      (3, 'seller', 1),
      (4, 'buyer', 1),
    ])
      {
        'transactionNumber': 'VISUAL-${entry.$1}-${entry.$2}',
        'itemsName': '科力晶（单个矿块）',
        'itemsNameHant': '科力晶（單個礦塊）',
        'number': 2,
        'amount': 1200000,
        'displayType': 1,
        'qualityData': {'type': 'material', 'quality': 880},
        'actorRole': entry.$2,
        'creatorType': entry.$3,
        'deliveryStatus': entry.$1,
        'transactionStatus': entry.$1 == 3
            ? 2
            : entry.$1 == 4
            ? 3
            : 1,
        'counterpartyName': '视觉回归样例',
        'transactionLocationName': '炽天使空间站',
        'deliveryMethod': 0,
        'shippingFee': 0,
        'createTime': '2026-10-16 10:00',
        if (entry.$1 == 2) 'receiptDeadline': '2026-10-18 10:00',
        if (entry.$1 == 3 && entry.$2 == 'seller') ...{
          'sellerCommentId': 1,
          'sellerRating': 5,
          'sellerContent': '按约定交付。',
          'buyerRating': 5,
          'buyerContent': '交易顺利。',
        },
        'canReport': entry.$1 == 3,
      },
  ];
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) async {
    if (op == 'list') {
      reads++;
      return {'rows': fixtures, 'total': fixtures.length};
    }
    if (op == 'detail') {
      return fixtures.firstWhere(
        (r) => r['transactionNumber'] == input['transactionNumber'],
      );
    }
    return super.trade(op, input);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('MARKET_SLICE3_SNAPSHOT')) return;
  setUpAll(() async {
    // Widget raster tests do not discover Windows font fallbacks automatically.
    // Read the installed font in place; never copy licensed system fonts into the repo.
    final traditionalFont = File('C:/Windows/Fonts/msjh.ttc');
    if (Platform.isWindows && await traditionalFont.exists()) {
      await (FontLoader('Microsoft JhengHei UI')
            ..addFont(traditionalFont.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
    for (final p in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Microsoft YaHei UI', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Han Sans TC', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      await (FontLoader(p.$1)..addFont(rootBundle.load(p.$2))).load();
    }
  });
  for (final locale in ['cn', 'hant', 'en']) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('slice 3 visual fixtures $locale ${mode.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = InMemoryAppPreferences();
        await prefs.setAppearanceMode(mode);
        await prefs.setLocale(
          locale == 'en'
              ? const Locale('en')
              : Locale('zh', locale == 'hant' ? 'TW' : 'CN'),
        );
        final port = VisualTradesPort();
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
            key: const Key('trade-window'),
            child: StarBridgeApp(composition: composition),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        final c = tester
            .widget<MarketplacePage>(find.byType(MarketplacePage))
            .controller;
        Future<void> shot(String name) async {
          if (c.trades.pending) {
            await tester.pump(const Duration(milliseconds: 100));
          } else {
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('trade-window')),
          );
          await tester.runAsync(() async {
            final pic = await boundary.toImage();
            final data = await pic.toByteData(format: ui.ImageByteFormat.png);
            const out =
                '../.artifacts/trading-hall-intake-20261015/slice3-round3/renders';
            await Directory(out).create(recursive: true);
            await File(
              '$out/${locale == 'cn' ? '' : '$locale-'}$name-${mode.name}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            pic.dispose();
          });
        }

        await shot('hall-1280');
        final todoLabel = find.widgetWithText(
          TextButton,
          '${tradeTextFor(locale, 'todoShort')} 3',
        );
        expect(todoLabel, findsOneWidget);
        expect(
          (tester.getCenter(todoLabel).dy -
                  tester.getCenter(find.byType(TextField).first).dy)
              .abs(),
          lessThan(8),
        );
        c.tab(3);
        await shot('trades-1280');
        final beforeRefresh = port.reads;
        await tester.tap(
          find.byTooltip(
            locale == 'en'
                ? 'Refresh'
                : locale == 'hant'
                ? '重新整理'
                : '刷新',
          ),
        );
        await tester.pumpAndSettle();
        expect(port.reads, beforeRefresh + 1);

        final ctx = Navigator.of(tester.element(find.byType(MarketplacePage)))
            .overlay!
            .context;
        for (var i = 0; i < port.fixtures.length; i++) {
          final r = port.fixtures[i];
          showTrade(ctx, c, r);
          await shot('txn-$i-1280');
          if (i < 3) {
            final act = ['ship', 'receive', 'review'][i];
            tradeDialog(ctx, c, act, r);
            if (act == 'ship' || act == 'receive') {
              await tester.pumpAndSettle();
              final primary = find
                  .widgetWithText(
                    FilledButton,
                    tradeTextFor(locale, act == 'ship' ? '确认发货' : '确认收货'),
                  )
                  .last;
              expect(tester.widget<FilledButton>(primary).onPressed, isNull);
              await tester.tap(find.byType(CheckboxListTile).last);
              await tester.pumpAndSettle();
              expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
            }
            await shot('dlg-$act-1280');
            final dialog = tester.widget<Dialog>(find.byType(Dialog).last);
            expect(dialog.shape, isA<RoundedRectangleBorder>());
            expect(tester.getSize(find.byWidget(dialog.child!)).width, 460);
            final cancel = find
                .widgetWithText(OutlinedButton, tradeTextFor(locale, '取消'))
                .last;
            expect(tester.getSize(cancel).height, greaterThanOrEqualTo(40));
            await tester.tap(
              find
                  .widgetWithText(OutlinedButton, tradeTextFor(locale, '取消'))
                  .last,
            );
            await tester.pumpAndSettle();
          }
          Navigator.of(ctx, rootNavigator: true).pop();
          await tester.pumpAndSettle();
        }
        for (final act in ['cancel', 'report', 'approve', 'block']) {
          tradeDialog(ctx, c, act, port.fixtures.first);
          await shot('dlg-$act-1280');
          if (act == 'report') {
            expect(find.byType(ChoiceChip), findsNWidgets(4));
            expect(
              tester
                  .widgetList<ChoiceChip>(find.byType(ChoiceChip))
                  .every((chip) => !chip.selected),
              isTrue,
            );
            expect(
              find.text(tradeTextFor(locale, 'reportTypeRequired')),
              findsNothing,
            );
            final writes = port.writes;
            await tester.tap(
              find.widgetWithText(FilledButton, tradeTextFor(locale, '提交举报')),
            );
            await tester.pumpAndSettle();
            expect(port.writes, writes);
            expect(
              find.text(tradeTextFor(locale, 'reportTypeRequired')),
              findsOneWidget,
            );
            expect(
              find.text(tradeTextFor(locale, 'reportTextRequired')),
              findsOneWidget,
            );
            await shot('dlg-report-invalid-1280');
            await tester.tap(find.byType(ChoiceChip).first);
            await tester.enterText(
              find.byType(TextField).last,
              'Visual regression only',
            );
            await tester.pumpAndSettle();
            expect(
              find.text(tradeTextFor(locale, 'reportTypeRequired')),
              findsNothing,
            );
            expect(
              find.text(tradeTextFor(locale, 'reportTextRequired')),
              findsNothing,
            );
            await shot('dlg-report-filled-1280');
          }
          final dialog = tester.widget<Dialog>(find.byType(Dialog).last);
          expect(dialog.shape, isA<RoundedRectangleBorder>());
          expect(tester.getSize(find.byWidget(dialog.child!)).width, 460);
          final cancel = find
              .widgetWithText(OutlinedButton, tradeTextFor(locale, '取消'))
              .last;
          expect(tester.getSize(cancel).height, greaterThanOrEqualTo(40));
          await tester.tap(
            find
                .widgetWithText(OutlinedButton, tradeTextFor(locale, '取消'))
                .last,
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(tradeTextFor(locale, '已结束')).first);
        await shot('trades-history-1280');
        await tester.tap(
          find.textContaining(tradeTextFor(locale, '进行中')).first,
        );
        confirmMarketTrade(ctx, c, {
          'orderNumber': 'VISUAL-O1',
          'itemName': '科力晶（单个矿块）',
          'itemNameHant': '科力晶（單個礦塊）',
          'availableQuantity': 24,
          'unitPrice': 1200000,
          'creatorType': 1,
          'locationId': 1,
        });
        await shot('confirm-1280');
        port.writeGate = Completer();
        await tester.tap(find.text(tradeTextFor(locale, '确认发起')));
        await shot('confirm-submitting-1280');
        port.writeGate!.completeError(
          const MarketplaceTradeError('marketplace.trade_rejected'),
        );
        await shot('confirm-failed-1280');
        port.writeGate = Completer();
        await tester.tap(
          find.widgetWithText(FilledButton, tradeTextFor(locale, '重试')),
        );
        port.writeGate!.complete({
          'transactionNumber': port.fixtures.first['transactionNumber'],
        });
        await tester.pumpAndSettle();
        await shot('toast-1280');
        final toast = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(toast.behavior, SnackBarBehavior.floating);
        expect(toast.width, 560);

        tester.view.physicalSize = const Size(900, 800);
        await shot('toast-900');
        await shot('trades-900');
        showTrade(ctx, c, port.fixtures.first);
        await shot('txn-900');
        Navigator.of(ctx, rootNavigator: true).pop();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
