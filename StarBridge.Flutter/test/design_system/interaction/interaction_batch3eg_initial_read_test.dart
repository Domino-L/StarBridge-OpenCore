import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';

import 'interaction_batch3bd_test.dart' show HeldPlay;
import 'interaction_batch3do_test.dart' show loadFonts, scopedApp, size;

const _panelKey = Key('same-play-original-read');

class _ViewportHost extends StatefulWidget {
  const _ViewportHost({
    required this.owner,
    required this.initialSource,
    required this.initialSuite,
    super.key,
  });

  final ContinuousPlayController owner;
  final InteractionSource initialSource;
  final InteractionSuite initialSuite;

  @override
  State<_ViewportHost> createState() => _ViewportHostState();
}

class _ViewportHostState extends State<_ViewportHost> {
  late InteractionSource opening = widget.initialSource;
  late InteractionSuite suite = widget.initialSuite;
  bool light = false;
  bool reduce = false;

  void present({
    InteractionSource? source,
    InteractionSuite? nextSuite,
    bool? nextLight,
    bool? nextReduce,
  }) {
    setState(() {
      opening = source ?? opening;
      suite = nextSuite ?? suite;
      light = nextLight ?? light;
      reduce = nextReduce ?? reduce;
    });
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => starBridgeInitialReadViewport(
        context,
        source: opening,
        child: ContinuousPlayConnectedPanel(
          key: _panelKey,
          controller: widget.owner,
        ),
      ),
    ),
    suite,
    light: light,
    reduce: reduce,
  );
}

Future<void> _twoFrames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadFonts);
  for (final initialSuite in InteractionSuite.values) {
    for (final initialSource in [
      InteractionSource.pointer,
      InteractionSource.keyboard,
    ]) {
      testWidgets(
        '$initialSuite Play $initialSource initial-read origin stays phase-local while presentation follows live preferences',
        (t) async {
          size(t, const Size(1000, 850));
          final port = HeldPlay();
          final owner = ContinuousPlayController(port);
          final host = GlobalKey<_ViewportHostState>();
          final originIsStatic = initialSource == InteractionSource.keyboard;
          final oppositeSource = originIsStatic
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          final switchedSuite =
              InteractionSuite.values[(initialSuite.index + 1) %
                  InteractionSuite.values.length];
          try {
            await t.pumpWidget(
              _ViewportHost(
                key: host,
                owner: owner,
                initialSource: initialSource,
                initialSuite: initialSuite,
              ),
            );
            await _twoFrames(t);
            final panel = find.byKey(_panelKey);
            expect(panel, findsOneWidget);
            final originalState = t.state(panel);
            final originalElement = t.element(panel);
            final originalRead = port.gate.pending;

            final frames = find.descendant(
              of: panel,
              matching: find.byType(SuiteBusyFrame),
            );
            final labels = find.descendant(
              of: panel,
              matching: find.byType(SuiteBusyLabel),
            );

            void checkPending({
              required InteractionSuite suite,
              required Brightness brightness,
              required bool globalReduce,
              required String checkpoint,
            }) {
              final effectiveStatic = originIsStatic || globalReduce;
              expect(port.gate.reads, 1, reason: checkpoint);
              expect(port.writes, 0, reason: checkpoint);
              expect(port.gate.pending, same(originalRead), reason: checkpoint);
              expect(originalRead.isCompleted, isFalse, reason: checkpoint);
              expect(owner.value.settings, isNull, reason: checkpoint);
              expect(owner.value.busy, isTrue, reason: checkpoint);
              expect(owner.value.failed, isFalse, reason: checkpoint);
              expect(t.state(panel), same(originalState), reason: checkpoint);
              expect(
                t.element(panel),
                same(originalElement),
                reason: checkpoint,
              );
              expect(
                t.widget<ContinuousPlayConnectedPanel>(panel).controller,
                same(owner),
                reason: checkpoint,
              );
              expect(
                find.byKey(const Key('continuous-play-loading')),
                findsOneWidget,
                reason: checkpoint,
              );
              expect(
                find.byKey(const Key('notification-play-enabled')),
                findsNothing,
                reason: checkpoint,
              );
              expect(frames, findsOneWidget, reason: checkpoint);
              expect(labels, findsOneWidget, reason: checkpoint);
              expect(
                t.widget<SuiteBusyFrame>(frames).busy,
                isTrue,
                reason: checkpoint,
              );
              final live = resolveStarBridgeInteraction(t.element(panel));
              expect(live.suite, suite, reason: checkpoint);
              expect(live.palette.brightness, brightness, reason: checkpoint);
              for (final element in [
                ...frames.evaluate(),
                ...labels.evaluate(),
              ]) {
                final data = InteractionScope.of(element);
                expect(data.suite, suite, reason: checkpoint);
                expect(
                  data.palette.accent,
                  live.palette.accent,
                  reason: checkpoint,
                );
                expect(
                  data.palette.surface,
                  live.palette.surface,
                  reason: checkpoint,
                );
                expect(
                  data.palette.textPrimary,
                  live.palette.textPrimary,
                  reason: checkpoint,
                );
                expect(data.palette.brightness, brightness, reason: checkpoint);
                expect(data.reduceMotion, effectiveStatic, reason: checkpoint);
                expect(data.animates, !effectiveStatic, reason: checkpoint);
                // Inspect only the real local waiting surfaces. Other widgets
                // may legitimately keep tickers; global idleness is not a
                // contract of this origin/presentation regression.
                expect(
                  TickerMode.valuesOf(element).enabled,
                  isTrue,
                  reason: checkpoint,
                );
              }
              expect(t.takeException(), isNull, reason: checkpoint);
            }

            checkPending(
              suite: initialSuite,
              brightness: Brightness.dark,
              globalReduce: false,
              checkpoint:
                  'One genuine held initial read with its original source.',
            );

            // Defensive adjacent boundary, not a claimed real-user incident:
            // change only the public inherited opening fact while preserving
            // the same Panel Element/State, owner and outstanding read Future.
            // A parent rebuild is not a new request or a new phase.
            host.currentState!.present(source: oppositeSource);
            await _twoFrames(t);
            checkPending(
              suite: initialSuite,
              brightness: Brightness.dark,
              globalReduce: false,
              checkpoint: 'The opposite parent opening fact cannot relabel this existing read.',
            );

            // Freeze origin evidence only, never the whole presentation data.
            host.currentState!.present(
              nextSuite: switchedSuite,
              nextLight: true,
            );
            await _twoFrames(t);
            checkPending(
              suite: switchedSuite,
              brightness: Brightness.light,
              globalReduce: false,
              checkpoint: 'The original held read adopts the current suite and light palette.',
            );

            host.currentState!.present(nextReduce: true);
            await _twoFrames(t);
            checkPending(
              suite: switchedSuite,
              brightness: Brightness.light,
              globalReduce: true,
              checkpoint:
                  'Live reduced motion makes either original source static.',
            );

            host.currentState!.present(nextReduce: false);
            await _twoFrames(t);
            checkPending(
              suite: switchedSuite,
              brightness: Brightness.light,
              globalReduce: false,
              checkpoint: 'Removing reduced motion restores the original phase source policy.',
            );

            port.gate.finish();
            await _twoFrames(t);
            expect(owner.value.settings, same(port.gate.value));
            expect(owner.value.settings!.revision, 0);
            expect(owner.value.settings!.enabled, isTrue);
            expect(owner.value.settings!.firstMinutes, 120);
            expect(owner.value.settings!.repeatMinutes, 60);
            expect(owner.value.busy, isFalse);
            expect(owner.value.failed, isFalse);
            expect(port.gate.reads, 1);
            expect(port.writes, 0);
            expect(t.state(panel), same(originalState));
            expect(
              t.widget<ContinuousPlayConnectedPanel>(panel).controller,
              same(owner),
            );
            expect(t.takeException(), isNull);
          } finally {
            // A failing checkpoint must not leave the real owner's read held.
            port.gate.finish();
            await _twoFrames(t);
            await t.pumpWidget(const SizedBox.shrink());
            owner.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
