import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_play_reminders.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';

import '../../features/settings/notification_audio_test.dart' show AudioFake;
import '../../features/settings/notification_sources_test.dart' as sources;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3az_test.dart' show taps;
import 'interaction_batch3b_test.dart' show exposedNodes;

class ReminderPort implements ContinuousPlayPort {
  var value = const ContinuousPlayValue(
    enabled: true,
    firstMinutes: 120,
    repeatMinutes: 120,
    revision: 1,
  );
  int reads = 0, writes = 0;
  bool failRead = false;
  Completer<ContinuousPlayValue>? held;
  @override
  Future<ContinuousPlayValue> read() async {
    reads++;
    if (failRead) throw StateError('unavailable');
    return value;
  }

  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue next) async {
    writes++;
    return held == null ? value = next : held!.future;
  }
}

class ReloadSources extends sources.Fake {
  Completer<NotificationSourcesValue>? held;
  @override
  Future<NotificationSourcesValue> read() async {
    reads++;
    return held == null ? value : held!.future;
  }
}

StarBridgeActionButton action(WidgetTester t, String key) => t.widget(
  find
      .ancestor(
        of: find.byKey(Key(key)),
        matching: find.byType(StarBridgeActionButton),
      )
      .first,
);
FocusNode sliderFocus(WidgetTester t) {
  final raw = t.widget(find.byKey(const Key('slider')));
  return raw is Slider ? raw.focusNode! : (raw as SuiteSlider).focusNode!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite shared slider cancellation performs no end command', (
      t,
    ) async {
      var value = .4, ends = 0, cancels = 0;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, s) => StarBridgeSlider(
            controlKey: const Key('slider'),
            value: value,
            onChanged: (v) => s(() => value = v),
            onChangeEnd: (_) => ends++,
            onChangeCancel: () => cancels++,
          ),
        ),
        suite,
      );
      final rect = t.getRect(find.byKey(const Key('slider')));
      final gesture = await t.startGesture(rect.center);
      await gesture.moveBy(const Offset(45, 0));
      await t.pump();
      await gesture.cancel();
      await t.pumpAndSettle();
      expect(ends, 0);
      expect(cancels, 1);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite adaptive audio switch has one real reader target', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final port = AudioFake()
        ..value = const AudioPreferences(1, true, .65, true);
      final audio = NotificationAudioController(port);
      await audio.refresh();
      addTearDown(audio.dispose);
      await mount(t, NotificationAudioPanel(controller: audio), suite);
      final root = find.byType(StarBridgeSwitch);
      final nodes = taps(t.getSemantics(root));
      expect(nodes, hasLength(1));
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        nodes.single.id,
        SemanticsAction.tap,
      );
      await t.pumpAndSettle();
      expect(port.writes, 1);
      expect(audio.value!.enabled, false);
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    testWidgets('$suite shared slider pointer keyboard reader and disabled', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      var value = .4, enabled = true;
      late StateSetter update;
      final changed = <InteractionSource>[], ended = <double>[];
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return SizedBox(
              width: 500,
              child: StarBridgeSlider(
                controlKey: const Key('slider'),
                value: value,
                divisions: 100,
                semanticLabel: 'Volume',
                valueLabel: (v) => '${(v * 100).round()}%',
                onChanged: enabled
                    ? (v) {
                        changed.add(currentStarBridgeActivationSource);
                        setState(() => value = v);
                      }
                    : null,
                onChangeEnd: ended.add,
              ),
            );
          },
        ),
        suite,
      );
      final target = find.byKey(const Key('slider'));
      final rect = t.getRect(target);
      final gesture = await t.startGesture(
        Offset(rect.right - 50, rect.center.dy),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(ended.single, value);
      expect(changed.single, InteractionSource.pointer);
      sliderFocus(t).requestFocus();
      await t.pumpAndSettle();
      final before = value;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(value, closeTo(before + .01, .0001));
      expect(changed.last, InteractionSource.keyboard);
      final node = exposedNodes(t).singleWhere(
        (node) =>
            node.getSemanticsData().flagsCollection.isSlider &&
            node.getSemanticsData().label == 'Volume',
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.decrease,
      );
      await t.pumpAndSettle();
      expect(value, closeTo(before, .0001));
      expect(changed.last, InteractionSource.keyboard);
      update(() => enabled = false);
      await t.pump();
      expect(
        exposedNodes(t)
            .singleWhere(
              (node) =>
                  node.getSemanticsData().flagsCollection.isSlider &&
                  node.getSemanticsData().label == 'Volume',
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.increase),
        false,
      );
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    testWidgets(
      '$suite actual audio slider stages zero writes then confirms retry',
      (t) async {
        final port = AudioFake()
          ..value = const AudioPreferences(1, true, .65, true);
        final audio = NotificationAudioController(port);
        await audio.refresh();
        addTearDown(audio.dispose);
        late PrivacyPageDrafts group;
        await mount(
          t,
          NotificationEditorFrame(
            owner: Object(),
            child: Builder(
              builder: (context) {
                group = NotificationDraftScope.of(context)!;
                return SingleChildScrollView(
                  child: NotificationAudioPanel(controller: audio),
                );
              },
            ),
          ),
          suite,
        );
        final target = find.byKey(const Key('audio-volume')),
            rect = t.getRect(find.byKey(const Key('audio-volume')));
        final gesture = await t.startGesture(
          Offset(rect.right - 35, rect.center.dy),
        );
        await gesture.up();
        await t.pumpAndSettle();
        final desired = group.value('notification-audio', (true, .65));
        expect(desired.$2, greaterThan(.8));
        expect(port.writes, 0);
        await t.tap(find.byKey(const Key('audio-preview')));
        await t.pumpAndSettle();
        expect(port.plays, 1);
        expect(audio.value!.volume, .65);
        port.fail = true;
        await t.tap(find.byKey(const Key('notification-save')));
        await t.pumpAndSettle();
        expect(group.failed, true);
        expect(group.dirty, true);
        expect(audio.value!.volume, .65);
        port.fail = false;
        await t.tap(find.byKey(const Key('notification-save')));
        await t.pumpAndSettle();
        expect(group.dirty, false);
        expect(audio.value!.volume, desired.$2);
        expect(port.writes, 2);
        expect(target, findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite held audio preview reduces and replacement fences cached play',
      (t) async {
        final aPort = AudioFake()
          ..value = const AudioPreferences(1, true, .65, true)
          ..delayedPreview = Completer<String>();
        final bPort = AudioFake()
          ..value = const AudioPreferences(1, true, .3, true);
        final a = NotificationAudioController(aPort),
            b = NotificationAudioController(bPort);
        await a.refresh();
        await b.refresh();
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        var current = a;
        late StateSetter update;
        final live = await mount(
          t,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return NotificationAudioPanel(controller: current);
            },
          ),
          suite,
        );
        final old = action(t, 'audio-preview').onActivate!;
        await t.tap(find.byKey(const Key('audio-preview')));
        await t.pump();
        old(InteractionSource.pointer);
        await t.pump();
        expect(aPort.plays, 1);
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        update(() => current = b);
        await t.pump();
        old(InteractionSource.pointer);
        aPort.delayedPreview!.complete('played');
        await t.pumpAndSettle();
        expect(a.status, 'stopped');
        expect(b.status, isNull);
        expect(bPort.plays, 0);
        expect(find.text('30%'), findsOneWidget);
        await t.tap(find.byKey(const Key('audio-preview')));
        await t.pumpAndSettle();
        expect(bPort.plays, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite reminder direct save holds projection then reads confirmation',
      (t) async {
        final port = ReminderPort()..held = Completer<ContinuousPlayValue>();
        final controller = ContinuousPlayController(port);
        await controller.refresh();
        addTearDown(controller.dispose);
        final live = await mount(
          t,
          ContinuousPlayConnectedPanel(controller: controller),
          suite,
        );
        await t.tapAt(
          t.getCenter(find.byKey(const Key('notification-play-enabled'))),
        );
        await t.pump();
        expect(port.writes, 1);
        expect(controller.value.settings!.enabled, true);
        expect(find.byKey(const Key('continuous-play-busy')), findsOneWidget);
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        port.held!.complete(
          const ContinuousPlayValue(
            enabled: false,
            firstMinutes: 90,
            repeatMinutes: 60,
            revision: 2,
          ),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<ContinuousPlayReminderPanel>(
                find.byType(ContinuousPlayReminderPanel),
              )
              .settings
              .continuousPlay
              .firstReminderMinutes,
          90,
        );
        expect(controller.value.settings!.enabled, false);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite reminder failed reload and cached old save retire', (
      t,
    ) async {
      final p = ReminderPort(), q = ReminderPort();
      final a = ContinuousPlayController(p), b = ContinuousPlayController(q);
      await a.refresh();
      await b.refresh();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var current = a;
      late StateSetter update;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, s) {
            update = s;
            return ContinuousPlayConnectedPanel(controller: current);
          },
        ),
        suite,
      );
      final old = t.widget<ContinuousPlayReminderPanel>(
        find.byType(ContinuousPlayReminderPanel),
      );
      p.failRead = true;
      await a.refresh();
      await t.pumpAndSettle();
      final reload = action(t, 'continuous-play-reload').onActivate!;
      update(() => current = b);
      await t.pump();
      expect(
        await old.onSave(
          old.settings.copyWith(
            continuousPlay: old.settings.continuousPlay.copyWith(
              enabled: false,
            ),
          ),
        ),
        false,
      );
      reload(InteractionSource.keyboard);
      await t.pumpAndSettle();
      expect(q.reads, 1);
      expect(q.writes, 0);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite uncertain source discard keeps known rows while reloading',
      (t) async {
        final port = ReloadSources()..fail = true;
        late PrivacyPageDrafts group;
        await mount(
          t,
          NotificationEditorFrame(
            owner: Object(),
            child: Builder(
              builder: (context) {
                group = NotificationDraftScope.of(context)!;
                return SingleChildScrollView(
                  child: NotificationSourcesConnectedPanel(port: port),
                );
              },
            ),
          ),
          suite,
        );
        final row = t.widget<NotificationSourceRuleRow>(
          find.byType(NotificationSourceRuleRow).first,
        );
        await row.onChanged(NotificationSourceMode.doNotDisturb);
        await t.pump();
        await t.tap(find.byKey(const Key('notification-save')));
        await t.pumpAndSettle();
        expect(group.failed, true);
        port.held = Completer<NotificationSourcesValue>();
        await t.tap(find.byKey(const Key('notification-discard')));
        await t.pump();
        await t.pump();
        expect(find.byType(NotificationSourceRuleRow), findsWidgets);
        for (final r in t.widgetList<NotificationSourceRuleRow>(
          find.byType(NotificationSourceRuleRow),
        )) {
          expect(r.enabled, false);
        }
        port.held!.complete(port.value);
        await t.pumpAndSettle();
        expect(group.dirty, false);
        expect(port.writes, 1);
        await t.pumpWidget(const SizedBox());
        port.dispose();
      },
    );
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite audio task review frames', (t) async {
      final capture = GlobalKey();
      final port = AudioFake()
        ..value = const AudioPreferences(1, true, .65, true)
        ..delayedPreview = Completer<String>();
      final audio = NotificationAudioController(port);
      await audio.refresh();
      addTearDown(audio.dispose);
      final live = await mount(
        t,
        SingleChildScrollView(child: NotificationAudioPanel(controller: audio)),
        suite,
        width: 820,
        capture: capture,
      );
      Future<void> save(String phase) async {
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3ba');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await t.tap(find.byKey(const Key('audio-preview')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await save('busy');
      port.delayedPreview!.completeError(const AudioFailure('output'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      await save('failure');
      live.change(() => live.light = true);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await save('light');
      await t.pumpWidget(const SizedBox());
    });
  }
}
