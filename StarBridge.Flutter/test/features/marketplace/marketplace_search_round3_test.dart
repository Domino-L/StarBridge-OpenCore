import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_search.dart';

import 'marketplace_test.dart' show FixturePort, app;

class TimedSearchPort extends FixturePort {
  final prices = <int>[];
  final searches = <String>[];
  Completer<MarketRead>? delayedPrice;
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
    if (operation == 'search') {
      searches.add(keyword);
      return MarketRead({
        'rows': [
          {
            'id': 43483,
            'itemName': '科力晶（单个矿块）',
            'sellOrderCount': 3,
            'buyOrderCount': 0,
          },
          {
            'id': 43484,
            'itemName': '科力晶（纯·单个矿块）',
            'sellOrderCount': 0,
            'buyOrderCount': 0,
          },
        ],
      }, DateTime.now());
    }
    if (operation == 'offers') {
      prices.add(id);
      return delayedPrice?.future ??
          Future.value(
            MarketRead({
              'rows': [
                {'unitPrice': 1200000},
              ],
            }, DateTime.now()),
          );
    }
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
  }
}

void main() {
  test('keywords strip real specifications and deduplicate', () {
    expect(
      marketSearchTerms(
        [
          {'itemName': '科力晶（单个矿块）'},
          {'itemName': '科力晶（纯·单个矿块）'},
        ],
        '科',
        'zh',
      ),
      ['科力晶'],
    );
  });
  testWidgets(
    'debounced first-only price ignores obsolete response and Tab completes keyword',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = TimedSearchPort();
      final c = MarketplaceController(port);
      await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('marketplace-search'));
      await tester.enterText(field, '科');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field, '科力');
      await tester.pump(const Duration(milliseconds: 249));
      expect(port.searches, isEmpty);
      expect(port.prices, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(port.searches, ['科力']);
      expect(port.prices, isEmpty);
      port.delayedPrice = Completer<MarketRead>();
      await tester.pump(const Duration(milliseconds: 200));
      expect(port.prices, [43483]);
      await tester.enterText(field, '科');
      port.delayedPrice!.complete(
        MarketRead({
          'rows': [
            {'unitPrice': 999},
          ],
        }, DateTime.now()),
      );
      await tester.pump();
      expect(find.text('999'), findsNothing);
      port.delayedPrice = null;
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(port.prices, [43483, 43483]);
      expect(find.text('1,200,000'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '科力晶');
      expect(c.hasItem, isFalse);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.mainTab, 1);
      expect(c.browser.keyword, '科力晶');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('IME Tab does not complete or request price', (tester) async {
    final port = TimedSearchPort();
    final c = MarketplaceController(port);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('marketplace-search'));
    await tester.tap(field);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '科',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '科');
    expect(port.prices, isEmpty);
    expect(port.searches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
