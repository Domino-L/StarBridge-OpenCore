// Active feedback is never frequency-suppressed. Only explicitly passive
// data opts into bounded continuous feedback. Keyboard/reduced motion settle.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

class _Host extends StatefulWidget {
  const _Host({required this.suite, required this.child});
  final InteractionSuite suite;
  final Widget child;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool reduce = false;
  void setReduce(bool v) => setState(() => reduce = v);
  @override
  Widget build(BuildContext context) => InteractionScope(
    data: InteractionData(
      suite: widget.suite,
      palette: palette,
      reduceMotion: reduce,
    ),
    child: MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: widget.child),
      ),
    ),
  );
}

class _Tabs extends StatefulWidget {
  const _Tabs();
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => SuiteSelectionTrack(
    style: TrackStyle.segmented,
    items: const [
      TrackItem(label: 'A'),
      TrackItem(label: 'B'),
      TrackItem(label: 'C'),
      TrackItem(label: 'D'),
    ],
    selected: selected,
    onChanged: (i, _) => setState(() => selected = i),
  );
}

SuiteSelectionTrackState _track(WidgetTester t) =>
    t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));
EffectHostState _effect(WidgetTester t) =>
    t.state<EffectHostState>(find.byType(EffectHost));

Future<void> _frames(WidgetTester t, int ms) async {
  for (var elapsed = 0; elapsed < ms; elapsed += 20) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

void _expectTrackFeedback(WidgetTester t, InteractionSuite suite) {
  final s = _track(t);
  switch (suite) {
    case InteractionSuite.rail:
      expect(s.isStretching, isTrue);
    case InteractionSuite.scan:
      expect(s.isSweeping, isTrue);
    case InteractionSuite.glow:
      expect(s.isRinging, isTrue);
    case InteractionSuite.standard:
      break;
  }
}

void main() {
  testWidgets('removing a held button safely cancels its gesture', (t) async {
    await t.pumpWidget(_Host(
      suite: InteractionSuite.scan,
      child: SuitePressable(
        kind: PressableKind.primary,
        minHeight: 34,
        onPressed: () {},
        child: const Text('Hold'),
      ),
    ));
    final gesture = await t.startGesture(t.getCenter(find.text('Hold')));
    await _frames(t, 120);
    await t.pumpWidget(const SizedBox.shrink());
    await gesture.cancel();
    expect(t.takeException(), isNull);
  });

  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets(
      '${suite.name}: rapid selections retain suite feedback, including reversal',
      (t) async {
        await t.pumpWidget(_Host(suite: suite, child: const _Tabs()));
        await t.pumpAndSettle();
        var action = 0;
        for (final label in ['B', 'C', 'D', 'C', 'A', 'D', 'B']) {
          final before = _track(t).indicatorRect;
          await t.tap(find.text(label));
          await t.pump();
          if (suite != InteractionSuite.scan) {
            expect(_track(t).indicatorRect, before);
          }
          await _frames(t, 40); // Faster than the scan/glow entrance delay.
          if (action++ > 0) _expectTrackFeedback(t, suite);
        }
        await _frames(t, 1600);
        expect(_track(t).indicatorRect, _track(t).itemRect(1));
        expect(t.hasRunningAnimations, isFalse);
      },
    );

    testWidgets(
      '${suite.name}: keyboard interrupts rapid selection immediately',
      (t) async {
        await t.pumpWidget(_Host(suite: suite, child: const _Tabs()));
        await t.pumpAndSettle();
        for (final label in ['B', 'C', 'D', 'C']) {
          await t.tap(find.text(label));
          await t.pump();
          await _frames(t, 80);
        }
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        final s = _track(t);
        expect(s.indicatorRect, s.itemRect(s.widget.selected));
        expect(s.isStretching || s.isSweeping || s.isRinging, isFalse);
        // A different item's earlier pointer-release feedback may still
        // finish; keyboard does not start any new selection decoration.
        await _frames(t, 160);
        expect(t.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('${suite.name}: live reduced motion stops rapid selection', (
      t,
    ) async {
      await t.pumpWidget(_Host(suite: suite, child: const _Tabs()));
      await t.pumpAndSettle();
      for (final label in ['B', 'C', 'D']) {
        await t.tap(find.text(label));
        await t.pump();
        await _frames(t, 80);
      }
      t.state<_HostState>(find.byType(_Host)).setReduce(true);
      await t.pump();
      expect(_track(t).indicatorRect, _track(t).itemRect(3));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets(
      '${suite.name}: rapid presses keep every callback and press effect',
      (t) async {
        var presses = 0;
        await t.pumpWidget(
          _Host(
            suite: suite,
            child: SuitePressable(
              kind: PressableKind.primary,
              minHeight: 34,
              onPressed: () => presses++,
              child: const Text('+1'),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await t.tap(find.text('+1'));
          await t.pump();
          await _frames(t, 60);
          if (suite == InteractionSuite.scan) {
            expect(_effect(t).isPlaying(TransientEffect.beam), isTrue);
          }
          if (suite == InteractionSuite.glow) {
            expect(_effect(t).isPlaying(TransientEffect.ring), isTrue);
          }
          expect(presses, i + 1);
        }
        await _frames(t, 1500);
        expect(t.hasRunningAnimations, isFalse);
      },
    );

    testWidgets(
      '${suite.name}: keyboard button clears an existing pointer effect',
      (t) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var presses = 0;
        await t.pumpWidget(
          _Host(
            suite: suite,
            child: SuitePressable(
              kind: PressableKind.primary,
              focusNode: focus,
              minHeight: 34,
              onPressed: () => presses++,
              child: const Text('Run'),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await t.tap(find.text('Run'));
          await t.pump();
          await _frames(t, 60);
        }
        focus.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(presses, 5);
        expect(t.hasRunningAnimations, isFalse);
      },
    );

    testWidgets(
      '${suite.name}: passive counter keeps latest data and settles',
      (t) async {
        var value = 10;
        late StateSetter set;
        await t.pumpWidget(
          _Host(
            suite: suite,
            child: StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuiteCounter(value: value, coalesceDataUpdates: true);
              },
            ),
          ),
        );
        for (final v in [11, 12, 13, 12, 14, 15]) {
          set(() => value = v);
          await t.pump();
          await _frames(t, 80);
          expect(find.text('$v'), findsWidgets);
        }
        await _frames(t, 2000);
        expect(t.hasRunningAnimations, isFalse);
        expect(find.text('15'), findsOneWidget);
        expect(find.text('14'), findsNothing);
      },
    );

    testWidgets(
      '${suite.name}: disabling data coalescing clears the old state',
      (t) async {
        var value = 10;
        var passive = true;
        late StateSetter set;
        await t.pumpWidget(
          _Host(
            suite: suite,
            child: StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuiteCounter(value: value, coalesceDataUpdates: passive);
              },
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          set(() => value++);
          await t.pump();
          await _frames(t, 60);
        }
        set(() => passive = false);
        await t.pump();
        expect(find.text('14'), findsOneWidget);
        expect(t.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('${suite.name}: reduced motion stops passive data flow', (
      t,
    ) async {
      var value = 10;
      late StateSetter set;
      await t.pumpWidget(
        _Host(
          suite: suite,
          child: StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteCounter(value: value, coalesceDataUpdates: true);
            },
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        set(() => value++);
        await t.pump();
        await _frames(t, 60);
      }
      t.state<_HostState>(find.byType(_Host)).setReduce(true);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      expect(find.text('14'), findsOneWidget);
    });
  }

  testWidgets('manual counter retains its full scan flash on every update', (
    t,
  ) async {
    var value = 10;
    late StateSetter set;
    await t.pumpWidget(
      _Host(
        suite: InteractionSuite.scan,
        child: StatefulBuilder(
          builder: (context, s) {
            set = s;
            return SuiteCounter(value: value);
          },
        ),
      ),
    );
    for (final v in [11, 12, 13, 12, 14, 15, 16, 17]) {
      set(() => value = v);
      await t.pump();
      await _frames(t, 60);
      expect(_effect(t).isPlaying(TransientEffect.bracketFlash), isTrue);
    }
    await _frames(t, 1600);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'passive counter alone coalesces scan, then restores a single flash',
    (t) async {
      var value = 10;
      var source = InteractionSource.programmatic;
      late StateSetter set;
      await t.pumpWidget(
        _Host(
          suite: InteractionSuite.scan,
          child: StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteCounter(
                value: value,
                coalesceDataUpdates: true,
                source: source,
              );
            },
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        set(() => value++);
        await t.pump();
        await _frames(t, 60);
        expect(_effect(t).isPlaying(TransientEffect.bracketFlash), i < 2);
      }
      await _frames(t, 1600);
      set(() => value++);
      await t.pump();
      await _frames(t, 60);
      expect(_effect(t).isPlaying(TransientEffect.bracketFlash), isTrue);
      set(() {
        source = InteractionSource.keyboard;
        value++;
      });
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      expect(find.text('$value'), findsOneWidget);
    },
  );

  for (final passive in [false, true]) {
    testWidgets(
      'row data coalescing is opt-in ($passive), clicks do not count as data',
      (t) async {
        var token = 0;
        var clicks = 0;
        late StateSetter set;
        await t.pumpWidget(
          _Host(
            suite: InteractionSuite.scan,
            child: StatefulBuilder(
              builder: (context, s) {
                set = s;
                return SuitePressable(
                  kind: PressableKind.row,
                  minHeight: 34,
                  flashToken: token,
                  coalesceDataUpdates: passive,
                  onPressed: () => clicks++,
                  child: const Text('Member'),
                );
              },
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await t.tap(find.text('Member'));
          await t.pump();
          await _frames(t, 40);
        }
        expect(clicks, 5);
        for (var i = 0; i < 4; i++) {
          set(() => token++);
          await t.pump();
          await _frames(t, 60);
          expect(_effect(t).isPlaying(TransientEffect.beam), !passive || i < 2);
        }
        await _frames(t, 1600);
        expect(t.hasRunningAnimations, isFalse);
      },
    );
  }

  testWidgets('rail digit reversal preserves the currently entering digit', (
    t,
  ) async {
    var value = 10;
    late StateSetter set;
    await t.pumpWidget(
      _Host(
        suite: InteractionSuite.rail,
        child: StatefulBuilder(
          builder: (context, s) {
            set = s;
            return SuiteCounter(value: value);
          },
        ),
      ),
    );
    set(() => value = 11);
    await t.pump();
    await _frames(t, 80);
    final digit = find.text('11');
    final before = t.getTopLeft(digit);
    final opacityBefore = t
        .widget<Opacity>(
          find.ancestor(of: digit, matching: find.byType(Opacity)).first,
        )
        .opacity;
    set(() => value = 9);
    await t.pump();
    expect(t.getTopLeft(digit), before);
    final opacityAfter = t
        .widget<Opacity>(
          find.ancestor(of: digit, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacityAfter, closeTo(opacityBefore, 0.000001));
    await _frames(t, 1600);
    expect(find.text('9'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('standard: rapid selection still jumps plainly', (t) async {
    await t.pumpWidget(
      const _Host(suite: InteractionSuite.standard, child: _Tabs()),
    );
    await t.pumpAndSettle();
    for (final label in ['B', 'C', 'D', 'C']) {
      await t.tap(find.text(label));
      await t.pump();
    }
    expect(_track(t).indicatorRect, _track(t).itemRect(2));
  });
}
