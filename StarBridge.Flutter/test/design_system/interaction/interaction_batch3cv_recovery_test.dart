import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_busy.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/menu_overlay/menu_overlay_surface_app_test.dart'
    show channel, snapshot, push;
import 'interaction_batch3ct_test.dart' show detach;
import 'interaction_batch3cu_test.dart' show focusOf;
import 'interaction_batch3cv_test.dart' show activate;
import 'interaction_batch3cm_bridge_test.dart' show incoming;

Map<String, Object> configuration(
  int opening,
  InteractionSuite suite, {
  bool wanted = true,
}) => {
  ...snapshot(opening, wanted: wanted),
  if (wanted) ...{
    'liveFriends': true,
    'recoveryPending': true,
    'preferences': MenuWindowPreferences.defaults.encode(),
    'interactionPresentation': MenuInteractionPresentation(
      style: MenuInteractionStyle.values.byName(suite.name),
    ).encode(),
  },
};

class RecoveryFixture {
  final calls = <MethodCall>[];
  final replies = <Completer<String>>[];
  List<MethodCall> get requests =>
      calls.where((call) => call.method == 'recoveryAction').toList();
  Future<void> mount(WidgetTester t, InteractionSuite suite) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 1000);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'ready') return snapshot(0, wanted: false);
      if (call.method == 'recoveryAction') {
        final pending = Completer<String>();
        replies.add(pending);
        return pending.future;
      }
      return null;
    });
    await t.pumpWidget(const MenuOverlaySurfaceApp(workspacePreview: true));
    await push(t, configuration(1, suite));
    await t.pump();
    expect(find.byType(MenuRecoveryPrompt), findsOneWidget);
  }

  Future<void> dispose(WidgetTester t) async {
    await detach(t);
    for (final reply in replies) {
      if (!reply.isCompleted) {
        reply.complete(MenuWindowPreferences.defaults.encode());
      }
    }
    await t.pump();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    t.view.reset();
  }
}

void expectWaiting(
  WidgetTester t,
  InteractionSuite suite,
  InteractionSource source, {
  bool reduced = false,
}) {
  expect(
    t.widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt)).busy,
    isTrue,
  );
  expect(
    t.widget<MenuRecoveryBusy>(find.byType(MenuRecoveryBusy)).source,
    source,
  );
  final frame = find.byType(SuiteBusyFrame);
  expect(frame, findsOneWidget);
  final data = InteractionScope.of(t.element(frame));
  final animate = source == InteractionSource.pointer && !reduced;
  expect(data.suite, suite);
  expect(data.reduceMotion, !animate);
  expect(
    t
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value,
    animate
        ? (suite == InteractionSuite.standard || suite == InteractionSuite.glow
              ? null
              : 0)
        : .5,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final action in ['restore', 'startClean']) {
        testWidgets(
          '$suite $source $action actual pending and successful reply preserve the two-field native contract',
          (t) async {
            final semantics = t.ensureSemantics();
            final fixture = RecoveryFixture();
            try {
              await fixture.mount(t, suite);
              final key = Key(
                action == 'restore'
                    ? 'menu-recovery-restore'
                    : 'menu-recovery-start-clean',
              );
              await activate(t, source, find.byKey(key));
              await t.pump();
              await t.pump();
              expect(fixture.requests.single.arguments, {
                'opening': 1,
                'action': action,
              });
              expectWaiting(
                t,
                suite,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              final status = t
                  .getSemantics(find.bySemanticsLabel('正在处理…'))
                  .getSemanticsData();
              expect(status.flagsCollection.isLiveRegion, isTrue);
              expect(status.value, isEmpty);
              expect(
                fixture.calls.where(
                  (call) => call.method == 'preferencesChanged',
                ),
                isEmpty,
              );
              await t.tap(find.byKey(key), warnIfMissed: false);
              expect(fixture.requests, hasLength(1));
              fixture.replies.single.complete(
                MenuWindowPreferences.defaults.encode(),
              );
              await t.pump();
              await t.pump();
              expect(find.byType(MenuRecoveryPrompt), findsNothing);
              expect(find.byType(MenuRecoveryBusy), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await fixture.dispose(t);
            }
          },
        );
      }
    }
    testWidgets(
      '$suite rejected pointer choice can retry statically from keyboard without early acceptance',
      (t) async {
        final fixture = RecoveryFixture();
        try {
          await fixture.mount(t, suite);
          await activate(
            t,
            'pointer',
            find.byKey(const Key('menu-recovery-restore')),
          );
          await t.pump();
          fixture.replies.single.completeError(
            PlatformException(code: 'recovery.rejected'),
          );
          await t.pump();
          await t.pump();
          expect(find.text('未能确认恢复选择，请重试。原有布局仍保留。'), findsOneWidget);
          expect(
            t.widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt)).busy,
            isFalse,
          );
          await activate(
            t,
            'keyboard',
            find.byKey(const Key('menu-recovery-start-clean')),
          );
          await t.pump();
          await t.pump();
          expect(fixture.requests.map((call) => call.arguments), [
            {'opening': 1, 'action': 'restore'},
            {'opening': 1, 'action': 'startClean'},
          ]);
          expectWaiting(t, suite, InteractionSource.keyboard);
          fixture.replies.last.complete(
            MenuWindowPreferences.defaults.encode(),
          );
          await t.pump();
          await t.pump();
          expect(find.byType(MenuRecoveryPrompt), findsNothing);
        } finally {
          await fixture.dispose(t);
        }
      },
    );
    testWidgets(
      '$suite timeout and late prior-opening reply cannot restore windows or source into a new opening',
      (t) async {
        final fixture = RecoveryFixture();
        try {
          await fixture.mount(t, suite);
          await activate(
            t,
            'pointer',
            find.byKey(const Key('menu-recovery-restore')),
          );
          await t.pump();
          await t.pump(const Duration(seconds: 6));
          await t.pump();
          expect(
            t
                .widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt))
                .failed,
            isTrue,
          );
          await push(t, configuration(1, suite, wanted: false));
          await push(t, configuration(2, suite));
          await t.pump();
          final current = t.widget<MenuRecoveryPrompt>(
            find.byType(MenuRecoveryPrompt),
          );
          expect(current.busySource, InteractionSource.programmatic);
          expect(current.busy, isFalse);
          fixture.replies.single.complete(
            MenuWindowPreferences.defaults.encode(),
          );
          await t.pump();
          await t.pump();
          expect(find.byType(MenuRecoveryPrompt), findsOneWidget);
          expect(
            t
                .widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt))
                .failed,
            isFalse,
          );
          expect(fixture.requests.single.arguments, {
            'opening': 1,
            'action': 'restore',
          });
          expect(t.takeException(), isNull);
        } finally {
          await fixture.dispose(t);
        }
      },
    );
    testWidgets(
      '$suite live reduce and palette switching keep one admitted native request',
      (t) async {
        final fixture = RecoveryFixture();
        try {
          await fixture.mount(t, suite);
          await activate(
            t,
            'pointer',
            find.byKey(const Key('menu-recovery-restore')),
          );
          await t.pump();
          final state = t.state(find.byType(SuiteBusyFrame));
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await incoming(channel, 'interactionPresentation', {
            'opening': 1,
            'revision': 1,
            'payload': MenuInteractionPresentation(
              style: MenuInteractionStyle.values.byName(next.name),
              reduceMotion: true,
            ).encode(),
          });
          await t.pump();
          await t.pump();
          expectWaiting(t, next, InteractionSource.pointer, reduced: true);
          expect(t.state(find.byType(SuiteBusyFrame)), same(state));
          await incoming(channel, 'interactionPresentation', {
            'opening': 1,
            'revision': 2,
            'payload': MenuInteractionPresentation(
              style: MenuInteractionStyle.values.byName(next.name),
            ).encode(),
          });
          await t.pump();
          await t.pump();
          expectWaiting(t, next, InteractionSource.pointer);
          expect(fixture.requests, hasLength(1));
        } finally {
          await fixture.dispose(t);
        }
      },
    );
    testWidgets(
      '$suite programmatic recovery has no borrowed pointer animation',
      (t) async {
        final fixture = RecoveryFixture();
        try {
          await fixture.mount(t, suite);
          t
              .widget<MenuRecoveryPrompt>(find.byType(MenuRecoveryPrompt))
              .onChoose('restore');
          await t.pump();
          await t.pump();
          expectWaiting(t, suite, InteractionSource.programmatic);
          expect(fixture.requests.single.arguments, {
            'opening': 1,
            'action': 'restore',
          });
        } finally {
          await fixture.dispose(t);
        }
      },
    );
  }
  testWidgets(
    'actual keyboard recovery waits statically without changing its native request',
    (t) async {
      final pending = Completer<String>();
      final calls = <MethodCall>[];
      final messenger = t.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'ready') return snapshot(0, wanted: false);
        if (call.method == 'recoveryAction') return pending.future;
        return null;
      });
      try {
        await t.pumpWidget(const MenuOverlaySurfaceApp(workspacePreview: true));
        await push(t, {
          ...snapshot(1),
          'liveFriends': true,
          'recoveryPending': true,
          'preferences': MenuWindowPreferences.defaults.encode(),
          'interactionPresentation': const MenuInteractionPresentation(
            style: MenuInteractionStyle.scan,
          ).encode(),
        });
        await t.pump();
        expect(
          find.byKey(const Key('menu-recovery-start-clean')),
          findsOneWidget,
        );
        focusOf(t, 'start-clean').requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(
          calls
              .where((call) => call.method == 'recoveryAction')
              .single
              .arguments,
          {'opening': 1, 'action': 'startClean'},
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          t
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNotNull,
        );
      } finally {
        await detach(t);
        if (!pending.isCompleted) {
          pending.complete(MenuWindowPreferences.defaults.encode());
        }
        await t.pump();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
