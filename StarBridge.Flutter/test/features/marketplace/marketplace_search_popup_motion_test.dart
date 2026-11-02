// Search popup: its buttons (recent tags, clear, popular searches, retry,
// complete-keyword) join the shared actions. The popup content excludes
// focus, so pointer and reader activation never take focus from the field,
// which keeps the arrow keys and closes the popup when it loses focus — the
// same as the native buttons, which never took focus either. Native geometry
// and text style measured before the change are pinned for the standard
// suite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_search.dart';

import 'marketplace_search_round3_test.dart' show TimedSearchPort;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class _HotPort extends TimedSearchPort {
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
  }) {
    if (operation == 'hotWords') {
      return Future.value(
        MarketRead({
          'rows': [
            {'itemName': '科力晶'},
            {'itemName': '婆娑罗'},
          ],
        }, DateTime.utc(2026, 10, 20)),
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

final _field = find.byKey(const Key('marketplace-search'));

Future<(MarketplaceController, TextEditingController, FocusNode)> _search(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(_HotPort());
  await c.rememberSearch('科力晶');
  final text = TextEditingController();
  final focus = FocusNode();
  await tester.pumpWidget(
    scopedApp(
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 600, child: MarketplaceSearch(c, text, focus)),
      ),
      suite,
    ),
  );
  await tester.pumpAndSettle();
  focus.requestFocus();
  await tester.pumpAndSettle();
  return (c, text, focus);
}

Future<void> _end(
  WidgetTester tester,
  (MarketplaceController, TextEditingController, FocusNode) s,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  s.$1.dispose();
  s.$2.dispose();
  s.$3.dispose();
}

void _activate(WidgetTester tester, String prefix) => activate(
  tester,
  exposedNodes(tester).firstWhere((n) {
    final d = n.getSemanticsData();
    return d.label.startsWith(prefix) && d.flagsCollection.isButton;
  }),
);

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    var s = await _search(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(
          find.byKey(
            const ValueKey<(String, String)>(('market-search-clear', '最近搜索')),
          ),
        ),
        const Rect.fromLTRB(880, 66, 928, 114),
      );
      expect(
        tester.getRect(
          find.byKey(
            const ValueKey<(String, String)>(('market-search-tag', '科力晶')),
          ),
        ),
        const Rect.fromLTRB(352, 114, 408, 142),
      );
      expect(
        tester.getRect(
          find.byKey(const ValueKey<(String, int)>(('market-search-hot', 0))),
        ),
        const Rect.fromLTRB(352, 186, 640, 234),
      );
      await tester.enterText(_field, '科');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(
          find.byKey(const ValueKey<(String, int)>(('market-search-fill', 0))),
        ),
        const Rect.fromLTRB(872, 60, 920, 108),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _end(tester, s);
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: popup controls keep focus in the field', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final s = await _search(tester, suite);
      final (c, text, focus) = s;
      try {
        await tester.tap(
          find.byKey(
            const ValueKey<(String, String)>(('market-search-tag', '科力晶')),
          ),
        );
        await tester.pumpAndSettle();
        expect(text.text, '科力晶');
        expect(
          focus.hasFocus,
          isTrue,
          reason: 'Pointer keeps the field focused.',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<(String, int)>(('market-search-fill', 0))),
        );
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(text.text, '科力晶');
        text.clear();
        await tester.pumpAndSettle();
        _activate(tester, '清空');
        await tester.pumpAndSettle();
        expect(c.recentSearches, isEmpty);
        expect(
          focus.hasFocus,
          isTrue,
          reason: 'Reader keeps the field focused.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _end(tester, s);
      }
    });

    testWidgets('${suite.name}: a popular search opens the market', (
      tester,
    ) async {
      final s = await _search(tester, suite);
      final (c, _, focus) = s;
      try {
        await tester.tap(
          find.byKey(const ValueKey<(String, int)>(('market-search-hot', 1))),
        );
        await tester.pumpAndSettle();
        expect(c.browser.keyword, '婆娑罗');
        expect(
          focus.hasFocus,
          isFalse,
          reason: 'Going to the market closes search.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _end(tester, s);
      }
    });
  }
}
