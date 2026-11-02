import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cz_actions_test.dart' show fire;

class TrayPresenceFixture {
  final source = ValueNotifier(
    const ManualPresenceSnapshot(
      scope: 1,
      confirmedMode: PresenceVisibility.online,
      canChange: true,
    ),
  );
  Completer<void>? pending;
  bool confirm = true;
  final writes = <(PresenceVisibility, Object, InteractionSource)>[];
  late final controller = ManualPresenceController(
    source: source,
    write: (mode, scope) async {
      writes.add((mode, scope, currentStarBridgeActivationSource));
      await pending?.future;
      if (confirm && source.value.scope == scope) {
        source.value = ManualPresenceSnapshot(
          scope: scope,
          confirmedMode: mode,
          canChange: true,
        );
      }
    },
  );
  Widget get panel => TrayQuickPanel(
    state: const TrayQuickPanelState(),
    onDismiss: () {},
    manualPresence: controller,
  );
  Future<void> clean(WidgetTester t) async {
    if (pending case final p? when !p.isCompleted) p.complete();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    controller.dispose();
    source.dispose();
  }
}

Finder menuSurface() => find.byWidgetPredicate(
  (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
);
void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final result in ['confirmed', 'rejected', 'unconfirmed']) {
        testWidgets(
          '$suite $input tray presence $result preserves confirmation and keep-open feedback',
          (t) async {
            final sem = t.ensureSemantics();
            final h = TrayPresenceFixture()
              ..pending = Completer<void>()
              ..confirm = result != 'unconfirmed';
            try {
              await t.pumpWidget(scopedApp(h.panel, suite));
              await t.pumpAndSettle();
              await fire(t, input, 'tray-presence-menu');
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsOneWidget);
              if (input != 'pointer') {
                expect(
                  t
                      .widget<SuiteSurfaceTransition>(menuSurface())
                      .animation
                      .value,
                  1,
                );
              }
              await t.pumpAndSettle();
              await fire(t, input, 'manual-presence-invisible');
              await t.pump();
              await t.pump();
              expect(h.writes, [
                (
                  PresenceVisibility.invisible,
                  1,
                  input == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              expect(h.controller.busy, isTrue);
              expect(
                h.controller.snapshot.confirmedMode,
                PresenceVisibility.online,
              );
              expect(find.text('正在切换…'), findsOneWidget);
              expect(menuSurface(), findsOneWidget);
              await t.tapAt(
                t.getCenter(find.byKey(const Key('manual-presence-invisible'))),
              );
              await t.pump();
              expect(h.writes, hasLength(1));
              if (result == 'rejected') {
                h.pending!.completeError(StateError('Synthetic rejected'));
              } else {
                h.pending!.complete();
              }
              await t.pumpAndSettle();
              expect(menuSurface(), findsOneWidget);
              expect(
                h.controller.snapshot.confirmedMode,
                result == 'confirmed'
                    ? PresenceVisibility.invisible
                    : PresenceVisibility.online,
              );
              expect(h.controller.failed, result != 'confirmed');
              if (result != 'confirmed') {
                expect(find.text('状态未更新，请重试。'), findsOneWidget);
                h.pending = null;
                h.confirm = true;
                await fire(t, input, 'manual-presence-invisible');
                await t.pumpAndSettle();
                expect(h.writes, hasLength(2));
                expect(
                  h.controller.snapshot.confirmedMode,
                  PresenceVisibility.invisible,
                );
                expect(find.text('状态未更新，请重试。'), findsNothing);
              }
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await h.clean(t);
            }
          },
        );
      }
    }
    for (final leave in ['scope', 'dispose', 'cancel']) {
      testWidgets('$suite pending presence $leave cannot revive an old menu', (
        t,
      ) async {
        final h = TrayPresenceFixture()..pending = Completer<void>();
        try {
          await t.pumpWidget(scopedApp(h.panel, suite));
          await t.pumpAndSettle();
          await fire(t, 'keyboard', 'tray-presence-menu');
          await t.pumpAndSettle();
          await fire(t, 'keyboard', 'manual-presence-invisible');
          await t.pump();
          if (leave == 'scope') {
            h.source.value = const ManualPresenceSnapshot(
              scope: 2,
              confirmedMode: PresenceVisibility.online,
              canChange: true,
            );
          } else if (leave == 'dispose') {
            await t.pumpWidget(const SizedBox());
          } else {
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await t.pump();
          await t.pump();
          expect(menuSurface(), findsNothing);
          h.pending!.complete();
          await t.pumpAndSettle();
          expect(menuSurface(), findsNothing);
          if (leave == 'scope') {
            expect(h.controller.snapshot.scope, 2);
            expect(
              h.controller.snapshot.confirmedMode,
              PresenceVisibility.online,
            );
            expect(h.controller.failed, isFalse);
          }
          expect(h.writes, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
    }
  }
}
