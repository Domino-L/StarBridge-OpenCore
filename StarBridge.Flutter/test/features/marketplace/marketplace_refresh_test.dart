import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

class RefreshPort extends FixturePort {
  bool fail = false;
  Completer<void>? refreshGate;
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
    await refreshGate?.future;
    if (fail) throw StateError('refresh failed');
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
    );
  }
}

void main() {
  testWidgets(
    'TH-01 failed hall refresh keeps the last categories and trending',
    (tester) async {
      final port = RefreshPort();
      final c = MarketplaceController(port);
      await tester.pumpWidget(
        app(c, AppearanceMode.dark, const Locale('en', 'US')),
      );
      await tester.pumpAndSettle();
      final previous = c.blocks['categories'];
      expect(find.text('Category 1'), findsOneWidget);
      port.fail = true;
      await c.refreshHall();
      await tester.pumpAndSettle();
      expect(identical(c.blocks['categories'], previous), isTrue);
      expect(find.text('Category 1'), findsOneWidget);
      expect(
        find.text('Refresh failed. Showing the previous snapshot.'),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  for (final pending in [false, true]) {
    testWidgets(
      'TH-01 item refresh ${pending ? 'pending' : 'failed'} retains visible quotes',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = RefreshPort();
        final c = MarketplaceController(port);
        await tester.pumpWidget(
          app(c, AppearanceMode.dark, const Locale('en', 'US')),
        );
        await tester.pumpAndSettle();
        await c.openItem(1);
        await tester.pumpAndSettle();
        expect(find.text('Trader 0'), findsOneWidget);
        if (pending) {
          port.refreshGate = Completer<void>();
        } else {
          port.fail = true;
        }
        await tester.tap(find.byKey(const Key('market-item-refresh')));
        await tester.pumpAndSettle();
        expect(find.text('Trader 0'), findsOneWidget);
        if (pending) {
          port.refreshGate!.complete();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
