// Batch 1 families: icon toggle (05), slider/stepper (07), expander (08),
// search suggestions (10), filter chips (11), tooltip (14).
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
  child: MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ),
);

void main() {
  group('05 icon toggle', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: pointer toggles; keyboard toggles without animation', (t) async {
        var on = false;
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, set) => SuiteIconToggle(
                value: on,
                offIcon: Icons.star_border,
                onIcon: Icons.star,
                semanticLabel: 'fav',
                onChanged: (v) => set(() => on = v),
              ),
            ),
          ),
        );
        await t.tap(find.byType(SuiteIconToggle));
        await t.pumpAndSettle();
        expect(on, isTrue);
        expect(find.byIcon(Icons.star), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(on, isFalse);
        expect(find.byIcon(Icons.star_border), findsOneWidget);
        expect(t.hasRunningAnimations, isFalse);
      });
    }
  });

  group('07 slider and stepper', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: drag follows exactly; keys step instantly', (t) async {
        var value = 50.0;
        await t.pumpWidget(
          _host(
            suite,
            SizedBox(
              width: 218,
              child: StatefulBuilder(
                builder: (context, set) => SuiteSlider(
                  value: value,
                  min: 0,
                  max: 100,
                  onChanged: (v) => set(() => value = v),
                ),
              ),
            ),
          ),
        );
        final box = t.getRect(find.byType(SuiteSlider));
        // Track runs from x+9 to x+209 (200 px): 25 % is at x+59.
        final g = await t.startGesture(Offset(box.left + 109, box.center.dy));
        await g.moveTo(Offset(box.left + 59, box.center.dy));
        await t.pump();
        expect(value, closeTo(25, 0.01));
        await g.moveTo(Offset(box.left + 159, box.center.dy));
        await t.pump();
        expect(value, closeTo(75, 0.01));
        await g.up();
        await t.pumpAndSettle();

        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        expect(value, closeTo(80, 0.01));
        await t.sendKeyEvent(LogicalKeyboardKey.end);
        await t.pump();
        expect(value, 100);
        await t.sendKeyEvent(LogicalKeyboardKey.home);
        await t.pump();
        expect(value, 0);
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('divisions snap the real value', (t) async {
      var value = 0.0;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          SizedBox(
            width: 218,
            child: StatefulBuilder(
              builder: (context, set) => SuiteSlider(
                value: value,
                divisions: 4,
                onChanged: (v) => set(() => value = v),
              ),
            ),
          ),
        ),
      );
      final box = t.getRect(find.byType(SuiteSlider));
      await t.tapAt(Offset(box.left + 9 + 200 * 0.6, box.center.dy));
      await t.pumpAndSettle();
      expect(value, 0.5);
    });

    testWidgets('every stepper press counts, even when rapid', (t) async {
      var value = 2;
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          StatefulBuilder(
            builder: (context, set) => SuiteStepper(
              value: value,
              min: 0,
              max: 5,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await t.tap(find.byIcon(Icons.add), warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(value, 5); // capped at max; the + button disables there
      await t.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('08 expander', () {
    testWidgets('collapsed body keeps its state and is skipped by Tab', (t) async {
      var open = true;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, set) => SuiteExpander(
                title: 'Advanced',
                expanded: open,
                onChanged: (v) => set(() => open = v),
                child: TextField(controller: controller),
              ),
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'draft');
      await t.tap(find.text('Advanced'));
      await t.pumpAndSettle();
      expect(open, isFalse);
      // Still mounted with its text, but out of the focus order.
      expect(controller.text, 'draft');
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final field = t.widget<EditableText>(find.byType(EditableText, skipOffstage: false));
      expect(field.focusNode.hasFocus, isFalse);
      await t.tap(find.text('Advanced'));
      await t.pumpAndSettle();
      expect(controller.text, 'draft');
    });

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: keyboard toggle is instant', (t) async {
        var open = false;
        await t.pumpWidget(
          _host(
            suite,
            SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, set) => SuiteExpander(
                  title: 'Group',
                  expanded: open,
                  onChanged: (v) => set(() => open = v),
                  child: const Text('body'),
                ),
              ),
            ),
          ),
        );
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(open, isTrue);
        expect(t.hasRunningAnimations, isFalse);
      });
    }
  });

  group('10 search box', () {
    testWidgets('an older response never overwrites a newer one', (t) async {
      final pending = <String, Completer<List<String>>>{};
      final key = GlobalKey<SuiteSearchBoxState>();
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          SizedBox(
            width: 260,
            child: SuiteSearchBox(
              key: key,
              search: (q) => (pending[q] = Completer<List<String>>()).future,
              onPicked: (_) {},
            ),
          ),
        ),
      );
      await t.tap(find.byType(TextField));
      key.currentState!.typeQuery('a');
      await t.pump();
      key.currentState!.typeQuery('ab');
      await t.pump();
      pending['ab']!.complete(['ab-1', 'ab-2']);
      await t.pump();
      pending['a']!.complete(['a-old']);
      await t.pump();
      expect(key.currentState!.results, ['ab-1', 'ab-2']);
      await t.pumpAndSettle();
      expect(find.text('a-old'), findsNothing);
      expect(find.text('ab-2'), findsOneWidget);
    });

    testWidgets('arrows + Enter pick; Esc closes at once; clear keeps focus', (t) async {
      String? picked;
      final key = GlobalKey<SuiteSearchBoxState>();
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          SizedBox(
            width: 260,
            child: SuiteSearchBox(
              key: key,
              search: (q) async => ['$q one', '$q two'],
              onPicked: (v) => picked = v,
            ),
          ),
        ),
      );
      await t.tap(find.byType(TextField));
      key.currentState!.typeQuery('x');
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(picked, 'x two');
      expect(key.currentState!.isOpen, isFalse);

      key.currentState!.typeQuery('y');
      await t.pumpAndSettle();
      expect(key.currentState!.isOpen, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('y one'), findsNothing);

      await t.tap(find.byIcon(Icons.close));
      await t.pump();
      expect(find.text('y'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'search');
    });
  });

  group('11 chips', () {
    testWidgets('removal animates out and hands focus to the next chip', (t) async {
      var chips = const [
        SuiteChipData(id: 'a', label: 'A', removable: true),
        SuiteChipData(id: 'b', label: 'B', removable: true),
        SuiteChipData(id: 'c', label: 'C', removable: true),
      ];
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          StatefulBuilder(
            builder: (context, set) => SuiteChipGroup(
              chips: chips,
              onToggle: (_) {},
              onRemove: (id) => set(() => chips = chips.where((c) => c.id != id).toList()),
            ),
          ),
        ),
      );
      // Focus chip B with Tab, remove it with Delete.
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pump();
      expect(chips.map((c) => c.id), ['a', 'c']);
      await t.pumpAndSettle();
      expect(find.text('B'), findsNothing);
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'chip-c');
    });

    testWidgets('toggling reports the chip id', (t) async {
      final toggled = <String>[];
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          SuiteChipGroup(
            chips: const [SuiteChipData(id: 'x', label: 'X')],
            onToggle: toggled.add,
          ),
        ),
      );
      await t.tap(find.text('X'));
      await t.pumpAndSettle();
      expect(toggled, ['x']);
    });
  });

  group('14 tooltip', () {
    Widget tips() => Row(
      children: [
        for (final m in ['one', 'two'])
          SuiteTooltip(
            message: 'tip $m',
            child: SizedBox(width: 60, height: 30, child: Center(child: Text(m))),
          ),
      ],
    );

    testWidgets('waits first, then shows neighbours at once; ignores pointers', (t) async {
      await t.pumpWidget(_host(InteractionSuite.rail, tips()));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('one')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('tip one'), findsNothing);
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('tip one'), findsOneWidget);
      // Browsing to the neighbour: no wait.
      await mouse.moveTo(t.getCenter(find.text('two')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('tip two'), findsOneWidget);
      // The bubble never takes hits.
      final bubble = find.text('tip two');
      final hits = t.hitTestOnBinding(t.getCenter(bubble));
      expect(hits.path.any((e) => e.target is RenderParagraph && (e.target as RenderParagraph).text.toPlainText() == 'tip two'), isFalse);
      await mouse.removePointer();
      await t.pumpAndSettle();
      expect(find.text('tip two'), findsNothing);
    });

    testWidgets('pressing hides the tooltip', (t) async {
      await t.pumpWidget(_host(InteractionSuite.glow, tips()));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('one')));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('tip one'), findsOneWidget);
      await mouse.down(t.getCenter(find.text('one')));
      await t.pumpAndSettle();
      expect(find.text('tip one'), findsNothing);
      await mouse.up();
      await mouse.removePointer();
    });
  });
}
