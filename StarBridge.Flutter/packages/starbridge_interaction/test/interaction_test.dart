import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

const _palette = InteractionPalette(
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

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => MaterialApp(
  home: Scaffold(
    body: InteractionScope(
      data: InteractionData(suite: suite, palette: _palette, reduceMotion: reduce),
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

class _Nav extends StatefulWidget {
  const _Nav({this.onSource});
  final ValueChanged<InteractionSource>? onSource;

  @override
  State<_Nav> createState() => _NavState();
}

class _NavState extends State<_Nav> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: SuiteSelectionTrack(
      style: TrackStyle.navigation,
      items: const [
        TrackItem(label: 'A'),
        TrackItem(label: 'B'),
        TrackItem(label: 'C'),
        TrackItem(label: 'D'),
      ],
      selected: selected,
      onChanged: (i, s) {
        widget.onSource?.call(s);
        setState(() => selected = i);
      },
    ),
  );
}

SuiteSelectionTrackState _track(WidgetTester t) =>
    t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));

void main() {
  group('selection track', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: settles exactly on the new item', (tester) async {
        await tester.pumpWidget(_host(suite, const _Nav()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('C'));
        await tester.pumpAndSettle();
        final s = _track(tester);
        expect(s.indicatorRect, s.itemRect(2));
      });
    }

    testWidgets('rail stretches over both items before settling', (tester) async {
      await tester.pumpWidget(_host(InteractionSuite.rail, const _Nav()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('D'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final s = _track(tester);
      final union = s.itemRect(0)!.expandToInclude(s.itemRect(3)!);
      expect(s.indicatorRect!.top, closeTo(union.top, 0.5));
      expect(s.indicatorRect!.bottom, closeTo(union.bottom, 0.5));
      await tester.pumpAndSettle();
      expect(s.indicatorRect, s.itemRect(3));
    });

    testWidgets('a new target mid-slide retargets without queueing', (tester) async {
      await tester.pumpWidget(_host(InteractionSuite.glow, const _Nav()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('D'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      final s = _track(tester);
      expect(s.indicatorRect, s.itemRect(1));
    });

    for (final suite in [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow]) {
      testWidgets('${suite.name}: keyboard selection jumps immediately', (tester) async {
        InteractionSource? source;
        await tester.pumpWidget(_host(suite, _Nav(onSource: (s) => source = s)));
        await tester.pumpAndSettle();
        // Keyboard users reach the item with Tab, then use the arrows.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final s = _track(tester);
        expect(source, InteractionSource.keyboard);
        expect(s.indicatorRect, s.itemRect(1));
        expect(tester.hasRunningAnimations, isFalse);
      });

      testWidgets('${suite.name}: reduced motion jumps immediately', (tester) async {
        await tester.pumpWidget(_host(suite, const _Nav(), reduce: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('C'));
        await tester.pump();
        final s = _track(tester);
        expect(s.indicatorRect, s.itemRect(2));
      });
    }

    testWidgets('system disableAnimations also counts as reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(InteractionSuite.rail, const _Nav()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pump();
      final s = _track(tester);
      expect(s.indicatorRect, s.itemRect(2));
    });
  });

  group('pressable', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: tap and keyboard both activate, disabled does not', (tester) async {
        final sources = <InteractionSource>[];
        await tester.pumpWidget(
          _host(
            suite,
            Column(
              children: [
                SuitePressable(
                  kind: PressableKind.primary,
                  minHeight: 34,
                  onActivate: sources.add,
                  child: const Text('go'),
                ),
                const SuitePressable(kind: PressableKind.secondary, child: Text('off')),
              ],
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('off'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(sources, [InteractionSource.pointer]);

        if (suite != InteractionSuite.standard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(sources.last, InteractionSource.keyboard);
        }
      });
    }

    testWidgets('effects are skipped under reduced motion', (tester) async {
      await tester.pumpWidget(
        _host(
          InteractionSuite.glow,
          SuitePressable(kind: PressableKind.primary, onPressed: () {}, child: const Text('go')),
          reduce: true,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('toggles', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: switch and checkbox follow the caller value', (tester) async {
        var on = false;
        bool? checked = false;
        await tester.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, set) => Row(
                children: [
                  SuiteSwitch(value: on, onChanged: (v) => set(() => on = v)),
                  SuiteCheckbox(value: checked, onChanged: (v) => set(() => checked = v)),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byType(SuiteSwitch));
        await tester.tap(find.byType(SuiteCheckbox));
        await tester.pumpAndSettle();
        expect(on, isTrue);
        expect(checked, isTrue);
      });
    }

    testWidgets('a rejected change leaves the switch where it was', (tester) async {
      await tester.pumpWidget(
        _host(InteractionSuite.rail, SuiteSwitch(value: false, onChanged: (_) {})),
      );
      await tester.tap(find.byType(SuiteSwitch));
      await tester.pumpAndSettle();
      expect(tester.widget<SuiteSwitch>(find.byType(SuiteSwitch)).value, isFalse);
    });
  });

  group('surfaces', () {
    testWidgets('reopening during the close keeps the menu open', (tester) async {
      final key = GlobalKey<SuiteDropdownState>();
      await tester.pumpWidget(
        _host(
          InteractionSuite.scan,
          SuiteDropdown(
            key: key,
            label: 'sort',
            entries: const [SuiteMenuEntry('one'), SuiteMenuEntry('two')],
            onSelected: (_) {},
          ),
        ),
      );
      key.currentState!.open();
      await tester.pumpAndSettle();
      key.currentState!.close();
      await tester.pump(const Duration(milliseconds: 60));
      key.currentState!.open();
      await tester.pumpAndSettle();
      expect(find.text('two'), findsOneWidget);
      expect(key.currentState!.isOpen, isTrue);
    });

    testWidgets('Esc and outside taps close the menu', (tester) async {
      final key = GlobalKey<SuiteDropdownState>();
      await tester.pumpWidget(
        _host(
          InteractionSuite.rail,
          SuiteDropdown(
            key: key,
            label: 'sort',
            entries: const [SuiteMenuEntry('one')],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('sort'));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('one'), findsNothing);
    });

    for (final suite in InteractionSuite.values) {
      for (final kind in SurfaceKind.values) {
        testWidgets('${suite.name}/${kind.name}: open and close without layout errors', (tester) async {
          final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _host(
              suite,
              Stack(
                children: [
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: SuiteSurfaceTransition(
                      animation: controller,
                      kind: kind,
                      child: const SizedBox(width: 120, height: 40, child: Text('surface')),
                    ),
                  ),
                ],
              ),
            ),
          );
          controller.forward();
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
          controller.reverse();
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('async', () {
    testWidgets('busy action button ignores taps; success only when reported', (tester) async {
      var presses = 0;
      var phase = ActionPhase.busy;
      late StateSetter setPhase;
      await tester.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, set) {
              setPhase = set;
              return SuiteActionButton(
                phase: phase,
                onPressed: () => presses++,
                label: 'save',
                busyLabel: 'saving',
                successLabel: 'saved',
                failureLabel: 'retry',
              );
            },
          ),
        ),
      );
      await tester.tap(find.byType(SuiteActionButton), warnIfMissed: false);
      await tester.pump();
      expect(presses, 0);
      expect(find.text('saved'), findsNothing);
      setPhase(() => phase = ActionPhase.failure);
      await tester.pumpAndSettle();
      await tester.tap(find.text('retry'));
      expect(presses, 1);
      setPhase(() => phase = ActionPhase.success);
      await tester.pumpAndSettle();
      expect(find.text('saved'), findsOneWidget);
    });

    testWidgets('busy frame loop stops when the task ends', (tester) async {
      var busy = true;
      late StateSetter set;
      await tester.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteBusyFrame(busy: busy, child: const SizedBox(width: 200, height: 60));
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      set(() => busy = false);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('passive counter updates keep the latest value without queueing', (tester) async {
      var value = 1;
      late StateSetter set;
      await tester.pumpWidget(
        _host(
          InteractionSuite.rail,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteCounter(value: value, coalesceDataUpdates: true);
            },
          ),
        ),
      );
      set(() => value = 2);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      set(() => value = 3);
      await tester.pump();
      set(() => value = 4);
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('content switcher: back navigation is instant', (tester) async {
      var page = 0;
      var instant = false;
      late StateSetter set;
      await tester.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return SuiteContentSwitcher(instant: instant, child: Text('page $page', key: ValueKey(page)));
            },
          ),
        ),
      );
      set(() {
        page = 1;
        instant = true;
      });
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('page 1'), findsOneWidget);
    });
  });
}
