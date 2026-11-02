// Edge cases around the audit findings: keyboard paths, live reduced motion,
// dynamic menus and accessibility for every suite and phase.
import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

const palette = InteractionPalette(
  brightness: Brightness.dark,
  accent: Color(0xFF4CB2F5),
  accentBright: Color(0xFF87CEFF),
  onAccent: Color(0xFF071925),
  selectedFill: Color(0xFF173348),
  surface: Color(0xFF0B1217),
  raised: Color(0xFF18242C),
  border: Color(0xFF4C616E),
  textPrimary: Color(0xFFE7EEF2),
  textSecondary: Color(0xFF93A4AE),
  textDisabled: Color(0xFF5A6A74),
  focusRing: Color(0xFF87CEFF),
  success: Color(0xFF3ED59A),
  onSuccess: Color(0xFF06261A),
  danger: Color(0xFFF26D75),
  onDanger: Color(0xFF2A0709),
  warning: Color(0xFFF5B544),
);

/// A host whose suite and reduced-motion flag can change while running.
class _Live extends StatefulWidget {
  const _Live({required this.suite, required this.child});
  final InteractionSuite suite;
  final Widget child;

  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> {
  bool reduce = false;
  void setReduce(bool v) => setState(() => reduce = v);

  @override
  Widget build(BuildContext context) => InteractionScope(
    data: InteractionData(suite: widget.suite, palette: palette, reduceMotion: reduce),
    child: MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: widget.child)),
    ),
  );
}

Future<_LiveState> _pumpLive(WidgetTester t, InteractionSuite suite, Widget child) async {
  await t.pumpWidget(_Live(suite: suite, child: child));
  return t.state<_LiveState>(find.byType(_Live));
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: keyboard checkbox and switch leave no animation', (t) async {
      var on = false;
      bool? checked = false;
      await _pumpLive(
        t,
        suite,
        StatefulBuilder(
          builder: (context, set) => Row(
            children: [
              SuiteSwitch(value: on, onChanged: (v) => set(() => on = v)),
              SuiteCheckbox(value: checked, onChanged: (v) => set(() => checked = v)),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(on, isTrue);
      expect(checked, isTrue);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('${suite.name}: reduced motion mid-slide settles the track at once', (t) async {
      var selected = 0;
      final live = await _pumpLive(
        t,
        suite,
        SizedBox(
          width: 220,
          child: StatefulBuilder(
            builder: (context, set) => SuiteSelectionTrack(
              style: TrackStyle.navigation,
              items: const [TrackItem(label: 'A'), TrackItem(label: 'B'), TrackItem(label: 'C')],
              selected: selected,
              onChanged: (i, _) => set(() => selected = i),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('C'));
      await t.pump(const Duration(milliseconds: 60));
      live.setReduce(true);
      await t.pump();
      final s = t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));
      expect(s.indicatorRect, s.itemRect(2));
      // Standard is stock Material: an ink ripple already in flight finishes.
      if (suite != InteractionSuite.standard) {
        expect(t.hasRunningAnimations, isFalse);
      }
    });

    testWidgets('${suite.name}: action button semantics in every phase', (t) async {
      for (final phase in ActionPhase.values) {
        final semantics = t.ensureSemantics();
        await t.pumpWidget(
          _Live(
            suite: suite,
            child: SuiteActionButton(
              phase: phase,
              onPressed: () {},
              label: 'save',
              busyLabel: 'saving',
              successLabel: 'saved',
              failureLabel: 'retry',
            ),
          ),
        );
        await t.pump();
        final data = t.getSemantics(find.byType(SuiteActionButton)).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue, reason: '$phase');
        expect(data.hasAction(SemanticsAction.tap), phase != ActionPhase.busy, reason: '$phase');
        semantics.dispose();
        // Busy loops never settle; just let one-shot effects finish.
        await t.pump(const Duration(seconds: 2));
      }
    });
  }

  testWidgets('Escape returns focus to the dropdown anchor', (t) async {
    final key = GlobalKey<SuiteDropdownState>();
    await _pumpLive(
      t,
      InteractionSuite.rail,
      SuiteDropdown(
        key: key,
        label: 'sort',
        entries: const [SuiteMenuEntry('one'), SuiteMenuEntry('two')],
        onSelected: (_) {},
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(find.text('two'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('two'), findsNothing);
    // Enter on the focused anchor reopens: focus came back to it.
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('two'), findsOneWidget);
    await t.pumpAndSettle();
  });

  testWidgets('dropdown entries can shrink, empty and disable while open', (t) async {
    final key = GlobalKey<SuiteDropdownState>();
    var entries = const [SuiteMenuEntry('one'), SuiteMenuEntry('two'), SuiteMenuEntry('three')];
    late StateSetter change;
    await _pumpLive(
      t,
      InteractionSuite.scan,
      StatefulBuilder(
        builder: (context, set) {
          change = set;
          return SuiteDropdown(key: key, label: 'sort', entries: entries, onSelected: (_) {});
        },
      ),
    );
    key.currentState!.open(source: InteractionSource.keyboard);
    await t.pump();
    await t.pump();
    key.currentState!.itemFocus(2).requestFocus();
    await t.pump();
    change(() => entries = const [SuiteMenuEntry('one')]);
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('three'), findsNothing);
    change(() => entries = const []);
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    change(() => entries = const [SuiteMenuEntry('x', enabled: false)]);
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('x'), findsOneWidget);
    await t.pumpAndSettle();
  });

  testWidgets('keyboard-opened dialog appears at once', (t) async {
    late BuildContext ctx;
    await _pumpLive(
      t,
      InteractionSuite.scan,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );
    showSuiteDialog<void>(
      ctx,
      (_) => const Dialog(child: Text('dialog')),
      source: InteractionSource.keyboard,
    );
    await t.pump();
    await t.pump();
    expect(find.text('dialog'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion mid-entrance shows the dialog settled', (t) async {
    final live = await _pumpLive(
      t,
      InteractionSuite.scan,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSuiteDialog<void>(context, (_) => const Dialog(child: Text('dialog'))),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    live.setReduce(true);
    await t.pump();
    // Line phase would still hide the content; reduced motion shows it whole.
    final clip = find.ancestor(of: find.text('dialog'), matching: find.byType(ClipRect));
    expect(clip, findsNothing);
    await t.pumpAndSettle();
  });

  testWidgets('a low-frequency counter change still plays its effect', (t) async {
    var value = 1;
    late StateSetter change;
    await _pumpLive(
      t,
      InteractionSuite.scan,
      StatefulBuilder(
        builder: (context, set) {
          change = set;
          return SuiteCounter(value: value);
        },
      ),
    );
    change(() => value = 2);
    await t.pump();
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('reduced motion mid-hover settles the pressable', (t) async {
    final live = await _pumpLive(
      t,
      InteractionSuite.rail,
      SuitePressable(kind: PressableKind.card, onPressed: () {}, child: const Text('card')),
    );
    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: t.getCenter(find.text('card')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    expect(t.hasRunningAnimations, isTrue);
    live.setReduce(true);
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    await gesture.removePointer();
    await t.pumpAndSettle();
  });
}
