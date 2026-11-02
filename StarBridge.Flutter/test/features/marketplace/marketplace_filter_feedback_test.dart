// User 10-29 (via 调度): filter chips name the item or category, never an id
// ("兼容配件 #43475 这一串数字也看不懂"), long names are cut with the full name
// on hover and for readers; a filter click answers at once — the old rows stay
// dimmed, "正在加载…" after a second, and after ten the wait can be cancelled.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

const _long = 'NDB-30 中子速射炮 · 军规级强化型号 限定涂装版';

/// Item 3 carries a name too long for a chip.
class _LongNamePort extends FixturePort {
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
    final read = await super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
    if (operation != 'item' || id != 3) return read;
    return MarketRead({...read.data, 'itemName': _long}, read.readAt);
  }
}

/// Records the side of every saved hall view.
class _SavedViewPort extends FixturePort {
  final savedSides = <int>[];
  @override
  Future<MarketRow> preferences([MarketRow? value]) {
    if (value?['view'] case {'side': final int side}) savedSides.add(side);
    return super.preferences(value);
  }
}

Future<MarketplaceController> _hall(
  WidgetTester tester, [
  FixturePort? port,
]) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = MarketplaceController(port ?? FixturePort());
  await tester.pumpWidget(
    app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
  );
  await tester.pumpAndSettle();
  return c;
}

final _filters = find.byKey(const Key('market-catalog-filters'));
final _status = find.byKey(const Key('market-refilter-status'));

void main() {
  testWidgets('related catalog chip names the item, never its id', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      await c.openItem(2);
      await tester.pumpAndSettle();
      await c.related('attachments', 2);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _filters, matching: find.text('兼容：测试物品 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _filters, matching: find.textContaining('#')),
        findsNothing,
      );
      await c.browse(category: 3);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _filters, matching: find.text('分类：分类 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _filters, matching: find.textContaining('#')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('a long name is cut, with the full name on hover and for readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final c = await _hall(tester, _LongNamePort());
    try {
      await c.openItem(3);
      await tester.pumpAndSettle();
      await c.related('attachments', 3);
      await tester.pumpAndSettle();
      final chip = find.descendant(
        of: _filters,
        matching: find.textContaining('兼容：NDB-30'),
      );
      expect(chip, findsOneWidget);
      final shown = tester.widget<Text>(chip).data!;
      expect(shown.endsWith('…'), isTrue);
      expect(shown.length, lessThan('兼容：$_long'.length));
      expect(
        find.descendant(
          of: _filters,
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == '兼容：$_long',
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('兼容：$_long'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      semantics.dispose();
    }
  });

  testWidgets('a restored related catalog reads its item name once', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      // As after a restart: the catalog is restored without the item read.
      c.relation = 'attachments';
      c.relatedId = 5;
      await c.refreshCatalog();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _filters, matching: find.text('兼容：测试物品 5')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('a filter click answers at once; slow waits can be cancelled', (
    tester,
  ) async {
    final port = FixturePort();
    final c = await _hall(tester, port);
    try {
      final before = c.blocks['latest'];
      expect(before, isNotNull);
      port.readGate = Completer<void>();
      unawaited(c.toggleSide(2));
      await tester.pump();
      // The choice shows at once; the old rows stay (dimmed), no blank page.
      expect(c.side, 2);
      expect(c.refiltering, contains('latest'));
      expect(identical(c.blocks['latest'], before), isTrue);
      expect(_status, findsNothing, reason: 'nothing extra under a second');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('正在加载…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('已等待'), findsOneWidget);
      await tester.tap(find.byKey(const Key('market-refilter-cancel')));
      await tester.pump();
      expect(c.side, 1, reason: 'cancelling puts the previous filter back');
      expect(c.refiltering, isEmpty);
      expect(_status, findsNothing);
      // The late answer for the cancelled filter is ignored.
      port.readGate!.complete();
      port.readGate = null;
      await tester.pumpAndSettle();
      expect(c.side, 1);
      expect(identical(c.blocks['latest'], before), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  // Build 44: the saved side 3 failed in the Host's preference store and that
  // failure ended the whole session (signed out, back home, reconnecting).
  testWidgets('clearing the filter shows every type but never saves side 3', (
    tester,
  ) async {
    final port = _SavedViewPort();
    final c = await _hall(tester, port);
    try {
      await c.toggleSide(1);
      await tester.pumpAndSettle();
      expect(c.side, MarketplaceController.allSides);
      expect(port.savedSides, isNotEmpty);
      expect(port.savedSides.last, 1, reason: 'older builds cannot read side 3');
      expect(port.savedSides, isNot(contains(MarketplaceController.allSides)));
      await c.toggleSide(2);
      await tester.pumpAndSettle();
      expect(c.side, 2);
      expect(port.savedSides.last, 2);
      expect(c.preferencesFailed, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('a quick answer replaces the rows without any wait notice', (
    tester,
  ) async {
    final port = FixturePort();
    final c = await _hall(tester, port);
    try {
      await c.openItem(1);
      await tester.pumpAndSettle();
      final before = c.blocks['sell'];
      port.readGate = Completer<void>();
      unawaited(c.setOfferFilter('creatorStatus', '2'));
      await tester.pump();
      expect(c.offerFilters['creatorStatus'], '2');
      expect(c.refiltering, containsAll(['sell', 'buy']));
      expect(identical(c.blocks['sell'], before), isTrue);
      port.readGate!.complete();
      port.readGate = null;
      await tester.pumpAndSettle();
      expect(c.refiltering, isEmpty);
      expect(identical(c.blocks['sell'], before), isFalse);
      expect(_status, findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });
}
