// Probes from the 2026-10-08 motion re-audit (F01–F07): lifecycle seams
// where effects meet real data, live settings, keyboard input and screen
// readers.
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _animated = [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow];

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Scope placed under the navigator (as in the lab's scenario page), driven
/// by [data] so a test can change it while a surface is open.
Widget _innerHost(ValueNotifier<InteractionData> data, Widget child) => MaterialApp(
  home: ValueListenableBuilder(
    valueListenable: data,
    builder: (context, d, _) => InteractionScope(
      data: d,
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  group('F01 chips: remove then restore', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: one node per id, no duplicate keys, usable after restore', (t) async {
        var ids = ['运输', '探索', '工业'];
        final toggled = <String>[];
        late StateSetter set;
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuiteChipGroup(
                  chips: [for (final id in ids) SuiteChipData(id: id, label: id, removable: true)],
                  onToggle: toggled.add,
                  onRemove: (id) => s(() => ids = ids.where((x) => x != id).toList()),
                );
              },
            ),
          ),
        );
        set(() => ids = ['运输', '工业']);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        set(() => ids = ['运输', '探索', '工业']);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.takeException(), isNull);
        expect(find.text('探索'), findsOneWidget);
        // Remove again mid-restore, then restore once more and let it settle.
        set(() => ids = ['运输', '工业']);
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        set(() => ids = ['运输', '探索', '工业']);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('探索'), findsOneWidget);
        await t.tap(find.text('探索'));
        await t.pump();
        expect(toggled, ['探索']);
        // Settled: the restored chip has full width (not stuck mid-exit).
        expect(t.getSize(find.text('探索')).width, greaterThan(10));
      });
    }

    testWidgets('a stale exit completion never removes the restored chip', (t) async {
      var ids = ['A', 'B'];
      late StateSetter set;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteChipGroup(
                chips: [for (final id in ids) SuiteChipData(id: id, label: id)],
                onToggle: (_) {},
              );
            },
          ),
        ),
      );
      set(() => ids = ['B']);
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      set(() => ids = ['A', 'B']);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('F02 surfaces follow live settings', () {
    testWidgets('a dialog opened under an inner scope follows suite changes', (t) async {
      final data = ValueNotifier(InteractionData(suite: InteractionSuite.rail, palette: palette));
      addTearDown(data.dispose);
      InteractionData? seen;
      await t.pumpWidget(
        _innerHost(
          data,
          Builder(
            builder: (context) => GestureDetector(onTap: () => showSuiteDialog<void>(
                context,
                (ctx) => Builder(
                  builder: (ctx) {
                    seen = InteractionScope.of(ctx);
                    return const Text('dialog');
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(seen!.suite, InteractionSuite.rail);
      data.value = data.value.copyWith(suite: InteractionSuite.glow);
      await t.pump();
      await t.pump();
      expect(seen!.suite, InteractionSuite.glow);
    });

    for (final suite in _animated) {
      testWidgets('${suite.name}: reduced motion mid-entrance settles an open dialog', (t) async {
        final data = ValueNotifier(InteractionData(suite: suite, palette: palette));
        addTearDown(data.dispose);
        await t.pumpWidget(
          _innerHost(
            data,
            Builder(
              builder: (context) => GestureDetector(onTap: () => showSuiteDialog<void>(context, (ctx) => const Text('dialog')),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.hasRunningAnimations, isTrue);
        data.value = data.value.copyWith(reduceMotion: true);
        await t.pump();
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(find.text('dialog'), findsOneWidget);
      });

      testWidgets('${suite.name}: reduced motion mid-entrance settles an open context menu', (t) async {
        final data = ValueNotifier(InteractionData(suite: suite, palette: palette));
        addTearDown(data.dispose);
        await t.pumpWidget(
          _innerHost(
            data,
            Builder(
              builder: (context) => GestureDetector(onTap: () => showSuiteContextMenu(
                  context,
                  position: const Offset(100, 100),
                  actions: [SuiteMenuAction(label: '加入', onSelected: () {})],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(t.hasRunningAnimations, isTrue);
        data.value = data.value.copyWith(reduceMotion: true);
        await t.pump();
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(find.text('加入'), findsOneWidget);
      });
    }

    testWidgets('closing the menu releases its relay subscription', (t) async {
      final data = ValueNotifier(InteractionData(suite: InteractionSuite.scan, palette: palette));
      addTearDown(data.dispose);
      late BuildContext origin;
      await t.pumpWidget(
        _innerHost(
          data,
          Builder(
            builder: (context) {
              origin = context;
              return GestureDetector(onTap: () => showSuiteContextMenu(
                  context,
                  position: const Offset(100, 100),
                  actions: [SuiteMenuAction(label: '加入', onSelected: () {})],
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      );
      expect(InteractionScope.linkOf(origin), isNotNull);
      expect(InteractionScope.debugLiveLinks, 0);
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(InteractionScope.debugLiveLinks, 1);
      await t.tapAt(const Offset(700, 500));
      await t.pumpAndSettle();
      expect(find.text('加入'), findsNothing);
      expect(InteractionScope.debugLiveLinks, 0);
    });
  });

  group('F03 screen reader activation', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: favourite toggle and sort header expose one tap action', (t) async {
        final handle = t.ensureSemantics();
        var fav = false;
        var taps = 0;
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, s) => Column(
                children: [
                  SuiteIconToggle(
                    value: fav,
                    offIcon: Icons.star_border,
                    onIcon: Icons.star,
                    semanticLabel: '收藏',
                    onChanged: (v) => s(() => fav = v),
                  ),
                  SuiteSortHeader(label: '尺寸', direction: SortDirection.none, onTap: () => taps++),
                  const SuiteIconToggle(
                    value: false,
                    offIcon: Icons.push_pin_outlined,
                    onIcon: Icons.push_pin,
                    semanticLabel: '置顶',
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        );
        final favNode = t.getSemantics(find.byType(SuiteIconToggle).first);
        expect(favNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(favNode.getSemanticsData().flagsCollection.isButton, isTrue);
        t.semantics.tap(find.semantics.byLabel('收藏'));
        await t.pump();
        expect(fav, isTrue);
        t.semantics.tap(find.semantics.byLabel('尺寸'));
        await t.pump();
        expect(taps, 1);
        final pinNode = t.getSemantics(find.byType(SuiteIconToggle).last);
        expect(pinNode.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        handle.dispose();
      });
    }
  });

  group('F04 drawer keeps its content through the exit', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: closing shows the old detail until the panel is gone', (t) async {
        String? ship = 'C2 大力神';
        late StateSetter set;
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuiteDrawer(
                  open: ship != null,
                  onClose: () => s(() => ship = null),
                  child: ship == null ? const SizedBox.shrink() : Center(child: Text(ship!)),
                );
              },
            ),
          ),
        );
        // Pointer close (caller clears its selection immediately).
        set(() => ship = null);
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        expect(find.text('C2 大力神'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 60));
        expect(find.text('C2 大力神'), findsOneWidget);
        // Reopen another ship mid-exit: the new content shows.
        set(() => ship = '北极星');
        await t.pump();
        expect(find.text('北极星'), findsOneWidget);
        expect(find.text('C2 大力神'), findsNothing);
        set(() => ship = null);
        await t.pumpAndSettle();
        expect(find.text('北极星'), findsNothing);
      });
    }

    testWidgets('the exiting panel takes no taps', (t) async {
      var open = true;
      var hits = 0;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteDrawer(
                open: open,
                onClose: () => s(() => open = false),
                child: Center(child: TextButton(onPressed: () => hits++, child: const Text('act'))),
              );
            },
          ),
        ),
      );
      set(() => open = false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      await t.tap(find.text('act'), warnIfMissed: false);
      expect(hits, 0);
      await t.pumpAndSettle();
    });
  });

  group('F05 reduced motion mid-flight', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: image zoom lands on its target at once', (t) async {
        final key = GlobalKey<SuiteImageViewerState>();
        var reduce = false;
        late StateSetter set;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return _host(
                suite,
                reduce: reduce,
                SizedBox(width: 400, child: SuiteImageViewer(key: key, image: const ColoredBox(color: Colors.teal))),
              );
            },
          ),
        );
        key.currentState!.zoomTo(1.5, const Size(400, 220));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        expect(key.currentState!.scale, lessThan(1.5));
        set(() => reduce = true);
        await t.pump();
        expect(key.currentState!.scale, closeTo(1.5, 1e-9));
        expect(t.hasRunningAnimations, isFalse);
      });

      testWidgets('${suite.name}: sort arrow and new rows stop at their end state', (t) async {
        var reduce = false;
        var dir = SortDirection.ascending;
        late StateSetter set;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return _host(
                suite,
                reduce: reduce,
                Column(
                  children: [
                    SuiteSortHeader(label: '尺寸', direction: dir, onTap: () {}),
                    if (dir == SortDirection.descending) const SuiteAppear(child: Text('new row')),
                  ],
                ),
              );
            },
          ),
        );
        set(() => dir = SortDirection.descending);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.hasRunningAnimations, isTrue);
        set(() => reduce = true);
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(find.text('new row'), findsOneWidget);
      });
    }

    testWidgets('style card preview stops on its current item; choosing under reduced motion stays put', (t) async {
      var reduce = false;
      var chosen = InteractionSuite.rail;
      late StateSetter set;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, s) {
            set = s;
            return _host(
              InteractionSuite.rail,
              reduce: reduce,
              SingleChildScrollView(
                child: SuiteStyleCards(value: chosen, onChanged: (v) => s(() => chosen = v)),
              ),
            );
          },
        ),
      );
      final glowTrack = find.descendant(
        of: find.ancestor(of: find.text('光晕'), matching: find.byType(SuitePressable)).first,
        matching: find.byType(SuiteSelectionTrack),
      );
      int selected() => t.widget<SuiteSelectionTrack>(glowTrack).selected;
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('光晕')));
      await t.pump(const Duration(milliseconds: 100));
      set(() => reduce = true);
      await t.pump();
      final at = selected();
      await t.pump(const Duration(seconds: 3));
      expect(selected(), at);
      await mouse.removePointer();
      // Choosing while static does not advance the preview.
      final before = selected();
      set(() => chosen = InteractionSuite.glow);
      await t.pump();
      expect(selected(), before);
      await t.pumpAndSettle();
    });
  });

  group('F06 keyboard source survives composition', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: Enter on a zoom button jumps; a click animates', (t) async {
        final key = GlobalKey<SuiteImageViewerState>();
        await t.pumpWidget(
          _host(suite, SizedBox(width: 400, child: SuiteImageViewer(key: key, image: const ColoredBox(color: Colors.teal)))),
        );
        final zoomIn = find.bySemanticsLabel('放大');
        Focus.of(t.element(find.descendant(of: zoomIn, matching: find.byType(Icon)))).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(key.currentState!.scale, closeTo(1.5, 1e-9));
        await t.tap(zoomIn);
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        final mid = key.currentState!.scale;
        expect(mid, greaterThan(1.5));
        expect(mid, lessThan(2.25));
        await t.pumpAndSettle();
        expect(key.currentState!.scale, closeTo(2.25, 1e-9));
      });

      testWidgets('${suite.name}: Esc removes the drawer in the same frame; the scrim animates', (t) async {
        var open = true;
        late StateSetter set;
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuiteDrawer(
                  open: open,
                  onClose: () => s(() => open = false),
                  child: const Center(child: TextField()),
                );
              },
            ),
          ),
        );
        await t.tap(find.byType(TextField));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(TextField), findsNothing);
        // A pointer close afterwards still plays the exit.
        set(() => open = true);
        await t.pumpAndSettle();
        await t.tapAt(const Offset(20, 300));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(find.byType(TextField), findsOneWidget);
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
      });

      testWidgets('${suite.name}: a keyboard-opened dialog is complete on the first frame', (t) async {
        await t.pumpWidget(
          _innerHost(
            ValueNotifier(InteractionData(suite: suite, palette: palette)),
            Builder(
              builder: (context) => SuitePressable(
                kind: PressableKind.primary,
                autofocus: true,
                onActivate: (src) => showSuiteDialog<void>(context, (ctx) => const Text('创建房间'), source: src),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        final route = ModalRoute.of(t.element(find.text('创建房间')))!;
        expect(route.animation!.status, AnimationStatus.completed);
      });
    }
  });

  group('F07 tooltip stays inside the window', () {
    Future<Rect> bubbleFor(WidgetTester t, Alignment where) async {
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const message = '这是一条比较长的提示信息，用来检查窗口边缘不会把它裁掉';
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          Align(
            alignment: where,
            child: const SuiteTooltip(
              message: message,
              child: SizedBox(width: 32, height: 32, child: Icon(Icons.info_outline)),
            ),
          ),
        ),
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.byIcon(Icons.info_outline)));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      final rect = t.getRect(find.text(message));
      await mouse.removePointer();
      return rect;
    }

    for (final where in [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight, Alignment.centerLeft]) {
      testWidgets('anchor at $where: at least 8 px inside every edge', (t) async {
        final r = await bubbleFor(t, where);
        expect(r.left, greaterThanOrEqualTo(8));
        expect(r.top, greaterThanOrEqualTo(8));
        expect(r.right, lessThanOrEqualTo(792));
        expect(r.bottom, lessThanOrEqualTo(592));
      });
    }
  });
}
