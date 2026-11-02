import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievement_idea_form.dart';
import 'package:starbridge_flutter/features/achievements/achievement_ideas_port.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

class IdeasProbe implements AchievementIdeasPort {
  @override
  bool get available => true;
  @override
  bool get canPickImage => true;
  final receipts = <String>[];
  final drafts = <(int, String, String)>[];
  Completer<void> pending = Completer();
  @override
  Future<String?> pickImage({required int generation}) async => null;
  @override
  Future<void> submit({
    required int generation,
    required String submissionId,
    required String name,
    required String condition,
    String? imageData,
  }) {
    receipts.add(submissionId);
    drafts.add((generation, name, condition));
    return pending.future;
  }
}

class CatalogProbe implements AchievementCollectionPort {
  var reads = 0;
  @override
  Future<AchievementCollection> read({required int generation}) async {
    reads++;
    return AchievementCollection(
      generation: generation,
      status: AchievementCollectionStatus.ready,
      earnedAt: {
        for (var i = 0; i < 30; i++) 'future-$i': DateTime.utc(2026, 10, 1),
      },
    );
  }
}

bool _inside(Finder target) {
  final wanted = target.evaluate().single;
  final context = FocusManager.instance.primaryFocus?.context;
  var found = identical(context, wanted);
  context?.visitAncestorElements((element) {
    found |= identical(element, wanted);
    return !found;
  });
  return found;
}

Future<void> activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    for (var i = 0; !_inside(target) && i < 64; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(_inside(target), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (source == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else {
    await t.tap(target);
  }
  await t.pump();
}

Finder key(String name) => find.byKey(Key(name));

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite account invalidation retires only its idea and late receipt',
      (t) async {
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(7));
        final port = IdeasProbe();
        try {
          await t.pumpWidget(
            scopedApp(AchievementsPage(account: account, ideas: port), suite),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-contribute'), 'pointer');
          await t.pumpAndSettle();
          await t.enterText(key('achievement-idea-name'), 'Old generation');
          await t.enterText(key('achievement-idea-condition'), 'Old draft');
          await activate(t, key('achievement-idea-submit'), 'pointer');
          expect(port.drafts, [(7, 'Old generation', 'Old draft')]);
          final old = port.pending;
          account.value = achievementTestAccount(8);
          await t.pumpAndSettle();
          expect(find.byType(AchievementIdeaForm), findsNothing);
          old.complete();
          await t.pumpAndSettle();
          expect(find.byType(AchievementIdeaForm), findsNothing);
          expect(port.receipts, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );

    testWidgets(
      '$suite reduce changes preserve the native draft editor and selection',
      (t) async {
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(7));
        final port = IdeasProbe();
        var reduce = false;
        late StateSetter update;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return scopedApp(
                  AchievementsPage(account: account, ideas: port),
                  suite,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-contribute'), 'pointer');
          await t.pumpAndSettle();
          await t.enterText(key('achievement-idea-condition'), 'Unsent voyage');
          final controller = t
              .widget<TextFormField>(key('achievement-idea-condition'))
              .controller!;
          final value = controller.value;
          update(() => reduce = true);
          await t.pump();
          await t.pump();
          expect(
            t
                .widget<TextFormField>(key('achievement-idea-condition'))
                .controller,
            same(controller),
          );
          expect(controller.value, value);
          update(() => reduce = false);
          await t.pumpAndSettle();
          expect(controller.value, value);
          expect(port.receipts, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );

    testWidgets(
      '$suite directory choices retain the original read-only collection',
      (t) async {
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(9));
        final port = CatalogProbe();
        final catalog = List.generate(
          30,
          (i) => AchievementDefinition(
            id: 'future-$i',
            nameKey: 'Future $i',
            conditionKey: 'Requirement $i',
            memoryKey: achievementCatalog.first.memoryKey,
            earnedAsset: achievementCatalog.first.earnedAsset,
            lockedAsset: achievementCatalog.first.lockedAsset,
            groupId: 'g${i % 4}',
            groupNameKey: 'Group ${i % 4}',
            target: 100,
          ),
        );
        try {
          await t.pumpWidget(
            scopedApp(
              AchievementsPage(account: account, port: port, catalog: catalog),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-group-earned'), 'pointer');
          await t.pumpAndSettle();
          expect(find.byType(AchievementEntry), findsNWidgets(24));
          await activate(t, key('achievement-show-more'), 'keyboard');
          await t.pumpAndSettle();
          expect(find.byType(AchievementEntry), findsNWidgets(30));
          await activate(t, key('achievement-filter-locked'), 'pointer');
          await t.pumpAndSettle();
          expect(find.byType(AchievementEntry), findsNothing);
          await activate(t, key('achievement-filter-all'), 'keyboard');
          await t.pumpAndSettle();
          expect(find.byType(AchievementEntry), findsNWidgets(24));
          size(t, const Size(380, 950));
          await t.pumpAndSettle();
          final picker = t.widget<StarBridgeSelectFormField<String>>(
            find.byType(StarBridgeSelectFormField<String>),
          );
          expect(
            picker.items!
                .singleWhere((item) => item.value == 'source-bridge')
                .enabled,
            isFalse,
          );
          await activate(t, key('achievement-group-control'), 'pointer');
          await t.pumpAndSettle();
          final option = find.byKey(
            const ValueKey<Object>(('achievement-groups', 'bridge:g0')),
          );
          for (var i = 0; !_inside(option) && i < 16; i++) {
            await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await t.pump();
          }
          expect(_inside(option), isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pumpAndSettle();
          expect(find.byType(AchievementEntry), findsNWidgets(8));
          expect(
            port.reads,
            1,
            reason: 'Browsing must not synchronize or write awards.',
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source idea draft retry and discard remain authoritative',
        (t) async {
          size(t, const Size(1100, 950));
          final semantics = t.ensureSemantics();
          final account = ValueNotifier(achievementTestAccount(7));
          final port = IdeasProbe();
          try {
            await t.pumpWidget(
              scopedApp(AchievementsPage(account: account, ideas: port), suite),
            );
            await t.pumpAndSettle();
            final opener = key('achievement-contribute');
            if (suite != InteractionSuite.standard && source == 'pointer') {
              expect(t.widget(opener), isA<SuitePressable>());
            }
            await activate(t, opener, source);
            await t.pumpAndSettle();
            expect(find.byType(AchievementIdeaForm), findsOneWidget);
            await t.enterText(key('achievement-idea-name'), '  Test voyage  ');
            await t.enterText(
              key('achievement-idea-condition'),
              '  Reach a port  ',
            );
            await activate(t, key('achievement-idea-submit'), source);
            expect(port.drafts, [(7, 'Test voyage', 'Reach a port')]);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(AchievementIdeaForm), findsOneWidget);
            expect(
              t
                  .getSemantics(key('achievement-idea-submit'))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
            port.pending.completeError(
              const AchievementIdeaFailure('unconfirmed'),
            );
            await t.pumpAndSettle();
            expect(
              t
                  .widget<TextFormField>(key('achievement-idea-name'))
                  .controller!
                  .text,
              '  Test voyage  ',
            );
            await activate(t, key('achievement-idea-close'), source);
            await t.pumpAndSettle();
            expect(find.text('放弃这次填写？'), findsOneWidget);
            await activate(t, key('achievement-idea-keep'), source);
            await t.pumpAndSettle();
            expect(
              t
                  .widget<TextFormField>(key('achievement-idea-condition'))
                  .controller!
                  .text,
              '  Reach a port  ',
            );
            port.pending = Completer();
            await activate(t, key('achievement-idea-submit'), source);
            expect(port.receipts, hasLength(2));
            expect(port.receipts.first, port.receipts.last);
            port.pending.complete();
            await t.pumpAndSettle();
            expect(key('achievement-idea-submit'), findsNothing);
            await activate(t, key('achievement-idea-close'), source);
            await t.pumpAndSettle();
            expect(find.byType(AchievementIdeaForm), findsNothing);
          await activate(t, opener, source);
          await t.pumpAndSettle();
          await t.enterText(key('achievement-idea-name'), 'Discarded draft');
          await activate(t, key('achievement-idea-close'), source);
          await t.pumpAndSettle();
          await activate(t, key('achievement-idea-discard'), source);
          await t.pumpAndSettle();
          expect(find.byType(AchievementIdeaForm), findsNothing);
          expect(port.receipts, hasLength(2));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
            semantics.dispose();
          }
        },
      );

      testWidgets('$suite $source signed-out entry keeps sign-in owner', (
        t,
      ) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final account = ValueNotifier(
          achievementTestAccount(8, signedIn: false),
        );
        var signs = 0;
        try {
          await t.pumpWidget(
            scopedApp(
              AchievementsPage(account: account, onSignIn: () => signs++),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-sign-in'), source);
          expect(signs, 1);
          await activate(t, key('achievement-contribute'), source);
          expect(signs, 2);
          expect(find.byType(AchievementIdeaForm), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
          semantics.dispose();
        }
      });
    }
  }
}
