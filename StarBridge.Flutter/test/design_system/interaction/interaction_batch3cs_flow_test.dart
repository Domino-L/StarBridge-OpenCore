import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

const opener = Key('notice-opener'), closer = Key('cig-fankit-notice-close');
SemanticsNode buttonNode(WidgetTester t, Key key, {bool actionable = true}) {
  final label = AppStrings.of(t.element(find.byKey(key)))
      .text(key == closer ? 'legal.close' : 'legal.fankit.inlineAction');
  final found = <SemanticsNode>[];
  final buttons = <String>[];
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    final data = node.getSemanticsData();
    if (data.flagsCollection.isButton) {
      buttons.add(
        '${data.label} tap=${data.hasAction(ui.SemanticsAction.tap)}',
      );
    }
    if (data.flagsCollection.isButton &&
        data.label == label &&
        (!actionable || data.hasAction(ui.SemanticsAction.tap))) {
      found.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.getSemantics(find.byKey(key)));
  expect(
    found,
    hasLength(1),
    reason: 'one button label=$label; observed=$buttons',
  );
  return found.single;
}

Future<void> activate(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key);
  switch (source) {
    case 'pointer':
      await t.tap(target);
    case 'keyboard':
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
    case 'reader':
      final node = buttonNode(t, key);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      t.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          viewId: t.view.viewId,
          nodeId: node.id,
        ),
      );
  }
  await t.pump();
  await t.pump();
}

Future<void> clean(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite actual notice opens and closes by $source', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(
            scopedApp(
              const Center(child: CigFankitNoticeButton(key: opener)),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(t, opener, source);
          final route =
              ModalRoute.of(t.element(find.byType(CigFankitNoticeContent)))!
                  as StarBridgeDialogRoute<void>;
          expect(route.instant, source != 'pointer');
          if (source != 'pointer') expect(route.animation!.value, 1);
          if (source == 'pointer') {
            expect(route.animation!.value, lessThan(1));
          }
          expect(
            t
                .widget<SelectableText>(
                  find.byKey(const Key('cig-fankit-required-notice')),
                )
                .data,
            CigFankitLegalNotice.requiredEnglish,
          );
          await t.pumpAndSettle();
          await activate(t, closer, source);
          if (source == 'pointer') {
            expect(find.byType(CigFankitNoticeContent), findsOneWidget);
            await t.pumpAndSettle();
          }
          expect(find.byType(CigFankitNoticeContent), findsNothing);
          if (source == 'keyboard') {
            expect(
              buttonNode(
                t,
                opener,
              ).getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.isTrue,
            );
          }
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
          await clean(t);
        }
      });
    }
    for (final method in ['escape', 'barrier']) {
      testWidgets('$suite actual notice dismisses by $method', (t) async {
        try {
          await t.pumpWidget(
            scopedApp(
              const Center(child: CigFankitNoticeButton(key: opener)),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(t, opener, 'pointer');
          await t.pumpAndSettle();
          if (method == 'escape') {
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
          } else {
            await t.tapAt(const Offset(2, 2));
            await t.pumpAndSettle();
          }
          expect(find.byType(CigFankitNoticeContent), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await clean(t);
        }
      });
    }
    for (final local in [false, true]) {
      testWidgets(
        '$suite notice live scope local=$local includes internal target',
        (t) async {
          var selected = suite, reduce = false, light = false;
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, state) {
                  update = state;
                  const body = Center(
                    child: CigFankitNoticeButton(key: opener),
                  );
                  return scopedApp(
                    local
                        ? StarBridgeInteractionConfiguration(
                            suite: selected,
                            reduceMotion: reduce,
                            child: body,
                          )
                        : body,
                    local ? InteractionSuite.standard : selected,
                    reduce: local ? false : reduce,
                    light: light,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            await activate(t, opener, 'pointer');
            expect(
              InteractionScope.of(t.element(find.byKey(closer))).suite,
              suite,
            );
            update(() {
              selected = suite == InteractionSuite.glow
                  ? InteractionSuite.scan
                  : InteractionSuite.glow;
              reduce = true;
              light = true;
            });
            await t.pump();
            await t.pump();
            final context = t.element(find.byKey(closer));
            final data = InteractionScope.of(context);
            expect(data.suite, selected);
            expect(data.reduceMotion, isTrue);
            expect(data.palette.brightness, Brightness.light);
            expect(ModalRoute.of(context)!.animation!.value, 1);
            await t.tap(find.byKey(closer));
            await t.pump();
            await t.pump();
            expect(find.byType(CigFankitNoticeContent), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await clean(t);
          }
        },
      );
    }
  }
}
