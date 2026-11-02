import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import '../../app/presence/manual_presence_test.dart' show state;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;

const menuProjection = ShellChromeProjection(
  overlay: OverlaySceneProjection(
    options: [],
    preferredSceneId: null,
    actualSceneId: null,
    canChange: false,
  ),
  accountLabel: '测试舰长',
  presenceKey: 'presence.online',
  syncKey: 'sync.idle',
  friendAttentionCount: 0,
  notificationCount: 0,
  accountSignedIn: true,
);

class MenuFixture {
  final source = ValueNotifier(state(PresenceVisibility.online));
  late final controller = ManualPresenceController(
    source: source,
    write: (mode, scope) async {
      writes.add((mode, scope));
      await pending?.future;
      if (fail) throw StateError('Synthetic failure');
      if (confirm && source.value.scope == scope) {
        source.value = state(mode, scope: scope);
      }
    },
  );
  Completer<void>? pending;
  bool fail = false, confirm = true;
  ShellChromeProjection projection = menuProjection;
  bool destination = true;
  final writes = <(PresenceVisibility, Object)>[];
  final actions = <(String, InteractionSource)>[];
  static const descriptor = FeatureDescriptor(
    id: 'sample',
    route: '/sample',
    labelKey: 'top.account',
    descriptionKey: 'top.account',
    icon: StarBridgeIconSemantic.account,
    navigationRegion: NavigationRegion.accountMenu,
    order: 1,
    availability: FeatureAvailability.comingSoon,
  );
  Widget get home => AccountMenu(
    destinations: destination ? [descriptor] : [],
    projection: projection,
    expanded: true,
    manualPresence: controller,
    onSelect: (d) => actions.add((d.id, currentStarBridgeActivationSource)),
    onLogin: () => actions.add(('login', currentStarBridgeActivationSource)),
    onLogout: () => actions.add(('logout', currentStarBridgeActivationSource)),
    onIssueAction: () =>
        actions.add(('issue', currentStarBridgeActivationSource)),
  );
  Future<void> clean(WidgetTester t) async {
    if (pending case final p? when !p.isCompleted) p.complete();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    controller.dispose();
    source.dispose();
  }
}

Future<void> openMenu(
  WidgetTester t,
  MenuFixture h,
  InteractionSuite suite, [
  String input = 'pointer',
]) async {
  await t.pumpWidget(scopedApp(h.home, suite));
  await t.pumpAndSettle();
  final key = h.projection.accountSignedIn
      ? 'account-identity-command'
      : 'account-command';
  await hit(t, input, key);
  await frames(t);
  expect(nativeViewportMenus.value, 1);
}

Future<void> submenu(WidgetTester t, [String input = 'pointer']) async {
  await hit(t, input, 'account-presence-menu');
  await frames(t);
  expect(find.byKey(const Key('manual-presence-invisible')), findsOneWidget);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final signedIn in [true, false]) {
      testWidgets('$suite signedIn=$signedIn 200 percent bounded topbar', (
        t,
      ) async {
        final h = MenuFixture();
        if (!signedIn) {
          h.projection = menuProjection.copyWith(accountSignedIn: false);
        }
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [h.home],
                      ),
                    ),
                  ),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final key = signedIn ? 'account-identity-command' : 'account-command';
          expect(t.getSize(find.byKey(Key(key))).height, lessThanOrEqualTo(64));
          await hit(t, 'keyboard', key);
          await frames(t);
          expect(nativeViewportMenus.value, 1);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await frames(t);
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
    }
    testWidgets('$suite pending disabled branch Left retains parent', (
      t,
    ) async {
      final h = MenuFixture()..pending = Completer<void>();
      try {
        await openMenu(t, h, suite, 'keyboard');
        await submenu(t, 'keyboard');
        await hit(t, 'keyboard', 'manual-presence-invisible');
        await frames(t);
        expect(h.controller.busy, isTrue);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'cascade-account-presence-menu',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await frames(t);
        expect(find.byKey(const Key('account-presence-menu')), findsOneWidget);
        expect(
          find.byKey(const Key('manual-presence-invisible')),
          findsNothing,
        );
        expect(nativeViewportMenus.value, 1);
        expect(h.writes, hasLength(1));
        expect(h.controller.busy, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await frames(t);
        expect(nativeViewportMenus.value, 0);
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input submenu uses confirmed status and keeps both levels open',
        (t) async {
          final h = MenuFixture(), semantics = t.ensureSemantics();
          try {
            await openMenu(t, h, suite, input);
            await submenu(t, input);
            await hit(t, input, 'manual-presence-invisible');
            await frames(t);
            expect(h.writes, [(PresenceVisibility.invisible, 1)]);
            expect(
              h.controller.snapshot.confirmedMode,
              PresenceVisibility.invisible,
            );
            expect(
              find.byKey(const Key('account-presence-menu')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('manual-presence-invisible')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('manual-presence-inGame')),
              findsNothing,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(
              find.byKey(const Key('account-presence-menu')),
              findsNothing,
            );
            expect(nativeViewportMenus.value, 0);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $input destination source survives and leaf closes root',
        (t) async {
          final h = MenuFixture(), semantics = t.ensureSemantics();
          try {
            await openMenu(t, h, suite, input);
            await hit(t, input, 'account-menu-sample');
            await frames(t);
            expect(h.actions, [
              (
                'sample',
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(nativeViewportMenus.value, 0);
            expect(h.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
      testWidgets('$suite $input logout retains action source and busy gate', (
        t,
      ) async {
        final h = MenuFixture(), semantics = t.ensureSemantics();
        try {
          await openMenu(t, h, suite, input);
          await hit(t, input, 'account-menu-logout');
          await frames(t);
          expect(h.actions, [
            (
              'logout',
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ),
          ]);
          expect(h.writes, isEmpty);
          expect(nativeViewportMenus.value, 0);
        } finally {
          await h.clean(t);
          semantics.dispose();
        }
      });
    }
    for (final outcome in ['confirmed', 'rejected', 'unconfirmed']) {
      testWidgets(
        '$suite pending $outcome never optimistically checks visibility',
        (t) async {
          final h = MenuFixture()
            ..pending = Completer<void>()
            ..fail = outcome == 'rejected'
            ..confirm = outcome == 'confirmed';
          final semantics = t.ensureSemantics();
          try {
            await openMenu(t, h, suite);
            await submenu(t);
            await hit(t, 'pointer', 'manual-presence-invisible');
            await frames(t);
            expect(h.controller.busy, isTrue);
            expect(
              h.controller.snapshot.confirmedMode,
              PresenceVisibility.online,
            );
            expect(find.text('正在切换…'), findsOneWidget);
            final node = t.getSemantics(
              find.byKey(const Key('manual-presence-invisible')),
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            h.pending!.complete();
            h.pending = null;
            await frames(t);
            expect(h.controller.failed, outcome != 'confirmed');
            expect(
              h.controller.snapshot.confirmedMode,
              outcome == 'confirmed'
                  ? PresenceVisibility.invisible
                  : PresenceVisibility.online,
            );
            if (outcome != 'confirmed') {
              expect(find.text('状态未更新，请重试。'), findsOneWidget);
            }
            expect(h.writes.length, 1);
            expect(nativeViewportMenus.value, 1);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite keyboard right enters left returns escape retires entire hierarchy',
      (t) async {
        final h = MenuFixture();
        try {
          await openMenu(t, h, suite, 'keyboard');
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await frames(t);
          expect(
            find.byKey(const Key('manual-presence-invisible')),
            findsOneWidget,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('manual-presence-invisible')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('account-presence-menu')),
            findsOneWidget,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(nativeViewportMenus.value, 0);
          expect(h.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite reduce and theme follow an open branch without a write',
      (t) async {
        final h = MenuFixture();
        try {
          await openMenu(t, h, suite);
          await submenu(t);
          await t.pumpWidget(
            scopedApp(h.home, suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          for (final transition in t.widgetList<SuiteSurfaceTransition>(
            find.byType(SuiteSurfaceTransition),
          )) {
            expect(transition.animation.value, 1);
          }
          expect(
            Theme.of(
              t.element(find.byKey(const Key('manual-presence-invisible'))),
            ).brightness,
            Brightness.light,
          );
          expect(h.writes, isEmpty);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite identity invalidation retires both levels and rejects old pending write',
      (t) async {
        final h = MenuFixture()..pending = Completer<void>();
        try {
          await openMenu(t, h, suite);
          await submenu(t);
          await hit(t, 'pointer', 'manual-presence-invisible');
          await frames(t);
          h.source.value = state(PresenceVisibility.online, scope: 2);
          await frames(t);
          expect(find.byKey(const Key('account-presence-menu')), findsNothing);
          expect(
            find.byKey(const Key('manual-presence-invisible')),
            findsNothing,
          );
          expect(nativeViewportMenus.value, 0);
          h.pending!.complete();
          h.pending = null;
          await frames(t);
          expect(h.controller.snapshot.scope, 2);
          expect(
            h.controller.snapshot.confirmedMode,
            PresenceVisibility.online,
          );
          expect(h.controller.failed, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite pointer exit retains content and hides native view until done',
      (t) async {
        final h = MenuFixture();
        try {
          await openMenu(t, h, suite);
          await submenu(t);
          await t.tapAt(const Offset(1, 1));
          await t.pump(const Duration(milliseconds: 16));
          expect(nativeViewportMenus.value, 1);
          await frames(t);
          expect(nativeViewportMenus.value, 0);
          expect(h.actions, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite reopen interrupts exit without stale hide or duplicate rows',
      (t) async {
        final h = MenuFixture();
        try {
          await openMenu(t, h, suite);
          await t.tapAt(const Offset(1, 1));
          await t.pump(const Duration(milliseconds: 16));
          await hit(t, 'pointer', 'account-identity-command');
          await frames(t);
          expect(
            find.byKey(const Key('account-presence-menu')),
            findsOneWidget,
          );
          expect(nativeViewportMenus.value, 1);
          await submenu(t);
          expect(
            find.byKey(const Key('manual-presence-invisible')),
            findsOneWidget,
          );
          expect(h.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets('$suite main menu opens before submenu interaction', (t) async {
      final source = ValueNotifier(state(PresenceVisibility.online));
      final control = ManualPresenceController(
        source: source,
        write: (mode, _) async {
          source.value = state(mode);
        },
      );
      try {
        await t.pumpWidget(
          scopedApp(
            AccountMenu(
              destinations: const [],
              projection: menuProjection,
              expanded: true,
              manualPresence: control,
              onSelect: (_) {},
              onLogin: () {},
              onLogout: () {},
              onIssueAction: () {},
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('account-identity-command')));
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 1);
        expect(find.byKey(const Key('account-presence-menu')), findsOneWidget);
        expect(
          find.byKey(const Key('manual-presence-invisible')),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        control.dispose();
        source.dispose();
      }
    });
  }
}
