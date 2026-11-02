import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_detail.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_details.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fb_hangar_test.dart'
    show
        HangarProbe,
        HangarProbePort,
        hangarInventory,
        hangarKey,
        settleHangarMotion;
import 'interaction_batch3fc_visibility_test.dart' show activateVisibility;

class DetailPort extends HangarProbePort {
  final sources = <InteractionSource>[];
  @override
  Future<LocalHangarSnapshot> setFavorite(String id, bool value, int revision) {
    sources.add(currentStarBridgeActivationSource);
    return super.setFavorite(id, value, revision);
  }
}

class DetailProbe extends HangarProbe {
  DetailProbe(super.suite) {
    port = DetailPort();
  }
  DetailPort get actual => port as DetailPort;
}

Future<DetailProbe> mountDetails(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(1120, 1200));
  final p = DetailProbe(suite);
  await t.pumpWidget(p.app());
  await settleHangarMotion(t);
  return p;
}

Future<void> detailActivate(WidgetTester t, Finder target, String input) async {
  if (input == 'keyboard' && t.widget(target) is IconButton) {
    await t.ensureVisible(target);
    await settleHangarMotion(t);
    final focus = t.widget<IconButton>(target).focusNode!;
    for (var i = 0; !focus.hasPrimaryFocus && i < 100; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(focus.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleHangarMotion(t);
  } else {
    await activateVisibility(t, target, input);
  }
}

StarBridgeIconAction detailButton(WidgetTester t, String name) =>
    t.widget<StarBridgeIconAction>(
      find
          .ancestor(
            of: hangarKey('hangar-detail-$name'),
            matching: find.byType(StarBridgeIconAction),
          )
          .first,
    );

StarBridgeDialogRoute<void> detailRoute(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(LocalHangarDetail)))!
        as StarBridgeDialogRoute<void>;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final list in [false, true]) {
      for (final input in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite ${list ? 'list' : 'card'} $input complete detail controls preserve favorite refusal/retry',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              final p = await mountDetails(t, suite);
              if (list) {
                await detailActivate(t, hangarKey('hangar-list'), input);
              }
              await detailActivate(t, hangarKey('hangar-open-alpha'), input);
              final route = detailRoute(t);
              expect(route.instant, input != 'pointer');
              expect(
                route.traversalEdgeBehavior,
                TraversalEdgeBehavior.closedLoop,
              );
              expect(route.barrierDismissible, isTrue);
              final body = t.state(find.byType(LocalHangarShipDetails));
              expect(detailButton(t, 'favorite').selected, isFalse);
              await detailActivate(t, hangarKey('hangar-detail-expand'), input);
              expect(t.state(find.byType(LocalHangarShipDetails)), same(body));
              await detailActivate(t, hangarKey('hangar-detail-expand'), input);
              expect(t.state(find.byType(LocalHangarShipDetails)), same(body));
              p.actual.pendingFavorite = Completer();
              await detailActivate(
                t,
                hangarKey('hangar-detail-favorite'),
                input,
              );
              expect(p.actual.favorites, [('alpha', true, 1)]);
              expect(
                p.actual.sources.single,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(detailButton(t, 'favorite').onActivate, isNull);
              expect(detailButton(t, 'favorite').selected, isFalse);
              await t.tapAt(t.getCenter(hangarKey('hangar-detail-favorite')));
              await t.pump();
              expect(p.actual.favorites.length, 1);
              p.actual.pendingFavorite!.completeError(
                StateError('controlled local refusal'),
              );
              await settleHangarMotion(t);
              expect(detailButton(t, 'favorite').selected, isFalse);
              expect(detailButton(t, 'favorite').onActivate, isNotNull);
              expect(find.textContaining('收藏'), findsWidgets);
              p.actual.pendingFavorite = Completer();
              await detailActivate(
                t,
                hangarKey('hangar-detail-favorite'),
                input,
              );
              expect(p.actual.favorites.length, 2);
              p.actual.snapshot = hangarInventory(revision: 2, favorite: true);
              p.actual.pendingFavorite!.complete(p.actual.snapshot);
              await settleHangarMotion(t);
              expect(detailButton(t, 'favorite').selected, isTrue);
              expect(detailButton(t, 'favorite').onActivate, isNotNull);
              expect(p.actual.saves, 0);
              expect(p.actual.reads, 1);
              await detailActivate(t, hangarKey('hangar-detail-close'), input);
              expect(find.byType(LocalHangarDetail), findsNothing);
              expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
              // The original saved projection, not an optimistic selected flag.
              final favorite = t.widget<StarBridgeIconAction>(
                find
                    .ancestor(
                      of: hangarKey('hangar-favorite-alpha'),
                      matching: find.byType(StarBridgeIconAction),
                    )
                    .first,
              );
              expect(favorite.selected, isTrue);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox.shrink());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }

    for (final succeed in [false, true]) {
      for (final leave in [false, true]) {
        testWidgets(
          '$suite ${leave ? 'leave' : 'replace'} during favorite; late $succeed cannot mutate new owner or pop unrelated route',
          (t) async {
            final p = await mountDetails(t, suite);
            final old = p.actual;
            await detailActivate(t, hangarKey('hangar-open-alpha'), 'pointer');
            old.pendingFavorite = Completer();
            await detailActivate(
              t,
              hangarKey('hangar-detail-favorite'),
              'pointer',
            );
            final ctx = t.element(find.byType(LocalHangarDetail));
            unawaited(
              showDialog<void>(
                context: ctx,
                builder: (_) =>
                    const AlertDialog(content: Text('unrelated detail probe')),
              ),
            );
            await settleHangarMotion(t);
            final next = DetailPort();
            p.update(() {
              if (leave) {
                p.visible = false;
              } else {
                p.port = next;
              }
            });
            await settleHangarMotion(t);
            expect(
              find.byType(LocalHangarDetail, skipOffstage: false),
              findsNothing,
            );
            expect(find.text('unrelated detail probe'), findsOneWidget);
            if (succeed) {
              old.pendingFavorite!.complete(
                hangarInventory(revision: 2, favorite: true),
              );
            } else {
              old.pendingFavorite!.completeError(StateError('late refusal'));
            }
            await settleHangarMotion(t);
            expect(next.favorites, isEmpty);
            expect(next.snapshot.ships.first.isFavorite, isFalse);
            expect(next.saves, 0);
            expect(find.text('unrelated detail probe'), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }

    testWidgets(
      '$suite live reduced motion and theme during entry settle same route within two frames',
      (t) async {
        final p = await mountDetails(t, suite);
        await t.ensureVisible(hangarKey('hangar-open-alpha'));
        await t.tap(hangarKey('hangar-open-alpha'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 48));
        final route = detailRoute(t);
        p.update(() {
          p.reduce = true;
          p.light = true;
          p.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(detailRoute(t), same(route));
        expect(route.animation!.value, 1);
        final data = InteractionScope.of(
          t.element(hangarKey('hangar-detail-close')),
        );
        expect(data.reduceMotion, isTrue);
        expect(data.suite, InteractionSuite.glow);
        expect(data.palette.brightness, Brightness.light);
        expect(p.actual.reads, 1);
        expect(p.actual.favorites, isEmpty);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(LocalHangarDetail), findsNothing);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '$suite disposing while close reverses retires body but not a separate top modal',
      (t) async {
        final p = await mountDetails(t, suite);
        await detailActivate(t, hangarKey('hangar-open-alpha'), 'pointer');
        final ctx = t.element(find.byType(LocalHangarDetail));
        final route = detailRoute(t);
        await t.tap(hangarKey('hangar-detail-close'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        expect(route.animation!.status, AnimationStatus.reverse);
        expect(
          find.byType(LocalHangarShipDetails),
          findsOneWidget,
          reason: 'body remains during exit',
        );
        unawaited(
          showDialog<void>(
            context: ctx,
            builder: (_) => const AlertDialog(content: Text('keep this modal')),
          ),
        );
        p.update(() => p.visible = false);
        await settleHangarMotion(t);
        expect(
          find.byType(LocalHangarDetail, skipOffstage: false),
          findsNothing,
        );
        expect(find.text('keep this modal'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
