import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/notifications/starbridge_notification_toast.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/app/composition/local_notification_listener.dart';

import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ac_test.dart' show LiveState;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const toastKey = Key('starbridge-notification-toast');
const closeKey = Key('starbridge-notification-close');
const testKey = Key('notification-test-button');
final toast = find.byKey(toastKey);

class Caller extends StatefulWidget {
  const Caller({super.key});
  @override
  State<Caller> createState() => CallerState();
}

class CallerState extends State<Caller> {
  late BuildContext caller;
  bool reduce = false, visible = true;
  void change(VoidCallback callback) => setState(callback);
  VoidCallback show(
    String name, {
    Alignment alignment = Alignment.topRight,
    InteractionSource source = InteractionSource.pointer,
    Duration duration = const Duration(seconds: 4),
  }) => showStarBridgeNotificationToast(
    caller,
    alignment: alignment,
    title: name,
    message: '有新的消息。请前往通知页查看。',
    source: source,
    duration: duration,
  );
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: visible
        ? Builder(
            builder: (context) {
              caller = context;
              return const Text('通知来源');
            },
          )
        : const Text('来源离开'),
  );
}

Future<(CallerState, LiveState)> host(
  WidgetTester t,
  InteractionSuite suite, {
  GlobalKey? capture,
}) async {
  final key = GlobalKey<CallerState>();
  final live = await mount(t, Caller(key: key), suite, capture: capture);
  return (key.currentState!, live);
}

SuiteSurfaceTransition transition(WidgetTester t) =>
    t.widget<SuiteSurfaceTransition>(
      find
          .byWidgetPredicate(
            (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.toast,
          )
          .last,
    );
AnimationController animation(WidgetTester t) =>
    transition(t).animation as AnimationController;
Future<void> frame(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> clean(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
}

Future<void> activate(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key).last;
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final icon = find
        .descendant(of: target, matching: find.byType(StarBridgeIcon))
        .first;
    Focus.of(t.element(icon)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in InteractionSource.values) {
      testWidgets(
        '$suite source $source preserves feedback and four-second timer',
        (t) async {
          final (caller, _) = await host(t, suite);
          caller.show('Source', source: source);
          await frame(t);
          final c = animation(t);
          expect(c.isAnimating, source != InteractionSource.keyboard);
          if (source == InteractionSource.keyboard) expect(c.value, 1);
          await t.pump(const Duration(milliseconds: 3999));
          expect(toast, findsOneWidget);
          await t.pump(const Duration(milliseconds: 1));
          if (source != InteractionSource.keyboard) {
            expect(c.status, AnimationStatus.reverse);
            await t.pump();
            await t.pump(const Duration(milliseconds: 350));
          } else {
            await t.pump();
          }
          expect(toast, findsNothing);
          await clean(t);
        },
      );
    }
    for (final phase in ['enter', 'settled', 'exit']) {
      testWidgets(
        '$suite local reduced motion during $phase settles within two frames',
        (t) async {
          final (caller, _) = await host(t, suite);
          caller.show('Live');
          await frame(t);
          await t.pump(Duration(milliseconds: phase == 'enter' ? 40 : 400));
          final c = animation(t);
          if (phase == 'exit') {
            await activate(t, closeKey, 'pointer');
            await t.pump();
            await t.pump(const Duration(milliseconds: 20));
            expect(c.status, AnimationStatus.reverse);
          }
          caller.change(() => caller.reduce = true);
          await frame(t);
          expect(c.isAnimating, false);
          if (phase == 'exit') {
            expect(toast, findsNothing);
          } else {
            expect(c.value, 1);
            expect(toast, findsOneWidget);
            caller.change(() => caller.reduce = false);
            await frame(t);
            expect(c.value, 1, reason: 'Do not replay entrance');
            await activate(t, closeKey, 'pointer');
            await t.pump();
            expect(c.status, AnimationStatus.reverse);
            await t.pump(const Duration(milliseconds: 350));
            expect(toast, findsNothing);
          }
          await clean(t);
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual $source close preserves exit and blocks old controls',
        (t) async {
          final handle = t.ensureSemantics();
          final (caller, _) = await host(t, suite);
          caller.show('Close');
          await frame(t);
          await t.pump(const Duration(milliseconds: 400));
          final c = animation(t);
          await activate(t, closeKey, source);
          await t.pump();
          if (source == 'pointer') {
            expect(c.status, AnimationStatus.reverse);
            expect(find.text('Close'), findsOneWidget);
            expect(
              find.ancestor(
                of: toast,
                matching: find.byWidgetPredicate(
                  (w) => w is IgnorePointer && w.ignoring,
                ),
              ),
              findsWidgets,
            );
            expect(
              find.ancestor(
                of: toast,
                matching: find.byWidgetPredicate(
                  (w) => w is ExcludeFocus && w.excluding,
                ),
              ),
              findsWidgets,
            );
            expect(
              find.ancestor(
                of: toast,
                matching: find.byWidgetPredicate(
                  (w) => w is ExcludeSemantics && w.excluding,
                ),
              ),
              findsWidgets,
            );
            await t.pump(const Duration(milliseconds: 30));
            expect(c.value, inExclusiveRange(0, 1));
            await t.pump(const Duration(milliseconds: 350));
          }
          expect(toast, findsNothing);
          await clean(t);
          handle.dispose();
        },
      );
    }
    testWidgets('$suite theme and suite updates do not reset timer', (t) async {
      final (caller, live) = await host(t, suite);
      caller.show('Timer', duration: const Duration(seconds: 1));
      await frame(t);
      await t.pump(const Duration(milliseconds: 400));
      final c = animation(t);
      live.change(() {
        live.light = true;
        live.suite = suite == InteractionSuite.scan
            ? InteractionSuite.glow
            : InteractionSuite.scan;
      });
      await frame(t);
      final data = InteractionScope.of(
        t.element(find.byType(SuiteSurfaceTransition)),
      );
      expect(data.suite, live.suite);
      expect(data.palette.brightness, Brightness.light);
      expect(transition(t).tone, data.palette.success);
      expect(c.value, 1);
      await t.pump(const Duration(milliseconds: 599));
      expect(toast, findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      expect(c.status, AnimationStatus.reverse);
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(toast, findsNothing);
      await clean(t);
    });
    testWidgets(
      '$suite cancel idempotence and old timer cannot remove replacement',
      (t) async {
        final (caller, live) = await host(t, suite);
        final old = caller.show('Old');
        await frame(t);
        await t.pump(const Duration(milliseconds: 200));
        old();
        old();
        final next = caller.show('New');
        await frame(t);
        await t.pump(const Duration(milliseconds: 3800));
        old();
        await t.pump();
        expect(find.text('Old'), findsNothing);
        expect(find.text('New'), findsOneWidget);
        live.change(() => live.reduce = true);
        await frame(t);
        expect(animation(t).isAnimating, false);
        next();
        next();
        await t.pump();
        await t.pump(const Duration(seconds: 5));
        expect(toast, findsNothing);
        expect(t.takeException(), isNull);
        await clean(t);
      },
    );
    testWidgets('$suite source leaving retains root live settings', (t) async {
      final (caller, live) = await host(t, suite);
      final cancel = caller.show('Leave');
      await frame(t);
      caller.change(() => caller.visible = false);
      await t.pump();
      expect(toast, findsOneWidget);
      live.change(() => live.reduce = true);
      await frame(t);
      expect(animation(t).isAnimating, false);
      cancel();
      await t.pump();
      await clean(t);
      expect(t.takeException(), isNull);
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite actual settings preview $source has zero saves', (
        t,
      ) async {
        final handle = t.ensureSemantics();
        var saves = 0;
        await mount(
          t,
          SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: InMemoryNotificationSettingsAdapter.forReview()
                  .current
                  .settings!,
              enabled: true,
              onSave: (_) async {
                saves++;
                return true;
              },
            ),
          ),
          suite,
        );
        await activate(t, testKey, source);
        await frame(t);
        expect(toast, findsOneWidget);
        expect(animation(t).isAnimating, source == 'pointer');
        expect(saves, 0);
        await t.pump(const Duration(milliseconds: 400));
        await activate(t, closeKey, 'reader');
        await t.pump();
        expect(toast, findsNothing);
        expect(saves, 0);
        await clean(t);
        handle.dispose();
      });
    }
    testWidgets('$suite disabled preview remains non-actionable', (t) async {
      final handle = t.ensureSemantics();
      var saves = 0;
      await mount(
        t,
        SingleChildScrollView(
          child: NotificationChannelPanel(
            settings: InMemoryNotificationSettingsAdapter.forReview()
                .current
                .settings!,
            enabled: false,
            onSave: (_) async {
              saves++;
              return true;
            },
          ),
        ),
        suite,
      );
      final button = find.byKey(testKey);
      await t.ensureVisible(button);
      expect(
        t
            .getSemantics(button)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        false,
      );
      await t.tap(button);
      await t.pump();
      expect(toast, findsNothing);
      expect(saves, 0);
      await clean(t);
      handle.dispose();
    });
    testWidgets(
      '$suite real listener replace revision invalidation and disposal',
      (t) async {
        final adapter = InMemoryNotificationSettingsAdapter.forReview();
        final module = createNotificationSettingsModule(adapter);
        addTearDown(module.dispose);
        await module.initialize();
        final events = StreamController<LocalRoomReminder?>(sync: true);
        addTearDown(events.close);
        final live = await mount(
          t,
          LocalNotificationListener(
            events: events.stream,
            settings: module,
            child: const Text('Listener'),
          ),
          suite,
        );
        events.add(const LocalRoomReminder(11, 1, 0));
        await frame(t);
        expect(animation(t).isAnimating, true);
        final old = animation(t);
        events.add(const LocalRoomReminder(11, 2, 1));
        await frame(t);
        expect(toast, findsOneWidget);
        expect(animation(t), isNot(same(old)));
        events.add(const LocalRoomReminder(10, 5, 0));
        await t.pump();
        expect(toast, findsNothing);
        events.add(const LocalRoomReminder(11, 1, 0));
        await frame(t);
        expect(toast, findsOneWidget);
        live.change(() => live.visible = false);
        await frame(t);
        expect(toast, findsNothing);
        events.add(const LocalRoomReminder(11, 7, 0));
        await t.pump(const Duration(seconds: 5));
        expect(toast, findsNothing);
        expect(adapter.current.revision, 11);
        await clean(t);
      },
    );
    for (final alignment in [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ]) {
      testWidgets('$suite $alignment fits narrow safe viewport', (t) async {
        final (caller, _) = await host(t, suite);
        t.view.physicalSize = const Size(320, 900);
        t.view.padding = const FakeViewPadding(
          left: 12,
          right: 18,
          top: 20,
          bottom: 24,
        );
        addTearDown(t.view.resetPadding);
        await t.pump();
        final cancel = caller.show('Position', alignment: alignment);
        await frame(t);
        await t.pump(const Duration(milliseconds: 400));
        final rect = t.getRect(toast);
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(302));
        expect(rect.top, greaterThanOrEqualTo(20));
        expect(rect.bottom, lessThanOrEqualTo(876));
        expect(transition(t).toastFromLeft, alignment.x < 0);
        expect(transition(t).alignment, alignment);
        expect(t.takeException(), isNull);
        cancel();
        await t.pump();
        await clean(t);
      });
    }
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite notification frames review', (t) async {
      final capture = GlobalKey();
      final (caller, _) = await host(t, suite, capture: capture);
      final cancel = caller.show('新的房间消息');
      await frame(t);
      await t.pump(const Duration(milliseconds: 80));
      Future<void> save(String phase) async {
        await t.pump();
        await t.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3ax');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await save('entry');
      await t.pump(const Duration(milliseconds: 400));
      await save('settled');
      await activate(t, closeKey, 'pointer');
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      expect(animation(t).value, inExclusiveRange(0, 1));
      await save('exit');
      cancel();
      await t.pump();
      await clean(t);
    });
  }
}
