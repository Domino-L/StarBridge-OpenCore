import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_idea_form.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart'
    show IdeasProbe, CatalogProbe, activate, key;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final closing in [false, true]) {
      testWidgets(
        '$suite account invalidation keeps unrelated top route closing=$closing',
        (t) async {
          size(t, const Size(1100, 950));
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
            await activate(t, key('achievement-contribute'), 'pointer');
            await t.pumpAndSettle();
            await t.enterText(key('achievement-idea-name'), 'Old draft');
            await activate(t, key('achievement-idea-close'), 'pointer');
            await t.pumpAndSettle();
            final navigator = Navigator.of(
              t.element(key('achievement-idea-keep')),
            );
            if (closing) {
              await activate(t, key('achievement-idea-keep'), 'pointer');
              await t.pump(const Duration(milliseconds: 25));
            }
            final other = PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) =>
                  const Scaffold(body: Text('Unrelated route')),
            );
            navigator.push(other);
            await t.pump();
            account.value = achievementTestAccount(8);
            await t.pump();
            await t.pump();
            expect(other.isCurrent, isTrue);
            expect(find.text('Unrelated route'), findsOneWidget);
            expect(key('achievement-idea-keep'), findsNothing);
            expect(find.byType(AchievementIdeaForm), findsNothing);
            navigator.pop();
            await t.pumpAndSettle();
            await activate(t, key('achievement-contribute'), 'keyboard');
            await t.pumpAndSettle();
            expect(
              t
                  .widget<TextFormField>(key('achievement-idea-name'))
                  .controller!
                  .text,
              isEmpty,
            );
            expect(ideas.receipts, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
          }
        },
      );

      testWidgets(
        '$suite page detach retires detail including exit closing=$closing',
        (t) async {
          size(t, const Size(1100, 950));
          final account = ValueNotifier(achievementTestAccount(7));
          final visible = ValueNotifier(true);
          final port = CatalogProbe();
          try {
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, _) => show
                      ? AchievementsPage(account: account, port: port)
                      : const Text('Other destination'),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-entry-first-entry'), 'pointer');
            await t.pumpAndSettle();
            final route =
                ModalRoute.of(t.element(find.byType(AchievementDetail)))!
                    as StarBridgeDialogRoute<void>;
            var detached = false;
            route.completed.then((_) => detached = true);
            if (closing) {
              await activate(t, key('achievement-detail-close'), 'pointer');
              await t.pump(const Duration(milliseconds: 25));
            }
            visible.value = false;
            await t.pump();
            await t.pump();
            expect(find.byType(AchievementDetail), findsNothing);
            expect(detached, isTrue);
            expect(find.text('Other destination'), findsOneWidget);
            expect(port.reads, 1);
            retireStarBridgeDialog(route, includeClosing: true);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            visible.dispose();
            account.dispose();
          }
        },
      );
    }

    for (final idea in [false, true]) {
      for (final closing in [false, true]) {
        testWidgets(
          '$suite replacing account listenable retires owned routes idea=$idea closing=$closing',
          (t) async {
            size(t, const Size(1100, 950));
            final first = ValueNotifier(achievementTestAccount(7)),
                second = ValueNotifier(achievementTestAccount(8));
            var account = first;
            final port = CatalogProbe(), ideas = IdeasProbe();
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
                        ideas: ideas,
                      ),
                      suite,
                    );
                  },
                ),
              );
              await t.pumpAndSettle();
              if (idea) {
                await activate(t, key('achievement-contribute'), 'pointer');
                await t.pumpAndSettle();
                await t.enterText(
                  key('achievement-idea-name'),
                  'Old listenable draft',
                );
                await activate(t, key('achievement-idea-close'), 'pointer');
              } else {
                await activate(
                  t,
                  key('achievement-entry-first-entry'),
                  'pointer',
                );
              }
              await t.pumpAndSettle();
              if (closing) {
                await activate(
                  t,
                  key(
                    idea ? 'achievement-idea-keep' : 'achievement-detail-close',
                  ),
                  'pointer',
                );
                await t.pump(const Duration(milliseconds: 25));
              }
              update(() => account = second);
              await t.pump();
              await t.pump();
              expect(find.byType(AchievementIdeaForm), findsNothing);
              expect(find.byType(AchievementDetail), findsNothing);
              expect(key('achievement-idea-keep'), findsNothing);
              expect(port.reads, 2);
              expect(ideas.receipts, isEmpty);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              first.dispose();
              second.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite changing generation retires a reversing detail while page stays mounted',
      (t) async {
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(7));
        final port = CatalogProbe();
        try {
          await t.pumpWidget(
            scopedApp(AchievementsPage(account: account, port: port), suite),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-entry-first-entry'), 'pointer');
          await t.pumpAndSettle();
          await activate(t, key('achievement-detail-close'), 'pointer');
          await t.pump(const Duration(milliseconds: 25));
          account.value = achievementTestAccount(8);
          await t.pump();
          await t.pump();
          expect(find.byType(AchievementDetail), findsNothing);
          expect(find.byType(AchievementsPage), findsOneWidget);
          expect(port.reads, 2);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );
    for (final closing in [false, true]) {
      for (final leave in [false, true]) {
        testWidgets(
          '$suite confirmation cleanup closing=$closing leave=$leave',
          (t) async {
            size(t, const Size(1100, 950));
            final account = ValueNotifier(achievementTestAccount(7));
            final visible = ValueNotifier(true);
            final ideas = IdeasProbe();
            try {
              await t.pumpWidget(
                scopedApp(
                  ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, show, _) => show
                        ? AchievementsPage(account: account, ideas: ideas)
                        : const Text('Other destination'),
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              await activate(t, key('achievement-contribute'), 'pointer');
              await t.pumpAndSettle();
              await t.enterText(
                key('achievement-idea-name'),
                'Unsent old generation',
              );
              await activate(t, key('achievement-idea-close'), 'pointer');
              await t.pumpAndSettle();
              final route =
                  ModalRoute.of(t.element(key('achievement-idea-keep')))!
                      as StarBridgeDialogRoute<bool>;
              var detached = false;
              route.completed.then((_) => detached = true);
              if (closing) {
                await activate(t, key('achievement-idea-keep'), 'pointer');
                expect(route.animation!.status, AnimationStatus.reverse);
                await t.pump(const Duration(milliseconds: 25));
              }
              if (leave) {
                visible.value = false;
              } else {
                account.value = achievementTestAccount(8);
              }
              await t.pump();
              await t.pump();
              expect(key('achievement-idea-keep'), findsNothing);
              expect(key('achievement-idea-discard'), findsNothing);
              expect(find.byType(AchievementIdeaForm), findsNothing);
              expect(detached, isTrue);
              retireStarBridgeDialog(route, includeClosing: true);
              route.finishKeyboardExit();
              expect(ideas.receipts, isEmpty);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              visible.dispose();
              account.dispose();
            }
          },
        );
      }
    }
  }
}
