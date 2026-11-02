// Batch 3: multi-select batch bar (17), sort/page/load more (18),
// drag reorder (21), long list entrance and scrollbar (22).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

/// Scope *below* MaterialApp on purpose: overlay content (drag proxies)
/// must still work when the scope does not cover the overlay.
Widget _host(InteractionSuite suite, Widget child) => MaterialApp(
  home: Scaffold(
    body: InteractionScope(
      data: InteractionData(suite: suite, palette: palette),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ),
);

void main() {
  group('17 batch', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: bar appears for a selection, count updates in place, hides at 0', (t) async {
        var count = 0;
        late StateSetter set;
        await t.pumpWidget(
          _host(
            suite,
            SizedBox(
              width: 360,
              height: 60,
              child: StatefulBuilder(
                builder: (context, s) {
                  set = s;
                  return SuiteBatchBar(count: count, actions: const [], onClear: () => s(() => count = 0));
                },
              ),
            ),
          ),
        );
        expect(find.text('已选择'), findsNothing);
        set(() => count = 2);
        await t.pumpAndSettle();
        expect(find.text('已选择'), findsOneWidget);
        set(() => count = 5);
        await t.pumpAndSettle();
        expect(find.text('5'), findsOneWidget);
        await t.tap(find.byIcon(Icons.close));
        await t.pumpAndSettle();
        expect(find.text('已选择'), findsNothing);
      });
    }

    testWidgets('externally changed checkboxes switch at once (no per-box effects)', (t) async {
      var all = false;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return Column(
                children: [
                  for (var i = 0; i < 6; i++) SuiteCheckbox(value: all, onChanged: (_) {}),
                ],
              );
            },
          ),
        ),
      );
      set(() => all = true);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('a direct click on a checkbox still plays its effect', (t) async {
      var v = false;
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          StatefulBuilder(builder: (context, s) => SuiteCheckbox(value: v, onChanged: (n) => s(() => v = n!))),
        ),
      );
      await t.tap(find.byType(SuiteCheckbox));
      await t.pump();
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
    });
  });

  group('18 sort, page, load more', () {
    testWidgets('sort header announces direction and reports taps', (t) async {
      var dir = SortDirection.none;
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, s) => SuiteSortHeader(
              label: 'Ships',
              direction: dir,
              onTap: () => s(() => dir = dir == SortDirection.ascending ? SortDirection.descending : SortDirection.ascending),
            ),
          ),
        ),
      );
      await t.tap(find.text('Ships'));
      await t.pumpAndSettle();
      expect(dir, SortDirection.ascending);
      expect(t.getSemantics(find.byType(SuiteSortHeader)).label, 'Ships，升序');
      await t.tap(find.text('Ships'));
      await t.pumpAndSettle();
      expect(t.getSemantics(find.byType(SuiteSortHeader)).label, 'Ships，降序');
      semantics.dispose();
    });

    testWidgets('pager disables prev/next at the ends', (t) async {
      var page = 0;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) => SuitePager(page: page, pageCount: 3, onChanged: (p, _) => s(() => page = p)),
          ),
        ),
      );
      await t.tap(find.byIcon(Icons.chevron_left), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(page, 0);
      await t.tap(find.text('3'));
      await t.pumpAndSettle();
      expect(page, 2);
      await t.tap(find.byIcon(Icons.chevron_right), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(page, 2);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(page, 1);
    });

    testWidgets('load more states say what is happening', (t) async {
      for (final (phase, text) in [
        (LoadMorePhase.idle, '加载更多'),
        (LoadMorePhase.loading, '正在加载更多…'),
        (LoadMorePhase.failed, '重试'),
        (LoadMorePhase.end, '已经到底了'),
      ]) {
        await t.pumpWidget(_host(InteractionSuite.rail, SizedBox(width: 300, child: SuiteLoadMore(phase: phase, onLoad: () {}))));
        expect(find.text(text), findsOneWidget, reason: '$phase');
      }
    });
  });

  group('22 long list', () {
    testWidgets('only new rows animate; rebuilds and recycling never replay', (t) async {
      var fresh = false;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteAppear(key: const ValueKey('row'), animate: fresh, child: const Text('row'));
            },
          ),
        ),
      );
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      // A rebuild that flips the flag does not replay an entrance either.
      set(() => fresh = true);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      // A newly mounted fresh row does animate once, then settles.
      await t.pumpWidget(_host(InteractionSuite.rail, const SuiteAppear(key: ValueKey('new'), child: Text('new'))));
      await t.pump();
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: scrollbar wraps a long list', (t) async {
        final c = ScrollController();
        addTearDown(c.dispose);
        await t.pumpWidget(
          _host(
            suite,
            SizedBox(
              height: 200,
              width: 200,
              child: SuiteScrollbar(
                controller: c,
                child: ListView.builder(controller: c, itemCount: 300, itemBuilder: (_, i) => SizedBox(height: 30, child: Text('$i'))),
              ),
            ),
          ),
        );
        c.jumpTo(3000);
        await t.pumpAndSettle();
        expect(find.text('100'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('21 reorder', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: drag proxy works even when the overlay is outside the scope', (t) async {
        final items = ['a', 'b', 'c'];
        await t.pumpWidget(
          _host(
            suite,
            SizedBox(
              width: 240,
              height: 200,
              child: StatefulBuilder(
                builder: (context, s) => ReorderableListView(
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, i, a) => suiteReorderProxy(context, child, a),
                  onReorderItem: (from, to) => s(() => items.insert(to, items.removeAt(from))),
                  children: [
                    for (var i = 0; i < items.length; i++)
                      ReorderableDragStartListener(
                        key: ValueKey(items[i]),
                        index: i,
                        child: SizedBox(height: 40, child: Text(items[i])),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        final g = await t.startGesture(t.getCenter(find.text('a')));
        await t.pump(const Duration(milliseconds: 50));
        for (var i = 0; i < 10; i++) {
          await g.moveBy(const Offset(0, 9));
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(t.takeException(), isNull);
        await g.up();
        await t.pumpAndSettle();
        expect(items.first, isNot('a'));
      });
    }

    testWidgets('Alt+arrows are just shortcuts the caller binds (no animation needed)', (t) async {
      // Documented pattern: rows use CallbackShortcuts for Alt+↑/↓ and the
      // list updates at once; the moved row then flashes via flashToken.
      var token = 0;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) => CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => s(() => token++)},
              child: SuitePressable(kind: PressableKind.row, autofocus: true, flashToken: token, onPressed: () {}, child: const Text('row')),
            ),
          ),
        ),
      );
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(token, 1);
    });
  });
}
