import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievement_idea_form.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3eo_test.dart'
    show IdeasProbe, CatalogProbe, activate, key;

const _catalog = [
  AchievementDefinition(
    id: 'future-0',
    nameKey: 'achievements.firstEntry.name',
    conditionKey: 'achievements.firstEntry.condition',
    memoryKey: 'achievements.firstEntry.memory',
    earnedAsset: 'assets/achievements/first-entry-earned.png',
    lockedAsset: 'assets/achievements/first-entry-locked.png',
  ),
  AchievementDefinition(
    id: 'future-1',
    nameKey: 'achievements.home.name',
    conditionKey: 'achievements.home.condition',
    memoryKey: 'achievements.home.memory',
    earnedAsset: 'assets/achievements/home-earned.png',
    lockedAsset: 'assets/achievements/home-locked.png',
  ),
];

StarBridgeDialogRoute<void> detailRoute(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(AchievementDetail)))!
        as StarBridgeDialogRoute<void>;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final finalSource in ['keyboard', 'reader', 'pointer']) {
      testWidgets('$suite discard final activation source wins: $finalSource', (
        t,
      ) async {
        size(t, const Size(1100, 950));
        final semantics = t.ensureSemantics();
        final account = ValueNotifier(achievementTestAccount(7));
        final ideas = IdeasProbe();
        try {
          await t.pumpWidget(
            scopedApp(AchievementsPage(account: account, ideas: ideas), suite),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-contribute'), 'pointer');
          await t.pumpAndSettle();
          final outer = ModalRoute.of(
            t.element(find.byType(AchievementIdeaForm)),
          )!;
          await t.enterText(key('achievement-idea-name'), 'Unsent voyage');
          await activate(
            t,
            key('achievement-idea-close'),
            finalSource == 'pointer' ? 'keyboard' : 'pointer',
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-idea-discard'), finalSource);
          if (finalSource == 'pointer') {
            expect(find.byType(AchievementIdeaForm), findsOneWidget);
            expect(outer.animation!.status, AnimationStatus.reverse);
          } else {
            expect(find.byType(AchievementIdeaForm), findsNothing);
          }
          await t.pumpAndSettle();
          expect(find.byType(AchievementIdeaForm), findsNothing);
          expect(ideas.receipts, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
          account.dispose();
        }
      });
    }

    for (final confirmation in [false, true]) {
      testWidgets(
        '$suite idea route follows live settings confirmation=$confirmation',
        (t) async {
          size(t, const Size(1100, 950));
          final account = ValueNotifier(achievementTestAccount(7));
          final ideas = IdeasProbe();
          var reduce = false, light = false;
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return scopedApp(
                    AchievementsPage(account: account, ideas: ideas),
                    suite,
                    reduce: reduce,
                    light: light,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-contribute'), 'pointer');
            if (confirmation) {
              await t.pumpAndSettle();
              await t.enterText(
                key('achievement-idea-name'),
                'Keep this draft',
              );
              await activate(t, key('achievement-idea-close'), 'pointer');
            }
            await t.pump(const Duration(milliseconds: 30));
            final context = t.element(
              confirmation
                  ? key('achievement-idea-keep')
                  : find.byType(AchievementIdeaForm),
            );
            final route = ModalRoute.of(context)!;
            expect(route, isA<StarBridgeDialogRoute>());
            update(() {
              reduce = true;
              light = true;
            });
            await t.pump();
            await t.pump();
            expect(route.animation!.value, 1);
            expect(InteractionScope.of(context).reduceMotion, isTrue);
            expect(InteractionScope.of(context).palette.isDark, isFalse);
            if (confirmation) {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pumpAndSettle();
              expect(key('achievement-idea-keep'), findsNothing);
              expect(
                t
                    .widget<TextFormField>(key('achievement-idea-name'))
                    .controller!
                    .text,
                'Keep this draft',
              );
            } else {
              await activate(t, key('achievement-idea-close'), 'keyboard');
              await t.pumpAndSettle();
              expect(find.byType(AchievementIdeaForm), findsNothing);
            }
            expect(ideas.receipts, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite detail keeps safe area and instant keyboard focus loop',
      (t) async {
        size(t, const Size(380, 900));
        t.view.padding = const FakeViewPadding(top: 52, bottom: 36);
        addTearDown(t.view.resetPadding);
        final account = ValueNotifier(achievementTestAccount(7));
        try {
          await t.pumpWidget(
            scopedApp(
              AchievementsPage(
                account: account,
                port: CatalogProbe(),
                catalog: _catalog,
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-entry-future-0'), 'keyboard');
          await t.pumpAndSettle();
          final dialog = t.getRect(find.byType(Dialog));
          expect(dialog.top, greaterThanOrEqualTo(52));
          expect(dialog.bottom, lessThanOrEqualTo(864));
          for (var i = 0; i < 10; i++) {
            await t.sendKeyEvent(LogicalKeyboardKey.tab);
            await t.pump();
            var inside = false;
            FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
              e,
            ) {
              inside |= e.widget is Dialog;
              return true;
            });
            expect(inside, isTrue);
          }
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.byType(AchievementDetail), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source achievement card retains focus and opens suite route',
        (t) async {
          size(t, const Size(1100, 950));
          final semantics = t.ensureSemantics();
          final account = ValueNotifier(achievementTestAccount(7));
          try {
            await t.pumpWidget(
              scopedApp(
                AchievementsPage(
                  account: account,
                  port: CatalogProbe(),
                  catalog: _catalog,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final first = key('achievement-entry-future-0');
            final original = t.widget<AchievementEntry>(first).focusNode;
            final rect = t.getRect(first);
            final target = source == 'reader'
                ? find.descendant(
                    of: first,
                    matching: find.byType(SuitePressable),
                  )
                : first;
            await activate(t, target, source);
            final route = detailRoute(t);
            expect(route.instant, source != 'pointer');
            expect(route.requestFocus, isTrue);
            expect(
              route.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-detail-next'), source);
            await t.pumpAndSettle();
            await activate(t, key('achievement-detail-close'), source);
            if (source != 'pointer') {
              expect(find.byType(AchievementDetail), findsNothing);
            }
            await t.pumpAndSettle();
            expect(t.widget<AchievementEntry>(first).focusNode, same(original));
            expect(
              t
                  .widget<AchievementEntry>(key('achievement-entry-future-1'))
                  .focusNode
                  .hasFocus,
              isTrue,
            );
            expect(t.getRect(first), rect);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
            account.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source idea and discard use suite routes without losing draft',
        (t) async {
          size(t, const Size(1100, 950));
          final semantics = t.ensureSemantics();
          final account = ValueNotifier(achievementTestAccount(7));
          final ideas = IdeasProbe();
          try {
            await t.pumpWidget(
              scopedApp(
                AchievementsPage(account: account, ideas: ideas),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-contribute'), source);
            final route =
                ModalRoute.of(t.element(find.byType(AchievementIdeaForm)))!
                    as StarBridgeDialogRoute<void>;
            expect(route.instant, source != 'pointer');
            expect(route.barrierDismissible, isFalse);
            expect(route.requestFocus, isTrue);
            expect(
              route.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            await t.pumpAndSettle();
            await t.enterText(key('achievement-idea-name'), 'My voyage');
            final editor = t
                .widget<TextFormField>(key('achievement-idea-name'))
                .controller!;
            final value = editor.value;
            await activate(t, key('achievement-idea-close'), source);
            final confirm =
                ModalRoute.of(t.element(key('achievement-idea-keep')))!
                    as StarBridgeDialogRoute<bool>;
            expect(confirm.instant, source != 'pointer');
            await t.pumpAndSettle();
            await activate(t, key('achievement-idea-keep'), source);
            await t.pumpAndSettle();
            expect(
              t.widget<TextFormField>(key('achievement-idea-name')).controller,
              same(editor),
            );
            expect(editor.value, value);
            await activate(t, key('achievement-idea-close'), source);
            await t.pumpAndSettle();
            await activate(t, key('achievement-idea-discard'), source);
            await t.pumpAndSettle();
            expect(find.byType(AchievementIdeaForm), findsNothing);
            expect(ideas.receipts, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
            account.dispose();
          }
        },
      );
    }

    for (final duringEntrance in [false, true]) {
      testWidgets(
        '$suite live settings settle detail and scrim within two frames entrance=$duringEntrance',
        (t) async {
          size(t, const Size(1100, 950));
          final account = ValueNotifier(achievementTestAccount(7));
          final port = CatalogProbe();
          var reduce = false, light = false;
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return scopedApp(
                    AchievementsPage(
                      account: account,
                      port: port,
                      catalog: _catalog,
                    ),
                    suite,
                    reduce: reduce,
                    light: light,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-entry-future-0'), 'pointer');
            if (duringEntrance) {
              await t.pump(const Duration(milliseconds: 35));
            } else {
              await t.pumpAndSettle();
            }
            final route = detailRoute(t);
            update(() {
              reduce = true;
              light = true;
            });
            await t.pump();
            await t.pump();
            expect(route.animation!.value, 1);
            final live = InteractionScope.of(
              t.element(find.byType(AchievementDetail)),
            );
            expect(live.reduceMotion, isTrue);
            expect(live.palette.isDark, isFalse);
            final scrims = t
                .widgetList<ModalBarrier>(find.byType(ModalBarrier))
                .where((b) => b.color != null);
            expect(
              scrims.any((b) => b.color == const Color(0x66000000)),
              isTrue,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(AchievementDetail), findsNothing);
            expect(port.reads, 1);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
          }
        },
      );
    }
  }
}
