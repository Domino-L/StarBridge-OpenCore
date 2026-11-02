import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder hangarKey(String value) => find.byKey(Key(value));

LocalHangarSnapshot hangarInventory({
  int revision = 1,
  bool favorite = false,
}) => LocalHangarSnapshot(
  revision: revision,
  ships: [
    LocalHangarShip(
      id: 'alpha',
      title: 'Alpha',
      cn: '阿尔法',
      tw: '阿爾法',
      category: 'combat',
      sizeClass: 'small',
      deliveryStatus: 'flyable',
      priceUsd: 100,
      isFavorite: favorite,
    ),
    const LocalHangarShip(
      id: 'beta',
      title: 'Beta',
      cn: '贝塔',
      tw: '貝塔',
      category: 'logistics',
      sizeClass: 'medium',
      deliveryStatus: 'concept',
      priceUsd: 200,
      isFavorite: true,
    ),
    const LocalHangarShip(
      id: 'gamma',
      title: 'Gamma',
      cn: '伽马',
      tw: '伽馬',
      category: 'combat',
      sizeClass: 'large',
      deliveryStatus: 'concept',
    ),
  ],
  formerShips: const [
    LocalHangarShip(
      id: 'old',
      title: 'Old ship',
      cn: '旧舰船',
      tw: '舊艦船',
      category: 'combat',
      sizeClass: 'small',
      deliveryStatus: 'flyable',
    ),
  ],
);

class HangarProbePort implements LocalHangarPort, LocalHangarFavoritesPort {
  LocalHangarSnapshot snapshot = hangarInventory();
  int reads = 0, saves = 0;
  Completer<LocalHangarSnapshot>? pendingRead, pendingFavorite;
  final favorites = <(String, bool, int)>[];
  @override
  bool get favoritesAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() {
    reads++;
    return pendingRead?.future ?? Future.value(snapshot);
  }

  @override
  Future<LocalHangarSnapshot> save(
    String id,
    int revision, {
    bool confirmEmpty = false,
  }) async {
    saves++;
    throw StateError('Toolbar/filter operations must not save an inventory');
  }

  @override
  Future<LocalHangarSnapshot> setFavorite(String id, bool value, int revision) {
    favorites.add((id, value, revision));
    return pendingFavorite?.future ?? Future.value(snapshot);
  }
}

class HangarProbe {
  HangarProbe(this.suite);
  InteractionSuite suite;
  HangarProbePort port = HangarProbePort();
  bool reduce = false, light = false, visible = true;
  int scanOpens = 0;
  final scanSources = <InteractionSource>[];
  final frame = GlobalKey();
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return RepaintBoundary(
        key: frame,
        child: scopedApp(
          visible
              ? LocalHangarPage(
                  port: port,
                  onRead: () {
                    scanOpens++;
                    scanSources.add(currentStarBridgeActivationSource);
                  },
                )
              : const Text('away'),
          suite,
          reduce: reduce,
          light: light,
        ),
      );
    },
  );
}

Future<HangarProbe> mountHangar(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(1120, 1200));
  final p = HangarProbe(suite);
  await t.pumpWidget(p.app());
  await t.pumpAndSettle();
  return p;
}

bool hangarEnabled(WidgetTester t, String key) {
  final target = hangarKey(key);
  final button = find.ancestor(
    of: target,
    matching: find.byType(StarBridgeActionButton),
  );
  if (button.evaluate().isNotEmpty) {
    return t.widget<StarBridgeActionButton>(button.first).onActivate != null;
  }
  return t
          .widget<StarBridgeIconAction>(
            find
                .ancestor(
                  of: target,
                  matching: find.byType(StarBridgeIconAction),
                )
                .first,
          )
          .onActivate !=
      null;
}

Future<void> activateHangar(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  await settleHangarMotion(t);
  if (input == 'keyboard') {
    final widget = t.widget(target);
    final node = switch (widget) {
      ButtonStyleButton button => button.focusNode!,
      IconButton button => button.focusNode!,
      ChoiceChip chip => chip.focusNode!,
      FilterChip chip => chip.focusNode!,
      SuitePressable pressable => pressable.focusNode!,
      SuiteChoiceChip chip => chip.focusNode!,
      _ =>
        t
            .widget<FocusableActionDetector>(
              find
                  .descendant(
                    of: target,
                    matching: find.byType(FocusableActionDetector),
                  )
                  .first,
            )
            .focusNode!,
    };
    for (var i = 0; !node.hasPrimaryFocus && i < 100; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (input == 'reader') {
    // SuiteChoiceChip's key is above its actual semantic press target. Reading
    // there reaches the route; activate the real child, not an ancestor node.
    final semanticTarget = t.widget(target) is SuiteChoiceChip
        ? find
              .descendant(of: target, matching: find.byType(SuitePressable))
              .first
        : target;
    final node = t.getSemantics(semanticTarget);
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
      reason: 'Target $target: ${node.getSemanticsData()}',
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    await t.tap(target);
  }
  await t.pump();
  await settleHangarMotion(t);
}

// A pending business read/favorite intentionally has a live waiting indicator.
// Advance only finite input feedback; do not wait for that operation to settle.
Future<void> settleHangarMotion(WidgetTester t) async {
  await t.pump();
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder summaryHeader() => find
    .descendant(
      of: hangarKey('local-hangar-summary'),
      matching: find.byType(SuitePressable),
    )
    .first;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input toolbar and all filter families retain owners',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountHangar(t, suite);
            expect(
              t.getSemantics(summaryHeader()).getSemanticsData().label,
              contains('历史目录参考价'),
            );
            await activateHangar(t, hangarKey('local-hangar-read'), input);
            expect(p.scanOpens, 1);
            expect(p.scanSources, [
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            await activateHangar(t, hangarKey('hangar-list'), input);
            await activateHangar(t, hangarKey('hangar-role-combat'), input);
            expect(hangarKey('local-hangar-ship-beta'), findsNothing);
            expect(
              t.widget<Text>(hangarKey('local-hangar-total-count')).data,
              '3',
            );
            await activateHangar(t, hangarKey('hangar-status-flyable'), input);
            expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
            expect(hangarKey('local-hangar-ship-gamma'), findsNothing);
            await activateHangar(t, hangarKey('hangar-size-small'), input);
            await activateHangar(t, hangarKey('hangar-status-flyable'), input);
            await activateHangar(t, hangarKey('hangar-size-all'), input);
            expect(hangarKey('local-hangar-ship-gamma'), findsOneWidget);
            await activateHangar(
              t,
              hangarKey('hangar-clear-active-filters'),
              input,
            );
            expect(hangarKey('local-hangar-ship-beta'), findsOneWidget);
            await activateHangar(t, hangarKey('hangar-favorites'), input);
            expect(hangarKey('local-hangar-ship-alpha'), findsNothing);
            expect(hangarKey('local-hangar-ship-beta'), findsOneWidget);
            await activateHangar(t, hangarKey('hangar-favorites'), input);
            await activateHangar(t, hangarKey('hangar-former'), input);
            expect(hangarKey('local-hangar-summary'), findsNothing);
            expect(hangarKey('local-hangar-ship-old'), findsOneWidget);
            await activateHangar(t, hangarKey('hangar-current'), input);
            await activateHangar(t, summaryHeader(), input);
            expect(find.text('用途分布'), findsOneWidget);
            await activateHangar(t, summaryHeader(), input);
            expect(find.text('用途分布'), findsNothing);
            await activateHangar(t, hangarKey('hangar-grid'), input);
            await t.enterText(hangarKey('local-hangar-search'), 'Alpha');
            await t.pump();
            expect(hangarKey('local-hangar-ship-beta'), findsNothing);
            await activateHangar(
              t,
              hangarKey('local-hangar-clear-search'),
              input,
            );
            expect(hangarKey('local-hangar-ship-beta'), findsOneWidget);
            expect(p.port.reads, 1);
            expect(p.port.saves, 0);
            expect(p.port.favorites, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    for (final failed in [false, true]) {
      testWidgets(
        '$suite refresh ${failed ? 'failure' : 'success'} keeps old inventory and independent controls',
        (t) async {
          final p = await mountHangar(t, suite);
          p.port.pendingRead = Completer();
          await t.tap(hangarKey('local-hangar-refresh'));
          await t.pump();
          expect(p.port.reads, 2);
          expect(hangarEnabled(t, 'local-hangar-refresh'), isFalse);
          expect(hangarEnabled(t, 'local-hangar-read'), isTrue);
          expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
          await activateHangar(t, hangarKey('hangar-list'), 'pointer');
          await activateHangar(t, hangarKey('hangar-role-combat'), 'pointer');
          if (failed) {
            p.port.pendingRead!.completeError(
              const LocalHangarFailure('hangar.read_unavailable'),
            );
          } else {
            p.port.pendingRead!.complete(hangarInventory(revision: 2));
          }
          await t.pumpAndSettle();
          expect(hangarEnabled(t, 'local-hangar-refresh'), isTrue);
          expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
          expect(p.port.saves, 0);
          expect(p.port.favorites, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite favorite pending gates original actions; refusal retains confirmed bookmark then retries',
      (t) async {
        final p = await mountHangar(t, suite);
        p.port.pendingFavorite = Completer();
        await t.tap(hangarKey('hangar-favorite-alpha'));
        await t.pump();
        expect(p.port.favorites, [('alpha', true, 1)]);
        expect(hangarEnabled(t, 'local-hangar-refresh'), isFalse);
        expect(hangarEnabled(t, 'local-hangar-read'), isFalse);
        await activateHangar(t, hangarKey('hangar-favorites'), 'pointer');
        expect(
          hangarKey('local-hangar-ship-alpha'),
          findsNothing,
          reason: 'favorite is not optimistically saved',
        );
        p.port.pendingFavorite!.completeError(
          const LocalHangarFailure('hangar.save_failed'),
        );
        await t.pumpAndSettle();
        expect(hangarEnabled(t, 'local-hangar-read'), isTrue);
        expect(hangarEnabled(t, 'local-hangar-refresh'), isTrue);
        await activateHangar(t, hangarKey('hangar-favorites'), 'pointer');
        p.port.pendingFavorite = Completer();
        await t.tap(hangarKey('hangar-favorite-alpha'));
        await t.pump();
        expect(p.port.favorites, [('alpha', true, 1), ('alpha', true, 1)]);
        p.port.pendingFavorite!.complete(
          hangarInventory(revision: 2, favorite: true),
        );
        await t.pumpAndSettle();
        await activateHangar(t, hangarKey('hangar-favorites'), 'pointer');
        expect(hangarKey('local-hangar-ship-alpha'), findsOneWidget);
        expect(p.port.saves, 0);
      },
    );

    testWidgets(
      '$suite live settings keep field identity IME and expanded overview',
      (t) async {
        final p = await mountHangar(t, suite);
        await activateHangar(t, summaryHeader(), 'pointer');
        final edit = find.descendant(
          of: hangarKey('local-hangar-search'),
          matching: find.byType(EditableText),
        );
        final state = t.state(edit);
        final controller = t.widget<EditableText>(edit).controller;
        const value = TextEditingValue(
          text: 'Alpha',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
          composing: TextRange(start: 0, end: 5),
        );
        controller.value = value;
        p.update(() {
          p.reduce = true;
          p.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(t.state(edit), same(state));
        expect(controller.value, value);
        expect(find.text('用途分布'), findsOneWidget);
        await activateHangar(t, summaryHeader(), 'keyboard');
        expect(find.text('用途分布'), findsNothing);
        expect(t.binding.hasScheduledFrame, isFalse);
        expect(p.port.reads, 1);
        expect(p.port.saves, 0);
      },
    );

    for (final failed in [false, true]) {
      testWidgets(
        '$suite leaving during refresh rejects late ${failed ? 'failure' : 'success'}',
        (t) async {
          final p = await mountHangar(t, suite);
          p.port.pendingRead = Completer();
          await t.tap(hangarKey('local-hangar-refresh'));
          await t.pump();
          p.update(() => p.visible = false);
          await t.pump();
          if (failed) {
            p.port.pendingRead!.completeError(
              const LocalHangarFailure('hangar.read_unavailable'),
            );
          } else {
            p.port.pendingRead!.complete(hangarInventory(revision: 2));
          }
          await t.pumpAndSettle();
          expect(find.text('away'), findsOneWidget);
          expect(hangarKey('local-hangar-ship-alpha'), findsNothing);
          expect(p.port.saves, 0);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
