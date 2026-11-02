import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart'
    show act, exposedNodes, loadFonts, scopedApp, size;
import 'interaction_batch3dw_test.dart'
    show NotificationMotionPort, notificationMotionFrames;

/// A controlled audio transport. It never reaches native playback or storage.
class AudioMotionPort implements NotificationAudioPort {
  AudioPreferences value = const AudioPreferences(
    3,
    false,
    .65,
    true,
    doNotDisturb: true,
  );
  final saving = Completer<AudioPreferences>();
  Completer<AudioPreferences>? pendingRead;
  Completer<AudioPreferences>? pendingSave;
  final saves = <(AudioPreferences, bool, double, bool?, InteractionSource)>[];
  int reads = 0, previews = 0, stops = 0;

  @override
  Future<AudioPreferences> read() {
    reads++;
    final gate = pendingRead;
    pendingRead = null;
    return gate?.future ?? Future.value(value);
  }

  @override
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  }) {
    saves.add((
      current,
      enabled,
      volume,
      doNotDisturb,
      currentStarBridgeActivationSource,
    ));
    final gate = pendingSave;
    pendingSave = null;
    return (gate ?? saving).future;
  }

  @override
  Future<String> preview() async {
    previews++;
    return 'played';
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

/// Uses the page's one real editor queue and its one real audio controller.
/// No native audio service is involved; pending transport receipts are explicit.
class AudioMotionScenario {
  AudioMotionScenario(this.suite);
  final InteractionSuite suite;
  final notifications = NotificationMotionPort();
  final port = AudioMotionPort();
  late final module = createNotificationSettingsModule(notifications);
  late final audio = NotificationAudioController(port);
  final _gates = <Completer<AudioPreferences>>[];

  Widget app({
    bool reduce = false,
    bool light = false,
    InteractionSuite? using,
  }) => scopedApp(
    SizedBox.expand(
      child: NotificationSettingsPage(module: module, audio: audio),
    ),
    using ?? suite,
    reduce: reduce,
    light: light,
  );

  Future<void> mount(WidgetTester t) async {
    size(t, const Size(1000, 1100));
    await module.initialize();
    await audio.refresh();
    await t.pumpWidget(app());
    await notificationMotionFrames(t);
  }

  Completer<AudioPreferences> holdSave() {
    final gate = Completer<AudioPreferences>();
    _gates.add(gate);
    port.pendingSave = gate;
    return gate;
  }

  Completer<AudioPreferences> holdRead() {
    final gate = Completer<AudioPreferences>();
    _gates.add(gate);
    port.pendingRead = gate;
    return gate;
  }

  AudioPreferences receipt({bool? enabled, double? volume}) => AudioPreferences(
    audio.value!.revision + 1,
    enabled ?? port.saves.last.$2,
    volume ?? port.saves.last.$3,
    audio.value!.previewAvailable,
    doNotDisturb: audio.value!.doNotDisturb,
  );

  Future<void> close(WidgetTester t) async {
    for (final gate in _gates) {
      if (!gate.isCompleted) {
        gate.complete(port.value);
      }
    }
    if (!port.saving.isCompleted) {
      port.saving.complete(port.value);
    }
    await notificationMotionFrames(t, count: 2);
    await t.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    module.dispose();
    await t.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
  }
}

Finder audioMotionSwitch() => find
    .ancestor(
      of: find.byKey(const Key('audio-enabled')),
      matching: find.byType(StarBridgeSwitch),
    )
    .first;

PrivacyPageDrafts audioMotionDrafts(WidgetTester t) =>
    NotificationDraftScope.of(t.element(find.byType(NotificationAudioPanel)))!;

Future<void> audioMotionStage(WidgetTester t, String source) async {
  final outer = audioMotionSwitch();
  await t.ensureVisible(outer);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(outer);
  } else if (source == 'reader') {
    final label = t.widget<StarBridgeSwitch>(outer).label;
    final nodes = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  } else {
    final row = find.descendant(
      of: outer,
      matching: find.byType(SuitePressable),
    );
    if (row.evaluate().isNotEmpty) {
      t.widget<SuitePressable>(row.first).focusNode!.requestFocus();
    } else {
      t
          .widget<SuiteSwitch>(find.byKey(const Key('audio-enabled')))
          .focusNode!
          .requestFocus();
    }
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await notificationMotionFrames(t, count: 2);
  expect(audioMotionDrafts(t).dirty, isTrue);
}

void audioMotionWait(WidgetTester t, {required bool isStatic}) {
  final panel = find.byType(NotificationAudioPanel);
  final labels = find.descendant(
    of: panel,
    matching: find.byType(SuiteBusyLabel),
  );
  final frames = find.descendant(
    of: panel,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(labels, findsOneWidget);
  expect(frames, findsOneWidget);
  for (final element in [...labels.evaluate(), ...frames.evaluate()]) {
    expect(
      InteractionScope.of(element).reduceMotion ||
          !TickerMode.valuesOf(element).enabled,
      isStatic,
    );
  }
}

void _audioCompletion(WidgetTester t, InteractionSuite suite, bool isStatic) {
  final frame = find.descendant(
    of: find.byType(NotificationAudioPanel),
    matching: find.byType(SuiteBusyFrame),
  );
  final effects = find.descendant(of: frame, matching: find.byType(EffectHost));
  expect(effects, findsOneWidget);
  final state = t.state<EffectHostState>(effects);
  final active = TransientEffect.values.where(state.isPlaying).toList();
  if (isStatic || suite == InteractionSuite.standard) {
    expect(active, isEmpty);
  } else {
    expect(
      active,
      isNotEmpty,
      reason: 'This pointer task retains its own completion feedback.',
    );
  }
}

Future<void> _audioSliderStep(WidgetTester t, String source) async {
  final inner = find.byKey(const Key('audio-volume'));
  final outer = find
      .ancestor(of: inner, matching: find.byType(StarBridgeSlider))
      .first;
  await t.ensureVisible(outer);
  await t.pump();
  if (source == 'reader') {
    final label = t.widget<StarBridgeSlider>(outer).semanticLabel;
    final nodes = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.increase);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.increase,
    );
  } else {
    final value = t.widget(inner);
    final focus = value is Slider
        ? value.focusNode!
        : (value as SuiteSlider).focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  }
  await notificationMotionFrames(t, count: 2);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'scan audio pointer draft follows actual keyboard save and local audio wait is static',
    (t) async {
      size(t, const Size(1000, 1000));
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = AudioMotionPort();
      final audio = NotificationAudioController(port);
      try {
        await module.initialize();
        await audio.refresh();
        final confirmed = audio.value!;
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(module: module, audio: audio),
            ),
            InteractionSuite.scan,
          ),
        );
        await notificationMotionFrames(t);
        final inner = find.byKey(const Key('audio-enabled'));
        final outer = find
            .ancestor(of: inner, matching: find.byType(StarBridgeSwitch))
            .first;
        await t.ensureVisible(outer);
        await t.pump();
        await t.tap(outer);
        await notificationMotionFrames(t, count: 2);
        final panel = find.byType(NotificationAudioPanel);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        expect(drafts.dirty, isTrue);
        expect(port.saves, isEmpty);
        expect(audio.value, same(confirmed));
        expect(t.widget<StarBridgeSwitch>(outer).value, isTrue);

        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await notificationMotionFrames(t, count: 2);
        expect(port.saves, hasLength(1));
        expect(port.saves.single.$1, same(confirmed));
        expect(port.saves.single.$2, isTrue);
        expect(port.saves.single.$3, .65);
        expect(port.saves.single.$4, isTrue);
        expect(port.saves.single.$5, InteractionSource.keyboard);
        expect(audio.value, same(confirmed));
        expect(audio.value!.revision, 3);
        expect(audio.value!.enabled, isFalse);
        expect(audio.busy, isTrue);
        expect(drafts.saving, isTrue);
        expect(notifications.writes, isEmpty);
        expect(port.reads, 1);
        expect(port.previews, 0);

        final labels = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyLabel),
        );
        final frames = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        expect(labels, findsOneWidget);
        expect(frames, findsOneWidget);
        for (final element in [...labels.evaluate(), ...frames.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isTrue,
            reason: 'The real audio owner became busy under keyboard save, not under the earlier pointer edit.',
          );
        }

        port.value = const AudioPreferences(
          4,
          true,
          .65,
          true,
          doNotDisturb: true,
        );
        port.saving.complete(port.value);
        await notificationMotionFrames(t);
        expect(audio.value!.revision, 4);
        expect(audio.value!.enabled, isTrue);
        expect(audio.value!.doNotDisturb, isTrue);
        expect(audio.busy, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        expect(port.previews, 0);
        expect(notifications.writes, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        if (!port.saving.isCompleted) {
          port.saving.completeError(const AudioFailure('conflict'));
        }
        await notificationMotionFrames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'scan audio initial keyboard read keeps its phase origin through pointer ancestor rebuild',
    (t) async {
      size(t, const Size(1000, 1000));
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = AudioMotionPort();
      final first = Completer<AudioPreferences>();
      final second = Completer<AudioPreferences>();
      port.pendingRead = first;
      final audio = NotificationAudioController(port);
      final origin = ValueNotifier(InteractionSource.keyboard);
      Widget app() => scopedApp(
        StarBridgeActivationOrigin(
          source: origin,
          child: SizedBox.expand(
            child: NotificationSettingsPage(module: module, audio: audio),
          ),
        ),
        InteractionSuite.scan,
      );
      void expectWaitMotion({required bool isStatic}) {
        final panel = find.byType(NotificationAudioPanel);
        final labels = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyLabel),
        );
        final frames = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        expect(labels, findsOneWidget);
        expect(frames, findsOneWidget);
        for (final element in [...labels.evaluate(), ...frames.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isStatic,
          );
        }
      }

      try {
        await module.initialize();
        await t.pumpWidget(app());
        await notificationMotionFrames(t, count: 2);
        final state = t.state(find.byType(NotificationAudioPanel));
        final frameKey = t
            .widget(
              find.descendant(
                of: find.byType(NotificationAudioPanel),
                matching: find.byType(SuiteBusyFrame),
              ),
            )
            .key;
        expect(port.reads, 1);
        expect(audio.busy, isTrue);
        expect(audio.value, isNull);
        expectWaitMotion(isStatic: true);

        // A different ancestor input fact and a real parent rebuild do not
        // start a new read. The still-held first phase must keep its origin.
        origin.value = InteractionSource.pointer;
        await t.pumpWidget(app());
        await notificationMotionFrames(t, count: 2);
        expect(t.state(find.byType(NotificationAudioPanel)), same(state));
        expect(port.reads, 1);
        expect(port.saves, isEmpty);
        expect(audio.busy, isTrue);
        expect(audio.value, isNull);
        expect(
          t
              .widget(
                find.descendant(
                  of: find.byType(NotificationAudioPanel),
                  matching: find.byType(SuiteBusyFrame),
                ),
              )
              .key,
          frameKey,
        );
        expectWaitMotion(isStatic: true);

        // Finish that first phase with a typed read failure, then use the
        // real retry action. Its explicit pointer source belongs to a new read.
        first.completeError(const AudioFailure('failed'));
        await notificationMotionFrames(t);
        expect(audio.busy, isFalse);
        expect(audio.error, 'failed');
        port.pendingRead = second;
        final retry = find.byKey(const Key('audio-retry'));
        await t.ensureVisible(retry);
        await t.pump();
        await t.tap(retry);
        await notificationMotionFrames(t, count: 2);
        expect(port.reads, 2);
        expect(audio.busy, isTrue);
        expect(audio.value, isNull);
        expectWaitMotion(isStatic: false);
        second.complete(port.value);
        await notificationMotionFrames(t);
        expect(audio.value, same(port.value));
        expect(audio.busy, isFalse);
        expect(audio.error, isNull);
        expect(port.previews, 0);
        expect(port.saves, isEmpty);
        expect(notifications.writes, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        if (!first.isCompleted) {
          first.complete(port.value);
        }
        if (!second.isCompleted) {
          second.complete(port.value);
        }
        await notificationMotionFrames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        origin.dispose();
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'scan audio new pointer wait does not inherit a completed keyboard save flash',
    (t) async {
      size(t, const Size(1000, 1000));
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = AudioMotionPort();
      final second = Completer<AudioPreferences>();
      final audio = NotificationAudioController(port);
      Future<void>? nextCommand;
      final firstIdle = Completer<void>();
      void listen() {
        if (!audio.busy && port.saves.length == 1 && !firstIdle.isCompleted) {
          firstIdle.complete();
        }
      }

      try {
        await module.initialize();
        await audio.refresh();
        audio.addListener(listen);
        await t.pumpWidget(
          scopedApp(
            Column(
              children: [
                // The rendered page's busy controls are deliberately disabled.
                // A separate actual activation of the same public owner allows
                // the next admitted request without first rebuilding that page.
                StarBridgeActionButton(
                  controlKey: const Key('fixture-audio-next-save'),
                  onActivate: (source) {
                    nextCommand = runStarBridgeActivation<void>(
                      source,
                      () => audio.save(enabled: false),
                    );
                  },
                  child: const Text('Next owner save'),
                ),
                Expanded(
                  child: NotificationSettingsPage(module: module, audio: audio),
                ),
              ],
            ),
            InteractionSuite.scan,
          ),
        );
        await notificationMotionFrames(t);
        final panel = find.byType(NotificationAudioPanel);
        final outer = find
            .ancestor(
              of: find.byKey(const Key('audio-enabled')),
              matching: find.byType(StarBridgeSwitch),
            )
            .first;
        await t.ensureVisible(outer);
        await t.pump();
        await t.tap(outer);
        await notificationMotionFrames(t, count: 2);
        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await notificationMotionFrames(t, count: 2);
        expect(audio.busy, isTrue);
        expect(port.saves, hasLength(1));
        expect(port.saves.single.$5, InteractionSource.keyboard);
        final frame = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        expect(frame, findsOneWidget);
        expect(InteractionScope.of(t.element(frame)).reduceMotion, isTrue);

        const receipt = AudioPreferences(
          4,
          true,
          .65,
          true,
          doNotDisturb: true,
        );
        // Drain the actual receipt and draft-queue Future, without drawing the
        // completed frame. The next activation is a real pointer event.
        await t.runAsync(() async {
          port.value = receipt;
          port.saving.complete(receipt);
          await firstIdle.future;
          await Future<void>.delayed(Duration.zero);
        });
        expect(audio.busy, isFalse);
        expect(audio.value, same(receipt));
        expect(NotificationDraftScope.of(t.element(panel))!.saving, isFalse);
        port.pendingSave = second;
        await t.tap(find.byKey(const Key('fixture-audio-next-save')));
        expect(port.saves, hasLength(2));
        expect(port.saves.last.$1, same(receipt));
        expect(port.saves.last.$2, isFalse);
        expect(port.saves.last.$5, InteractionSource.pointer);
        expect(audio.busy, isTrue);
        expect(audio.value, same(receipt));
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        expect(InteractionScope.of(t.element(frame)).reduceMotion, isFalse);
        final effects = find.descendant(
          of: frame,
          matching: find.byType(EffectHost),
        );
        expect(effects, findsOneWidget);
        final effect = t.state<EffectHostState>(effects);
        for (final transient in TransientEffect.values) {
          expect(
            effect.isPlaying(transient),
            isFalse,
            reason:
                'A completed static keyboard task must not flash inside the new pointer wait: $transient',
          );
        }
        expect(port.previews, 0);
        expect(notifications.writes, isEmpty);
        port.value = const AudioPreferences(
          5,
          false,
          .65,
          true,
          doNotDisturb: true,
        );
        second.complete(port.value);
        await nextCommand;
        await notificationMotionFrames(t);
        expect(audio.value!.revision, 5);
        expect(audio.busy, isFalse);
        expect(t.takeException(), isNull);
      } finally {
        audio.removeListener(listen);
        if (!port.saving.isCompleted) {
          port.saving.complete(port.value);
        }
        if (!second.isCompleted) {
          second.complete(port.value);
        }
        await notificationMotionFrames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual $source audio stage and submit preserve receipt facts and own completion source',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = AudioMotionScenario(suite);
          try {
            await fixture.mount(t);
            final confirmed = fixture.audio.value!;
            final stale = t
                .widget<StarBridgeSwitch>(audioMotionSwitch())
                .onChanged!;
            await audioMotionStage(t, source);
            expect(fixture.port.saves, isEmpty);
            expect(fixture.audio.value, same(confirmed));
            expect(
              t.widget<StarBridgeSwitch>(audioMotionSwitch()).value,
              isTrue,
            );
            final gate = fixture.holdSave();
            await act(
              t,
              find.byKey(const Key('notification-save')),
              source,
              '保存更改',
            );
            await notificationMotionFrames(t, count: 2);
            final expected = source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(fixture.port.saves, hasLength(1));
            expect(fixture.port.saves.single, (
              confirmed,
              true,
              .65,
              true,
              expected,
            ));
            expect(fixture.audio.value, same(confirmed));
            expect(fixture.audio.value!.revision, 3);
            expect(fixture.audio.busy, isTrue);
            expect(audioMotionDrafts(t).saving, isTrue);
            audioMotionWait(t, isStatic: source != 'pointer');
            // A closure retained from the old enabled frame cannot admit a
            // second operation or relabel this held phase.
            runStarBridgeSynchronousActivation(
              source == 'pointer'
                  ? InteractionSource.keyboard
                  : InteractionSource.pointer,
              () => stale(false),
            );
            await notificationMotionFrames(t, count: 1);
            expect(fixture.port.saves, hasLength(1));
            audioMotionWait(t, isStatic: source != 'pointer');
            final receipt = fixture.receipt();
            gate.complete(receipt);
            await t.pump();
            await t.pump(const Duration(milliseconds: 16));
            expect(fixture.audio.value, same(receipt));
            expect(fixture.audio.value!.doNotDisturb, isTrue);
            expect(audioMotionDrafts(t).dirty, isFalse);
            _audioCompletion(t, suite, source != 'pointer');
            expect(fixture.notifications.writes, isEmpty);
            expect(fixture.port.previews, 0);
            expect(
              currentStarBridgeActivationSource,
              InteractionSource.pointer,
            );
            expect(
              captureStarBridgeActivationSource()(),
              InteractionSource.programmatic,
            );
            expect(t.takeException(), isNull);
          } finally {
            await fixture.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite actual $source leave confirmation establishes audio save provenance',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = AudioMotionScenario(suite);
          try {
            await fixture.mount(t);
            final confirmed = fixture.audio.value!;
            await audioMotionStage(t, 'pointer');
            final gate = fixture.holdSave();
            final leaving = confirmNotificationLeave(fixture.module);
            await notificationMotionFrames(t);
            final exitDuration = ModalRoute.of(
              t.element(find.byKey(const Key('notification-leave-dialog'))),
            )!.reverseTransitionDuration;
            await act(
              t,
              find.byKey(const Key('notification-leave-save')),
              source,
              '保存更改',
            );
            await notificationMotionFrames(
              t,
              count: (exitDuration.inMilliseconds / 100).ceil() + 2,
            );
            expect(
              find.byKey(const Key('notification-leave-dialog')),
              findsNothing,
            );
            expect(fixture.port.saves, hasLength(1));
            expect(
              fixture.port.saves.single.$5,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(fixture.audio.value, same(confirmed));
            expect(audioMotionDrafts(t).dirty, isTrue);
            audioMotionWait(t, isStatic: source != 'pointer');
            final receipt = fixture.receipt();
            gate.complete(receipt);
            expect(await leaving, isTrue);
            await notificationMotionFrames(t);
            expect(fixture.audio.value, same(receipt));
            expect(audioMotionDrafts(t).dirty, isFalse);
            expect(fixture.notifications.writes, isEmpty);
            expect(fixture.port.previews, 0);
            expect(
              captureStarBridgeActivationSource()(),
              InteractionSource.programmatic,
            );
            expect(t.takeException(), isNull);
          } finally {
            await fixture.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite keyboard audio edit followed by actual pointer submit animates only the submitted task',
      (t) async {
        final fixture = AudioMotionScenario(suite);
        try {
          await fixture.mount(t);
          await audioMotionStage(t, 'keyboard');
          expect(fixture.port.saves, isEmpty);
          final gate = fixture.holdSave();
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          expect(fixture.port.saves.single.$5, InteractionSource.pointer);
          expect(fixture.audio.value!.enabled, isFalse);
          audioMotionWait(t, isStatic: false);
          gate.complete(fixture.receipt());
          await t.pump();
          await t.pump(const Duration(milliseconds: 16));
          _audioCompletion(t, suite, false);
          expect(audioMotionDrafts(t).dirty, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await fixture.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite held audio phase follows live suite palette and reduced motion without new requests',
      (t) async {
        final fixture = AudioMotionScenario(suite);
        try {
          await fixture.mount(t);
          await audioMotionStage(t, 'pointer');
          final gate = fixture.holdSave();
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await t.pumpWidget(
            fixture.app(using: next, light: true, reduce: true),
          );
          await notificationMotionFrames(t, count: 2);
          audioMotionWait(t, isStatic: true);
          final frame = find.descendant(
            of: find.byType(NotificationAudioPanel),
            matching: find.byType(SuiteBusyFrame),
          );
          final data = InteractionScope.of(t.element(frame));
          expect(data.suite, next);
          expect(data.palette.brightness, Brightness.light);
          expect(fixture.port.reads, 1);
          expect(fixture.port.saves, hasLength(1));
          expect(fixture.audio.value!.revision, 3);
          expect(fixture.audio.busy, isTrue);
          await t.pumpWidget(fixture.app(using: next, light: true));
          await notificationMotionFrames(t, count: 2);
          audioMotionWait(t, isStatic: false);
          expect(fixture.port.saves, hasLength(1));
          gate.complete(fixture.receipt());
          await notificationMotionFrames(t);
          expect(fixture.audio.value!.revision, 4);
          expect(t.takeException(), isNull);
        } finally {
          await fixture.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite failed keyboard save reader reload and pointer resubmit each own their held phase',
      (t) async {
        final semantics = t.ensureSemantics();
        final fixture = AudioMotionScenario(suite);
        try {
          await fixture.mount(t);
          final confirmed = fixture.audio.value!;
          await audioMotionStage(t, 'pointer');
          final saving = fixture.holdSave();
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'keyboard',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          saving.completeError(const AudioFailure('output'));
          await notificationMotionFrames(t);
          expect(fixture.audio.value, same(confirmed));
          expect(fixture.audio.error, 'output');
          expect(audioMotionDrafts(t).failed, isTrue);
          expect(audioMotionDrafts(t).dirty, isTrue);
          expect(t.widget<StarBridgeSwitch>(audioMotionSwitch()).value, isTrue);
          final reading = fixture.holdRead();
          await act(t, find.byKey(const Key('audio-retry')), 'reader', '重新读取');
          await notificationMotionFrames(t, count: 2);
          expect(fixture.port.reads, 2);
          expect(fixture.port.saves, hasLength(1));
          expect(fixture.audio.value, same(confirmed));
          audioMotionWait(t, isStatic: true);
          reading.complete(confirmed);
          await notificationMotionFrames(t);
          expect(audioMotionDrafts(t).dirty, isTrue);
          final retrySave = fixture.holdSave();
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          expect(fixture.port.saves, hasLength(2));
          expect(fixture.port.saves.last.$1, same(confirmed));
          expect(fixture.port.saves.last.$5, InteractionSource.pointer);
          audioMotionWait(t, isStatic: false);
          retrySave.complete(fixture.receipt());
          await notificationMotionFrames(t);
          expect(fixture.audio.error, isNull);
          expect(audioMotionDrafts(t).dirty, isFalse);
          expect(audioMotionDrafts(t).failed, isFalse);
          expect(fixture.port.previews, 0);
          expect(fixture.notifications.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await fixture.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    for (final source in ['keyboard', 'reader']) {
      testWidgets(
        '$suite actual $source volume step only stages then pointer submit controls save motion',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = AudioMotionScenario(suite);
          try {
            await fixture.mount(t);
            final confirmed = fixture.audio.value!;
            await _audioSliderStep(t, source);
            expect(fixture.port.saves, isEmpty);
            expect(fixture.audio.value, same(confirmed));
            expect(audioMotionDrafts(t).dirty, isTrue);
            final slider = find
                .ancestor(
                  of: find.byKey(const Key('audio-volume')),
                  matching: find.byType(StarBridgeSlider),
                )
                .first;
            expect(
              t.widget<StarBridgeSlider>(slider).value,
              closeTo(.66, .00001),
            );
            final gate = fixture.holdSave();
            await act(
              t,
              find.byKey(const Key('notification-save')),
              'pointer',
              '保存更改',
            );
            await notificationMotionFrames(t, count: 2);
            expect(fixture.port.saves.single.$2, isFalse);
            expect(fixture.port.saves.single.$3, closeTo(.66, .00001));
            expect(fixture.port.saves.single.$5, InteractionSource.pointer);
            audioMotionWait(t, isStatic: false);
            gate.complete(fixture.receipt());
            await notificationMotionFrames(t);
            expect(fixture.audio.value!.volume, closeTo(.66, .00001));
            expect(fixture.audio.value!.doNotDisturb, isTrue);
            expect(fixture.port.previews, 0);
            expect(t.takeException(), isNull);
          } finally {
            await fixture.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }

  testWidgets(
    'scan real volume pointer cancellation drops only temporary volume then finish stages for keyboard save',
    (t) async {
      final fixture = AudioMotionScenario(InteractionSuite.scan);
      try {
        await fixture.mount(t);
        final confirmed = fixture.audio.value!;
        final inner = find.byKey(const Key('audio-volume'));
        await t.ensureVisible(inner);
        await t.pump();
        final rect = t.getRect(inner);
        final gesture = await t.startGesture(
          Offset(rect.left + rect.width * .65, rect.center.dy),
        );
        await gesture.moveBy(const Offset(80, 0));
        await t.pump();
        expect(find.text('65%'), findsNothing);
        expect(fixture.port.saves, isEmpty);
        expect(audioMotionDrafts(t).dirty, isFalse);
        await gesture.cancel();
        await notificationMotionFrames(t);
        expect(find.text('65%'), findsOneWidget);
        expect(audioMotionDrafts(t).dirty, isFalse);
        expect(fixture.audio.value, same(confirmed));
        await t.timedDragFrom(
          Offset(rect.left + rect.width * confirmed.volume, rect.center.dy),
          const Offset(100, 0),
          const Duration(milliseconds: 350),
        );
        await notificationMotionFrames(t);
        expect(audioMotionDrafts(t).dirty, isTrue);
        expect(fixture.port.saves, isEmpty);
        final gate = fixture.holdSave();
        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await notificationMotionFrames(t, count: 2);
        expect(fixture.port.saves.single.$3, greaterThan(.65));
        expect(fixture.port.saves.single.$5, InteractionSource.keyboard);
        audioMotionWait(t, isStatic: true);
        gate.complete(fixture.receipt());
        await notificationMotionFrames(t);
        expect(fixture.port.previews, 0);
        expect(t.takeException(), isNull);
      } finally {
        await fixture.close(t);
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
