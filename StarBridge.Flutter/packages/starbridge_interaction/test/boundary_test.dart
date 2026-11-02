// Boundary probes from the Codex acceptance audit (2026-10-06), kept as
// regression tests for the effect package.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

const palette = InteractionPalette(
  brightness: Brightness.dark,
  accent: Color(0xFF4CB2F5), accentBright: Color(0xFF87CEFF),
  onAccent: Color(0xFF071925), selectedFill: Color(0xFF173348),
  surface: Color(0xFF0B1217), raised: Color(0xFF18242C),
  border: Color(0xFF4C616E), textPrimary: Color(0xFFE7EEF2),
  textSecondary: Color(0xFF93A4AE), textDisabled: Color(0xFF5A6A74),
  focusRing: Color(0xFF87CEFF), success: Color(0xFF3ED59A),
  onSuccess: Color(0xFF06261A), danger: Color(0xFFF26D75),
  onDanger: Color(0xFF2A0709), warning: Color(0xFFF5B544),
);

Widget host(InteractionSuite suite, Widget child, {bool reduce = false}) =>
    MaterialApp(home: Scaffold(body: InteractionScope(
      data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
      child: Align(alignment: Alignment.topLeft, child: child),
    )));

void main() {
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('${suite.name} switch: keyboard activation leaves no decoration', (t) async {
      var on = false;
      await t.pumpWidget(host(suite, StatefulBuilder(builder: (context, set) =>
        SuiteSwitch(value: on, onChanged: (v) => set(() => on = v)))));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(on, isTrue);
      expect(t.hasRunningAnimations, isFalse,
        reason: 'Keyboard must skip beam/bracket/ring as well as knob travel.');
    });
  }

  testWidgets('field: enabling reduced motion stops the active focus animation', (t) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var reduce = false;
    late StateSetter change;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, set) {
        change = set;
        return InteractionScope(
          data: InteractionData(suite: InteractionSuite.rail, palette: palette, reduceMotion: reduce),
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 200,
            child: SuiteFieldFrame(focusNode: focus,
              child: TextField(focusNode: focus, showCursor: false)))));
      }))));
    AnimationController frameAnimation() {
      final paints = t.widgetList<CustomPaint>(find.descendant(
        of: find.byType(SuiteFieldFrame), matching: find.byType(CustomPaint)));
      final painter = paints.map((v) => v.painter).firstWhere(
        (v) => v.runtimeType.toString() == '_FieldPainter');
      return (painter as dynamic).focus as AnimationController;
    }
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(focus.hasFocus, isTrue);
    expect(frameAnimation().isAnimating, isTrue);
    change(() => reduce = true);
    await t.pump();
    expect(frameAnimation().isAnimating, isFalse,
      reason: 'App reduced-motion changes must settle a running field controller.');
    expect(frameAnimation().value, 1);
  });

  testWidgets('dialog: a live app reduced-motion change reaches the open route', (t) async {
    var reduce = false;
    late StateSetter change;
    await t.pumpWidget(StatefulBuilder(builder: (context, set) {
      change = set;
      return InteractionScope(
        data: InteractionData(suite: InteractionSuite.scan, palette: palette, reduceMotion: reduce),
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
          TextButton(onPressed: () => showSuiteDialog(context, (context) =>
            Dialog(child: Text('dialog reduce=${InteractionScope.of(context).reduceMotion}'))),
            child: const Text('open'))))));
    }));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('dialog reduce=false'), findsOneWidget);
    change(() => reduce = true);
    await t.pump();
    expect(find.text('dialog reduce=true'), findsOneWidget,
      reason: 'An open route must not retain stale InteractionData.');
  });

  testWidgets('action button: accessibility retains a button and tap action', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(host(InteractionSuite.rail, SuiteActionButton(
      phase: ActionPhase.idle, onPressed: () {}, label: 'save',
      busyLabel: 'saving', successLabel: 'saved', failureLabel: 'retry')));
    await t.pumpAndSettle();
    final data = t.getSemantics(find.byType(SuiteActionButton)).getSemanticsData();
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue,
      reason: 'ExcludeSemantics must not remove the only activation action.');
    expect(data.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('standard pressable: Enter is reported as keyboard activation', (t) async {
    InteractionSource? source;
    await t.pumpWidget(host(InteractionSuite.standard, SuitePressable(
      kind: PressableKind.secondary, onActivate: (v) => source = v,
      child: const Text('go'))));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(source, InteractionSource.keyboard);
    await t.pumpAndSettle();
  });

  testWidgets('dropdown: Escape closes immediately for a keyboard user', (t) async {
    final key = GlobalKey<SuiteDropdownState>();
    await t.pumpWidget(host(InteractionSuite.scan, SuiteDropdown(
      key: key, label: 'sort', entries: const [SuiteMenuEntry('one')],
      onSelected: (_) {})));
    await t.pumpAndSettle();
    key.currentState!.open(source: InteractionSource.keyboard);
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('one'), findsNothing,
      reason: 'Escape must not wait for a 180ms pointer exit.');
    await t.pumpAndSettle();
  });

  // Updated for the continuous-state requirement (recheck 2026-10-06): high
  // frequency keeps feedback, but shows the latest value, never queues old
  // effects, and settles completely after silence.
  testWidgets('counter: a burst shows the latest value and settles after silence', (t) async {
    var value = 1;
    late StateSetter change;
    await t.pumpWidget(host(InteractionSuite.scan, StatefulBuilder(builder: (context, set) {
      change = set;
      return SuiteCounter(value: value, coalesceDataUpdates: true);
    })));
    for (var i = 2; i <= 6; i++) {
      change(() => value = i);
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('6'), findsOneWidget);
    // Real frames (not one long jump): silence ends the burst, then it settles.
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('dropdown: ArrowDown then Enter selects the second entry', (t) async {
    final key = GlobalKey<SuiteDropdownState>();
    int? selected;
    await t.pumpWidget(host(InteractionSuite.rail, SuiteDropdown(
      key: key, label: 'sort', entries: const [SuiteMenuEntry('one'), SuiteMenuEntry('two')],
      onSelected: (v) => selected = v)));
    key.currentState!.open(source: InteractionSource.keyboard);
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('dropdown: entries can grow after its first open', (t) async {
    final key = GlobalKey<SuiteDropdownState>();
    var entries = const [SuiteMenuEntry('one')];
    late StateSetter change;
    await t.pumpWidget(host(InteractionSuite.rail, StatefulBuilder(builder: (context, set) {
      change = set;
      return SuiteDropdown(key: key, label: 'sort', entries: entries, onSelected: (_) {});
    })));
    key.currentState!.open(source: InteractionSource.keyboard);
    await t.pumpAndSettle();
    key.currentState!.close();
    await t.pumpAndSettle();
    change(() => entries = const [SuiteMenuEntry('one'), SuiteMenuEntry('two')]);
    await t.pump();
    key.currentState!.open(source: InteractionSource.keyboard);
    await t.pump();
    expect(t.takeException(), isNull, reason: 'Focus nodes must follow current entry count.');
    expect(find.text('two'), findsOneWidget);
    await t.pumpAndSettle();
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: a busy frame settles when reduced motion changes live', (t) async {
      var reduce = false;
      late StateSetter change;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, set) {
        change = set;
        return InteractionScope(data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
          child: const SuiteBusyFrame(busy: true, child: SizedBox(width: 200, height: 60)));
      }))));
      await t.pump(const Duration(milliseconds: 40));
      change(() => reduce = true);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    });
  }
}
