import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scope_sections.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';

import '../../features/settings/community_sharing_test.dart'
    show SharingFixture, target;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bi_test.dart' show input;

Widget section(
  LocalPrivacyController c,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) => scopedApp(
  ListenableBuilder(
    listenable: c,
    builder: (context, _) => SingleChildScrollView(
      child: c.draft == null
          ? const Text('owner unavailable')
          : LocalPrivacyOrganizationsSection(controller: c),
    ),
  ),
  suite,
  reduce: reduce,
  light: light,
);

class HeldTargets extends SharingFixture {
  Completer<CommunitySharingTargets>? held;
  int reads = 0;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() {
    reads++;
    return held?.future ?? super.readCommunityTargets();
  }
}

Future<void> activate(WidgetTester t, String source, String id) async {
  await t.ensureVisible(find.byKey(Key(id)));
  await t.pump();
  await input(t, source, Key(id));
  await t.pumpAndSettle();
}

Future<void> cleanup(
  WidgetTester t,
  LocalPrivacyController c,
  SharingFixture p,
) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  c.dispose();
  await t.runAsync(p.close);
}

StarBridgeActionButton action(WidgetTester t, String id) => t.widget(
  find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.controlKey == Key(id),
  ),
);

void main() {
  for (final suite in InteractionSuite.values) {
    adjacent(suite);
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source legacy migration is typed, cancellable and staged only',
        (t) async {
          final p = SharingFixture(), c = LocalPrivacyController(p);
          final semantics = t.ensureSemantics();
          try {
            await c.refresh();
            final original = c.draft;
            await t.pumpWidget(section(c, suite));
            await t.pumpAndSettle();
            expect(
              action(t, 'privacy-organizations-migrate').onActivate,
              isNotNull,
            );
            await activate(t, source, 'privacy-organizations-migrate');
            final route = ModalRoute.of(
              t.element(
                find.byKey(const Key('privacy-organizations-migrate-confirm')),
              ),
            );
            expect(route, isA<StarBridgeDialogRoute<bool>>());
            expect(
              (route as StarBridgeDialogRoute).instant,
              source != 'pointer',
            );
            expect(identical(c.draft, original), isTrue);
            expect(p.writes, 0);
            expect(p.applies, 0);
            await activate(t, source, 'privacy-organizations-migrate-cancel');
            expect(identical(c.draft, original), isTrue);
            await activate(t, source, 'privacy-organizations-migrate');
            await activate(t, source, 'privacy-organizations-migrate-confirm');
            expect(c.draft!.communities, isNotNull);
            expect(c.dirty, isTrue);
            expect(p.writes, 0);
            expect(p.applies, 0);
            final staged = c.draft;
            p.failSave = true;
            expect(await c.save(), isFalse);
            expect(identical(c.draft, staged), isTrue);
            p.failSave = false;
            expect(await c.save(), isTrue);
            expect(p.writes, 1);
          } finally {
            await cleanup(t, c, p);
            semantics.dispose();
          }
        },
      );
      testWidgets('$suite $source explicit closed choice is not publication', (
        t,
      ) async {
        final p = SharingFixture(), c = LocalPrivacyController(p);
        final semantics = t.ensureSemantics();
        try {
          await c.refresh();
          c.enableCommunityChoices();
          await t.pumpWidget(section(c, suite));
          await t.pumpAndSettle();
          expect(
            action(t, 'privacy-scope-B-confirm-none').onActivate,
            isNotNull,
          );
          await activate(t, source, 'privacy-scope-B-confirm-none');
          final b = c.draft!.communities!.singleWhere((s) => s.code == 'B');
          expect(b.fields, 0);
          expect(b.toJson(), target('B').choice().toJson());
          expect(p.writes, 0);
          expect(p.applies, 0);
        } finally {
          await cleanup(t, c, p);
          semantics.dispose();
        }
      });
    }
    for (final cause in ['account', 'draft', 'membership', 'leave']) {
      testWidgets(
        '$suite $cause retires only its legacy confirmation and rejects stale activation',
        (t) async {
          final p = SharingFixture(), c = LocalPrivacyController(p);
          try {
            await c.refresh();
            await t.pumpWidget(section(c, suite));
            await t.pumpAndSettle();
            await activate(t, 'pointer', 'privacy-organizations-migrate');
            final stale = action(
              t,
              'privacy-organizations-migrate-confirm',
            ).onActivate!;
            if (cause == 'account') {
              p.events.add(null);
            } else if (cause == 'draft') {
              c.edit(c.draft!.copyWith(roomFields: 0));
            } else if (cause == 'membership') {
              p.targets = p.targets.renamed('A', 'same membership');
              await c.refreshCommunityTargets();
              expect(
                find.byKey(const Key('privacy-organizations-migrate-confirm')),
                findsOneWidget,
              );
              p.targets = CommunitySharingTargets(communities: [target('C')]);
              await c.refreshCommunityTargets();
            } else {
              await t.pumpWidget(scopedApp(const Text('next page'), suite));
            }
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('privacy-organizations-migrate-confirm')),
              findsNothing,
            );
            final draft = c.draft;
            stale(InteractionSource.pointer);
            await t.pumpAndSettle();
            expect(identical(c.draft, draft), isTrue);
            expect(p.writes, 0);
            expect(p.applies, 0);
          } finally {
            await cleanup(t, c, p);
          }
        },
      );
    }
  }
}

void adjacent(InteractionSuite suite) {
  for (final kind in ['migration', 'retry']) {
    testWidgets('$suite stale $kind entry cannot target a replacement owner', (
      t,
    ) async {
      final p = HeldTargets()..failTargets = kind == 'retry';
      final q = HeldTargets()..failTargets = kind == 'retry';
      final c = LocalPrivacyController(p), next = LocalPrivacyController(q);
      try {
        await c.refresh();
        await next.refresh();
        await t.pumpWidget(section(c, suite));
        await t.pumpAndSettle();
        final id = kind == 'retry'
            ? 'privacy-organizations-retry'
            : 'privacy-organizations-migrate';
        final stale = action(t, id).onActivate!;
        await t.pumpWidget(section(next, suite));
        await t.pumpAndSettle();
        final reads = q.reads, draft = next.draft;
        stale(InteractionSource.pointer);
        await t.pumpAndSettle();
        expect(q.reads, reads);
        expect(identical(next.draft, draft), isTrue);
        expect(
          find.byKey(const Key('privacy-organizations-migrate-confirm')),
          findsNothing,
        );
        await activate(t, 'pointer', id);
        if (kind == 'retry') {
          expect(q.reads, reads + 1);
        } else {
          expect(
            find.byKey(const Key('privacy-organizations-migrate-confirm')),
            findsOneWidget,
          );
        }
      } finally {
        await cleanup(t, c, p);
        next.dispose();
        await t.runAsync(q.close);
      }
    });
  }
  for (final source in ['pointer', 'keyboard', 'reader']) {
    for (final failed in [false, true]) {
      testWidgets(
        '$suite $source held retry failed=$failed preserves draft and source feedback',
        (t) async {
          final p = HeldTargets()..failTargets = true;
          final c = LocalPrivacyController(p), semantics = t.ensureSemantics();
          try {
            await c.refresh();
            final draft = c.draft;
            await t.pumpWidget(section(c, suite));
            await t.pumpAndSettle();
            p.failTargets = false;
            p.held = Completer<CommunitySharingTargets>();
            await input(t, source, const Key('privacy-organizations-retry'));
            await t.pump();
            expect(action(t, 'privacy-organizations-retry').onActivate, isNull);
            final bar = find.byType(SuiteProgressBar);
            expect(bar, findsOneWidget);
            expect(
              InteractionScope.of(t.element(bar)).reduceMotion,
              source != 'pointer',
            );
            expect(p.reads, 2);
            expect(identical(c.draft, draft), isTrue);
            if (failed) {
              p.held!.completeError(StateError('still unavailable'));
            } else {
              p.held!.complete(p.targets);
            }
            p.held = null;
            await t.pumpAndSettle();
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(c.communityTargetsFailed, failed);
            if (failed) {
              expect(
                action(t, 'privacy-organizations-retry').onActivate,
                isNotNull,
              );
            }
            expect(identical(c.draft, draft), isTrue);
            expect(p.writes, 0);
            expect(p.applies, 0);
          } finally {
            await cleanup(t, c, p);
            semantics.dispose();
          }
        },
      );
    }
  }
  testWidgets('$suite owner replacement ignores late retry completion', (
    t,
  ) async {
    final oldPort = HeldTargets()..failTargets = true,
        newPort = SharingFixture();
    final old = LocalPrivacyController(oldPort),
        next = LocalPrivacyController(newPort);
    try {
      await old.refresh();
      await next.refresh();
      await t.pumpWidget(section(old, suite));
      await t.pumpAndSettle();
      oldPort.held = Completer<CommunitySharingTargets>();
      await input(t, 'pointer', const Key('privacy-organizations-retry'));
      await t.pump();
      await t.pumpWidget(section(next, suite));
      await t.pumpAndSettle();
      expect(find.byType(SuiteProgressBar), findsNothing);
      final draft = next.draft;
      oldPort.held!.completeError(StateError('late old retry'));
      oldPort.held = null;
      await t.pumpAndSettle();
      expect(next.communityTargetsFailed, isFalse);
      expect(identical(next.draft, draft), isTrue);
    } finally {
      await cleanup(t, old, oldPort);
      next.dispose();
      await t.runAsync(newPort.close);
    }
  });
  testWidgets('$suite invalidation never pops an unrelated newer dialog', (
    t,
  ) async {
    final p = SharingFixture(), c = LocalPrivacyController(p);
    try {
      await c.refresh();
      await t.pumpWidget(section(c, suite));
      await t.pumpAndSettle();
      await activate(t, 'pointer', 'privacy-organizations-migrate');
      final stale = action(
        t,
        'privacy-organizations-migrate-confirm',
      ).onActivate!;
      final context = t.element(
        find.byKey(const Key('privacy-organizations-migrate-confirm')),
      );
      unawaited(
        showStarBridgeDialog(
          context,
          builder: (_) =>
              const AlertDialog(content: Text('unrelated new dialog')),
        ),
      );
      await t.pumpAndSettle();
      c.edit(c.draft!.copyWith(roomFields: 0));
      await t.pumpAndSettle();
      stale(InteractionSource.pointer);
      await t.pumpAndSettle();
      expect(find.text('unrelated new dialog'), findsOneWidget);
      expect(
        find.byKey(const Key('privacy-organizations-migrate-confirm')),
        findsNothing,
      );
      expect(c.draft!.communities, isNull);
    } finally {
      await cleanup(t, c, p);
    }
  });
  testWidgets(
    '$suite live reduction/theme and Escape keep migration uncommitted',
    (t) async {
      final p = SharingFixture(), c = LocalPrivacyController(p);
      try {
        await c.refresh();
        await t.pumpWidget(section(c, suite));
        await t.pumpAndSettle();
        final draft = c.draft;
        await activate(t, 'pointer', 'privacy-organizations-migrate');
        await t.pumpWidget(section(c, suite, reduce: true, light: true));
        await t.pump();
        await t.pump();
        final context = t.element(
          find.byKey(const Key('privacy-organizations-migrate-confirm')),
        );
        expect(InteractionScope.of(context).reduceMotion, isTrue);
        expect(Theme.of(context).brightness, Brightness.light);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(
          find.byKey(const Key('privacy-organizations-migrate-confirm')),
          findsNothing,
        );
        expect(identical(c.draft, draft), isTrue);
        expect(p.writes, 0);
      } finally {
        await cleanup(t, c, p);
      }
    },
  );
}
