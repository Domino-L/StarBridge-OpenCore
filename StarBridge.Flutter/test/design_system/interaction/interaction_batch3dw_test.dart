import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));

Future<void> notificationMotionFrames(WidgetTester t, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Typed transport gate, not a replacement projection or editor owner.
class NotificationMotionPort implements NotificationSettingsPort {
  NotificationSettingsSnapshot stored =
      InMemoryNotificationSettingsAdapter.forReview().current;
  final events = StreamController<void>.broadcast();
  final reads = <InteractionSource>[];
  final writes = <(NotificationSettingsValue, int, InteractionSource)>[];
  Completer<NotificationSettingsSnapshot>? pendingRead;
  Completer<NotificationSettingsWriteResult>? pendingWrite;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<NotificationSettingsSnapshot> read() {
    reads.add(currentStarBridgeActivationSource);
    final gate = pendingRead;
    pendingRead = null;
    return gate?.future ?? Future.value(stored);
  }

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  }) {
    writes.add((settings, expectedRevision, currentStarBridgeActivationSource));
    final gate = pendingWrite;
    pendingWrite = null;
    if (gate != null) return gate.future;
    stored = NotificationSettingsSnapshot.available(
      settings: settings,
      revision: expectedRevision + 1,
    );
    return Future.value(NotificationSettingsWriteResult.completed(stored));
  }

  @override
  Future<void> close() => events.close();
}

Widget notificationMotionApp(
  NotificationSettingsModule module,
  InteractionSuite suite, {
  bool keyboardOpening = false,
  bool reduce = false,
}) {
  final page = SizedBox.expand(child: NotificationSettingsPage(module: module));
  return scopedApp(
    keyboardOpening
        ? Builder(
            builder: (context) => starBridgeInitialReadViewport(
              context,
              source: InteractionSource.keyboard,
              child: page,
            ),
          )
        : page,
    suite,
    reduce: reduce,
  );
}

void _readMotion(WidgetTester t, InteractionSource expected) {
  final view = find.byType(NotificationLoadingView);
  expect(view, findsOneWidget);
  expect(t.widget<NotificationLoadingView>(view).source, expected);
  if (expected == InteractionSource.keyboard) {
    expectNotificationWaitStatic(t);
  } else {
    final frame = find.descendant(
      of: view,
      matching: find.byType(SuiteBusyFrame),
    );
    expect(frame, findsOneWidget);
    expect(InteractionScope.of(t.element(frame)).reduceMotion, isFalse);
    expect(TickerMode.valuesOf(t.element(frame)).enabled, isTrue);
  }
}

PrivacyPageDrafts _drafts(WidgetTester t) => NotificationDraftScope.of(
  t.element(find.byKey(const Key('notification-settings-content'))),
)!;

Future<void> _stage(WidgetTester t, {String source = 'pointer'}) async {
  final inner = find.byKey(const Key('notification-channel-windows'));
  final outer = find
      .ancestor(of: inner, matching: find.byType(StarBridgeSwitch))
      .first;
  await t.ensureVisible(outer);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(outer);
  } else {
    t
        .widget<SuitePressable>(
          find
              .descendant(of: outer, matching: find.byType(SuitePressable))
              .first,
        )
        .focusNode!
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await notificationMotionFrames(t, count: 2);
  expect(_drafts(t).dirty, isTrue);
}

void _saveWait(
  WidgetTester t,
  InteractionSource source, {
  bool reduce = false,
}) {
  final wait = find.byType(HelpSupportWaiting);
  expect(wait, findsOneWidget);
  expect(t.widget<HelpSupportWaiting>(wait).source, source);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  expect(
    find.byType(SuiteProgressBar),
    reduce || source == InteractionSource.keyboard
        ? findsNothing
        : findsOneWidget,
  );
}

NotificationSettingsSnapshot _receipt(NotificationMotionPort port) =>
    NotificationSettingsSnapshot.available(
      settings: port.writes.last.$1,
      revision: port.writes.last.$2 + 1,
    );

Future<void> _close(WidgetTester t, NotificationSettingsModule module) async {
  await t.pumpWidget(const SizedBox.shrink());
  module.dispose();
  await t.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

void expectNotificationWaitStatic(WidgetTester t) {
  final loading = find.byType(NotificationLoadingView);
  expect(loading, findsOneWidget);
  // Check actual potential animation surfaces within the real read view,
  // without requiring a particular new helper implementation or global idle.
  final animated = find.descendant(
    of: loading,
    matching: find.byWidgetPredicate(
      (w) =>
          w is SuiteBusyFrame ||
          w is SuiteBusyLabel ||
          w is SuiteProgressBar ||
          w is CircularProgressIndicator ||
          w is LinearProgressIndicator,
    ),
  );
  for (final element in animated.evaluate()) {
    expect(
      InteractionScope.of(element).reduceMotion ||
          !TickerMode.valuesOf(element).enabled,
      isTrue,
      reason: 'Keyboard initial reads must settle every local wait surface.',
    );
  }
  final strings = AppStrings.of(t.element(loading));
  expect(
    find.descendant(
      of: loading,
      matching: find.text(strings.text('settings.notification.loading')),
    ),
    findsOneWidget,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite real notification keyboard initial read is locally static until owner receipt',
      (t) async {
        size(t, const Size(1000, 900));
        final port = NotificationMotionPort();
        final gate = Completer<NotificationSettingsSnapshot>();
        port.pendingRead = gate;
        final module = createNotificationSettingsModule(port);
        final initial = module.initialize();
        try {
          await t.pumpWidget(
            notificationMotionApp(module, suite, keyboardOpening: true),
          );
          await notificationMotionFrames(t);
          expect(
            module.projection.value.availability,
            NotificationSettingsAvailability.loading,
          );
          expect(port.reads, hasLength(1));
          expect(port.writes, isEmpty);
          expectNotificationWaitStatic(t);
          gate.complete(port.stored);
          await initial;
          await notificationMotionFrames(t);
          expect(module.projection.value.revision, 11);
          expect(find.byType(NotificationLoadingView), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete(port.stored);
          await t.pumpWidget(const SizedBox.shrink());
          module.dispose();
          await t.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite direct leave guard keyboard confirmation reaches actual module update source',
      (t) async {
        size(t, const Size(1000, 900));
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        final gate = Completer<NotificationSettingsWriteResult>();
        try {
          await module.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          final inner = find.byKey(const Key('notification-channel-windows'));
          final outer = find
              .ancestor(of: inner, matching: find.byType(StarBridgeSwitch))
              .first;
          await t.ensureVisible(outer);
          await t.pump();
          await t.tap(outer);
          await notificationMotionFrames(t, count: 2);
          expect(port.writes, isEmpty);
          port.pendingWrite = gate;
          // Deliberately no active command around this public leave guard.
          // Its keyboard confirmation must establish its own awaited source.
          final leaving = confirmNotificationLeave(module);
          await notificationMotionFrames(t);
          await act(
            t,
            find.byKey(const Key('notification-leave-save')),
            'keyboard',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          expect(port.writes, hasLength(1));
          expect(port.writes.single.$2, 11);
          expect(port.writes.single.$3, InteractionSource.keyboard);
          final receipt = NotificationSettingsSnapshot.available(
            settings: port.writes.single.$1,
            revision: 12,
          );
          gate.complete(NotificationSettingsWriteResult.completed(receipt));
          expect(await leaving, isTrue);
          await notificationMotionFrames(t);
          expect(module.projection.value.revision, 12);
          expect(t.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(
              const NotificationSettingsWriteResult.failed(
                NotificationSettingsFailure.writeFailed,
              ),
            );
          }
          await notificationMotionFrames(t, count: 2);
          await t.pumpWidget(const SizedBox.shrink());
          module.dispose();
          await t.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
        }
      },
      timeout: _timeout,
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source real staged save keeps confirmed revision until authoritative receipt',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = NotificationMotionPort();
          final module = createNotificationSettingsModule(port);
          final gate = Completer<NotificationSettingsWriteResult>();
          try {
            size(t, const Size(1000, 900));
            await module.initialize();
            await t.pumpWidget(notificationMotionApp(module, suite));
            await notificationMotionFrames(t);
            final confirmed = module.projection.value.settings!;
            await _stage(t);
            expect(port.writes, isEmpty);
            expect(module.projection.value.settings, same(confirmed));
            port.pendingWrite = gate;
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
            expect(port.writes, hasLength(1));
            expect(port.writes.single.$2, 11);
            expect(port.writes.single.$3, expected);
            expect(
              port.writes.single.$1.channels.windowsDesktopEnabled,
              isFalse,
            );
            expect(port.writes.single.$1.previewMode, confirmed.previewMode);
            expect(
              port.writes.single.$1.sourceRules,
              orderedEquals(confirmed.sourceRules),
            );
            expect(module.projection.value.settings, same(confirmed));
            expect(module.projection.value.revision, 11);
            expect(module.projection.value.canEdit, isFalse);
            _saveWait(t, expected);
            expect(_drafts(t).saving, isTrue);
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            await notificationMotionFrames(t, count: 3);
            expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
            expect(port.writes, hasLength(1));
            port.stored = _receipt(port);
            gate.complete(
              NotificationSettingsWriteResult.completed(port.stored),
            );
            await notificationMotionFrames(t);
            expect(module.projection.value.revision, 12);
            expect(
              module.projection.value.settings!.channels.windowsDesktopEnabled,
              isFalse,
            );
            expect(_drafts(t).dirty, isFalse);
            expect(_drafts(t).saving, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(port.reads, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            if (!gate.isCompleted) {
              gate.complete(
                const NotificationSettingsWriteResult.failed(
                  NotificationSettingsFailure.writeFailed,
                ),
              );
            }
            await notificationMotionFrames(t, count: 2);
            await _close(t, module);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $source unavailable retry freezes read source then a later pointer phase animates again',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = NotificationMotionPort();
          final available = port.stored;
          port.stored = const NotificationSettingsSnapshot.unavailable(
            failure: NotificationSettingsFailure.readFailed,
          );
          final module = createNotificationSettingsModule(port);
          final first = Completer<NotificationSettingsSnapshot>();
          final second = Completer<NotificationSettingsSnapshot>();
          try {
            size(t, const Size(1000, 900));
            await module.initialize();
            await t.pumpWidget(notificationMotionApp(module, suite));
            await notificationMotionFrames(t);
            expect(
              find.byKey(const Key('notification-settings-unavailable')),
              findsOneWidget,
            );
            port.pendingRead = first;
            await act(
              t,
              find.byKey(const Key('notification-state-action')),
              source,
              '重新读取',
            );
            await notificationMotionFrames(t, count: 2);
            final expected = source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(port.reads, hasLength(2));
            expect(port.reads.last, expected);
            _readMotion(t, expected);
            final phase = t.widget(find.byType(NotificationLoadingView)).key;
            first.complete(port.stored);
            await notificationMotionFrames(t);
            port.pendingRead = second;
            await act(
              t,
              find.byKey(const Key('notification-state-action')),
              'pointer',
              '重新读取',
            );
            await notificationMotionFrames(t, count: 2);
            _readMotion(t, InteractionSource.pointer);
            expect(
              t.widget(find.byType(NotificationLoadingView)).key,
              isNot(phase),
            );
            expect(port.reads, hasLength(3));
            expect(port.writes, isEmpty);
            second.complete(available);
            await notificationMotionFrames(t);
            expect(module.projection.value.revision, 11);
            expect(find.byType(NotificationLoadingView), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            if (!first.isCompleted) first.complete(available);
            if (!second.isCompleted) second.complete(available);
            await notificationMotionFrames(t, count: 2);
            await _close(t, module);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite live reduce stops main-owner wait without ending or relabeling its save',
      (t) async {
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        final gate = Completer<NotificationSettingsWriteResult>();
        try {
          size(t, const Size(1000, 900));
          await module.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          await _stage(t);
          port.pendingWrite = gate;
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          _saveWait(t, InteractionSource.pointer);
          final waitKey = t.widget(find.byType(HelpSupportWaiting)).key;
          final group = _drafts(t);
          await t.pumpWidget(
            notificationMotionApp(module, suite, reduce: true),
          );
          await t.pump(const Duration(milliseconds: 16));
          _saveWait(t, InteractionSource.pointer, reduce: true);
          expect(t.widget(find.byType(HelpSupportWaiting)).key, waitKey);
          expect(_drafts(t), same(group));
          expect(group.saving, isTrue);
          expect(port.writes, hasLength(1));
          gate.complete(
            NotificationSettingsWriteResult.completed(_receipt(port)),
          );
          await notificationMotionFrames(t);
          expect(group.dirty, isFalse);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(
              const NotificationSettingsWriteResult.failed(
                NotificationSettingsFailure.writeFailed,
              ),
            );
          }
          await notificationMotionFrames(t, count: 2);
          await _close(t, module);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite failure keeps confirmed values and draft until explicit keyboard resave',
      (t) async {
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        final first = Completer<NotificationSettingsWriteResult>();
        final second = Completer<NotificationSettingsWriteResult>();
        try {
          size(t, const Size(1000, 900));
          await module.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          final before = module.projection.value.settings;
          await _stage(t);
          port.pendingWrite = first;
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          first.complete(
            const NotificationSettingsWriteResult.failed(
              NotificationSettingsFailure.writeFailed,
            ),
          );
          await notificationMotionFrames(t);
          expect(module.projection.value.settings, same(before));
          expect(module.projection.value.revision, 11);
          expect(_drafts(t).dirty, isTrue);
          expect(_drafts(t).failed, isTrue);
          expect(find.byType(NotificationFailureBanner), findsOneWidget);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          port.pendingWrite = second;
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'keyboard',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          _saveWait(t, InteractionSource.keyboard);
          expect(port.writes, hasLength(2));
          expect(port.writes.map((w) => w.$2), [11, 11]);
          second.complete(
            NotificationSettingsWriteResult.completed(_receipt(port)),
          );
          await notificationMotionFrames(t);
          expect(_drafts(t).dirty, isFalse);
          expect(_drafts(t).failed, isFalse);
          expect(module.projection.value.revision, 12);
          expect(t.takeException(), isNull);
        } finally {
          if (!first.isCompleted) {
            first.complete(
              const NotificationSettingsWriteResult.failed(
                NotificationSettingsFailure.writeFailed,
              ),
            );
          }
          if (!second.isCompleted) {
            second.complete(
              const NotificationSettingsWriteResult.failed(
                NotificationSettingsFailure.writeFailed,
              ),
            );
          }
          await notificationMotionFrames(t, count: 2);
          await _close(t, module);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite same-frame repeated save uses original admission and later phase source',
      (t) async {
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        try {
          size(t, const Size(1000, 900));
          await module.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          Key? previous;
          for (final source in [
            InteractionSource.keyboard,
            InteractionSource.pointer,
          ]) {
            await _stage(t);
            final index = port.writes.length;
            final gate = Completer<NotificationSettingsWriteResult>();
            port.pendingWrite = gate;
            final target = find.byKey(const Key('notification-save'));
            final action = t
                .widget<StarBridgeActionButton>(
                  find
                      .ancestor(
                        of: target,
                        matching: find.byType(StarBridgeActionButton),
                      )
                      .first,
                )
                .onActivate!;
            action(source);
            action(
              source == InteractionSource.keyboard
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await notificationMotionFrames(t, count: 2);
            expect(port.writes, hasLength(index + 1));
            expect(port.writes.last.$3, source);
            _saveWait(t, source);
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            if (previous != null) expect(phase, isNot(previous));
            previous = phase;
            port.stored = _receipt(port);
            gate.complete(
              NotificationSettingsWriteResult.completed(port.stored),
            );
            await notificationMotionFrames(t);
          }
          expect(port.writes, hasLength(2));
          expect(module.projection.value.revision, 13);
          expect(t.takeException(), isNull);
        } finally {
          await _close(t, module);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite programmatic refresh preserves original loading behavior and no new write',
      (t) async {
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        final gate = Completer<NotificationSettingsSnapshot>();
        try {
          size(t, const Size(1000, 900));
          await module.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          port.pendingRead = gate;
          final reading = runStarBridgeActivation<void>(
            InteractionSource.programmatic,
            module.refresh,
          );
          await notificationMotionFrames(t, count: 2);
          expect(module.projection.value.settings, isNull);
          expect(module.projection.value.canEdit, isFalse);
          expect(
            find.byKey(const Key('notification-settings-content')),
            findsNothing,
          );
          _readMotion(t, InteractionSource.programmatic);
          expect(port.reads, hasLength(2));
          expect(port.writes, isEmpty);
          gate.complete(port.stored);
          await reading;
          await notificationMotionFrames(t);
          expect(module.projection.value.revision, 11);
          expect(
            find.byKey(const Key('notification-settings-content')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete(port.stored);
          await notificationMotionFrames(t, count: 2);
          await _close(t, module);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite replaced page owner ignores old late save feedback without disposing that module',
      (t) async {
        final port = NotificationMotionPort();
        final nextPort = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        final next = createNotificationSettingsModule(nextPort);
        final gate = Completer<NotificationSettingsWriteResult>();
        try {
          size(t, const Size(1000, 900));
          await module.initialize();
          await next.initialize();
          await t.pumpWidget(notificationMotionApp(module, suite));
          await notificationMotionFrames(t);
          await _stage(t);
          port.pendingWrite = gate;
          await act(
            t,
            find.byKey(const Key('notification-save')),
            'pointer',
            '保存更改',
          );
          await notificationMotionFrames(t, count: 2);
          _saveWait(t, InteractionSource.pointer);
          await t.pumpWidget(notificationMotionApp(next, suite));
          await notificationMotionFrames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(_drafts(t).dirty, isFalse);
          gate.complete(
            NotificationSettingsWriteResult.completed(_receipt(port)),
          );
          await notificationMotionFrames(t);
          expect(module.projection.value.revision, 12);
          expect(next.projection.value.revision, 11);
          expect(nextPort.writes, isEmpty);
          expect(_drafts(t).dirty, isFalse);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(
              const NotificationSettingsWriteResult.failed(
                NotificationSettingsFailure.writeFailed,
              ),
            );
          }
          await notificationMotionFrames(t, count: 2);
          await _close(t, module);
          next.dispose();
          await t.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
        }
      },
      timeout: _timeout,
    );
  }
}
