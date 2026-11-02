import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_monitor_panel.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_motion_controls.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';

import 'interaction_batch3dm_test.dart' show act;
import 'interaction_batch3dm_visual_test.dart' show capture;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import 'interaction_batch3i_test.dart' show scopedApp;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_test.dart' as original;

class Live extends StatefulWidget {
  const Live(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Live> createState() => LiveState();
}

class LiveState extends State<Live> {
  bool reduce = false;
  int calls = 0;
  void stop() => setState(() => reduce = true);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: ExecHangarMotionButton(
        OutlinedButton(
          key: const Key('live-action'),
          onPressed: () => calls++,
          child: const Text('保存提醒设置'),
        ),
      ),
    ),
    widget.suite,
    reduce: reduce,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source monitor commands keep opaque enum, duration, only-next and gates',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(1000, 1300));
            final commands =
                <
                  ({
                    ExecHangarAction action,
                    int minutes,
                    bool next,
                    InteractionSource source,
                  })
                >[];
            final experience = original.ExperiencePort();
            final now = original.origin;
            ExecHangarPlan plan({String state = 'muted', bool active = true}) =>
                ExecHangarPlan(
                  active: active,
                  state: state,
                  onlyNext: false,
                  endsAt: now.add(const Duration(hours: 1)),
                  startedAt: now,
                  mutedBoundary: now.add(const Duration(minutes: 15)),
                  outside: ExecHangarNotice(
                    now.add(const Duration(hours: 2)),
                    now.add(const Duration(hours: 2)),
                    true,
                  ),
                );
            Widget host(
              ExecHangarPlan p, {
              bool busy = false,
              bool canStart = true,
            }) => scopedApp(
              SingleChildScrollView(
                child: ExecHangarMonitorPanel(
                  snapshot: original.sample(plan: p),
                  now: now,
                  busy: busy,
                  canStart: canStart,
                  experience: experience,
                  onCommand: (a, m, n) => commands.add((
                    action: a,
                    minutes: m,
                    next: n,
                    source: captureStarBridgeActivationSource()(),
                  )),
                ),
              ),
              suite,
            );
            await t.pumpWidget(host(plan()));
            await t.pumpAndSettle();
            Future<void> action(String key, String copy) async {
              final label = AppStrings.of(
                t.element(find.byType(ExecHangarMonitorPanel)),
              ).text('execHangar.$copy');
              await act(t, find.byKey(Key(key)), source, label);
              await t.pumpAndSettle();
            }

            await action('exec-restore', 'restoreEvent');
            await action('exec-add-hour', 'addHour');
            await action('exec-stop', 'stopMonitor');
            await action('exec-adjust', 'adjustMonitor');
            await t.ensureVisible(find.byKey(const Key('exec-only-next')));
            await t.tap(find.byKey(const Key('exec-only-next')));
            await t.pumpAndSettle();
            await action('exec-start', 'restartMonitor');
            expect(commands.map((c) => c.action), [
              ExecHangarAction.restore,
              ExecHangarAction.addHour,
              ExecHangarAction.stop,
              ExecHangarAction.start,
            ]);
            expect(commands.last.minutes, 60);
            expect(commands.last.next, isTrue);
            expect(
              commands.every(
                (c) =>
                    c.source ==
                    (source == 'pointer'
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard),
              ),
              isTrue,
            );
            await action('exec-test', 'testReminder');
            expect(experience.tests, 1);
            expect(experience.saves, 0);
            expect(experience.starts, 0);
            await t.pumpWidget(host(plan(state: 'noEvent'), canStart: false));
            await t.pumpAndSettle();
            final extend = find.ancestor(
              of: find.byKey(const Key('exec-extend')),
              matching: find.byType(StarBridgeActionButton),
            );
            final restore = find.ancestor(
              of: find.byKey(const Key('exec-restore')),
              matching: find.byType(StarBridgeActionButton),
            );
            expect(
              t.widget<StarBridgeActionButton>(extend).onActivate,
              isNotNull,
              reason: 'original extend is not gated on canStart',
            );
            expect(
              t.widget<StarBridgeActionButton>(restore).onActivate,
              isNull,
            );
            await action('exec-extend', 'extendOpen');
            expect(commands.last.action, ExecHangarAction.extend);
            expect(commands.last.minutes, 0);
            expect(commands.last.next, isFalse);
            await t.pumpWidget(host(plan(state: 'noEvent'), busy: true));
            await t.pumpAndSettle();
            for (final button in t.widgetList<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            )) {
              expect(button.onActivate, isNull);
            }
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite pointer press is visible, cancel never fires, live reduce settles',
      (t) async {
        size(t, const Size(500, 400));
        final key = GlobalKey<LiveState>(), frame = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: Live(suite, key: key),
          ),
        );
        await t.pumpAndSettle();
        final image = find.byKey(frame),
            target = find.byKey(const Key('live-action'));
        final idle = await pixels(t, image);
        final gesture = await t.startGesture(t.getCenter(target));
        await t.pump(const Duration(milliseconds: 60));
        expect(
          await pixels(t, image),
          isNot(orderedEquals(idle)),
          reason: 'active press must retain perceptible feedback',
        );
        expect(key.currentState!.calls, 0);
        await capture(t, frame, '${suite.name}-pointer-down');
        await gesture.cancel();
        await t.pumpAndSettle();
        expect(key.currentState!.calls, 0);
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 35));
        expect(key.currentState!.calls, 1);
        key.currentState!.stop();
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        final still = await pixels(t, image);
        await t.pump(const Duration(milliseconds: 500));
        expect(await pixels(t, image), orderedEquals(still));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
