import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

bool _focusedInside(Finder finder) {
  final target = finder.evaluate().single;
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var inside = identical(context, target);
  context.visitAncestorElements((element) {
    inside |= identical(element, target);
    return !inside;
  });
  return inside;
}

Future<void> _activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    var steps = 0;
    while (!_focusedInside(target) && steps++ < 48) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(_focusedInside(target), isTrue);
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

EffectHostState? _effectFor(WidgetTester t, Finder target) {
  final host = find.ancestor(of: target, matching: find.byType(EffectHost));
  return host.evaluate().isEmpty ? null : t.state<EffectHostState>(host.first);
}

void _feedback(
  WidgetTester t,
  Finder target,
  InteractionSuite suite,
  bool animated,
) {
  final effect = switch (suite) {
    InteractionSuite.rail => TransientEffect.sweep,
    InteractionSuite.scan => TransientEffect.bracketFlash,
    InteractionSuite.glow => TransientEffect.ring,
    InteractionSuite.standard => null,
  };
  if (effect != null) {
    expect(_effectFor(t, target)?.isPlaying(effect) ?? false, animated);
  }
}

AchievementCollection _ready() => AchievementCollection(
  generation: 1,
  status: AchievementCollectionStatus.ready,
  earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite inspector hint does not consume its modal Escape', (
      t,
    ) async {
      size(t, const Size(1280, 900));
      var previous = 0;
      await t.pumpWidget(
        scopedApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AchievementDetail(
                  definition: achievementCatalog.first,
                  collection: _ready(),
                  index: 1,
                  total: 2,
                  onPrevious: () => previous++,
                ),
              ),
              child: const Text('open inspector'),
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('open inspector'));
      await t.pumpAndSettle();
      final target = find.byKey(const Key('achievement-detail-prev'));
      await _activate(t, target, 'keyboard');
      expect(previous, 1);
      final hint = find.ancestor(
        of: target,
        matching: find.byType(SuiteTooltip),
      );
      expect(t.state<SuiteTooltipState>(hint.first).isShowing, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('achievement-detail')), findsNothing);
      expect(previous, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $source achievement refresh retains its real owner', (
        t,
      ) async {
        size(t, const Size(1280, 900));
        final semantics = t.ensureSemantics();
        final account = ValueNotifier(achievementTestAccount(1));
        final port = DeferredAchievementPort();
        final session = AchievementCollectionSession(
          account: account,
          port: port,
        );
        try {
          await t.pumpWidget(
            scopedApp(
              AchievementsPage(account: account, port: port, session: session),
              suite,
            ),
          );
          await t.pump();
          expect(port.requests, hasLength(1));
          port.requests.single.completion.complete(_ready());
          await t.pumpAndSettle();
          final target = find.byKey(const Key('achievement-refresh'));
          final before = session.collection.value.earnedAt;
          // The existing loading indicator changes the header's vertical
          // placement. Preserve control geometry, not an unrelated page offset.
          final bounds = t.getSize(target);
          await _activate(t, target, source);
          expect(port.requests, hasLength(2));
          expect(session.collection.value.isRefreshing, isTrue);
          expect(session.collection.value.earnedAt, before);
          expect(t.widget<IconButton>(target).onPressed, isNull);
          expect(t.getSize(target), bounds);
          _feedback(t, target, suite, source == 'pointer');
          port.requests.last.completion.completeError(
            TimeoutException('fixture'),
          );
          await t.pumpAndSettle();
          expect(session.collection.value.refreshFailed, isTrue);
          expect(session.collection.value.earnedAt, before);
          expect(t.widget<IconButton>(target).onPressed, isNotNull);
          await _activate(t, target, source);
          expect(port.requests, hasLength(3));
          port.requests.last.completion.complete(_ready());
          await t.pumpAndSettle();
          expect(session.collection.value.refreshFailed, isFalse);
          expect(session.collection.value.earnedAt, before);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          session.dispose();
          account.dispose();
          semantics.dispose();
        }
      });

      testWidgets(
        '$suite $source inspector arrows keep every explicit action',
        (t) async {
          size(t, const Size(1280, 900));
          final semantics = t.ensureSemantics();
          var previous = 0, next = 0;
          try {
            await t.pumpWidget(
              scopedApp(
                AchievementDetail(
                  definition: achievementCatalog.first,
                  collection: _ready(),
                  index: 1,
                  total: 3,
                  onPrevious: () => previous++,
                  onNext: () => next++,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final back = find.byKey(const Key('achievement-detail-prev'));
            final forward = find.byKey(const Key('achievement-detail-next'));
            final before = t.getRect(forward);
            await _activate(t, forward, source);
            expect(next, 1);
            _feedback(t, forward, suite, source == 'pointer');
            for (var i = 0; i < 3; i++) {
              await _activate(t, forward, source);
            }
            expect(next, 4, reason: 'Active input must not be coalesced.');
            expect(t.getRect(forward), before);
            await _activate(t, back, source);
            expect(previous, 1);
            _feedback(t, back, suite, source == 'pointer');
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets('$suite live reduced motion retires arrow feedback', (t) async {
      size(t, const Size(1280, 900));
      var next = 0;
      var reduce = false;
      late StateSetter update;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return scopedApp(
              AchievementDetail(
                definition: achievementCatalog.first,
                collection: _ready(),
                total: 2,
                onNext: () => next++,
              ),
              suite,
              reduce: reduce,
            );
          },
        ),
      );
      await t.pumpAndSettle();
      final target = find.byKey(const Key('achievement-detail-next'));
      await _activate(t, target, 'pointer');
      _feedback(t, target, suite, true);
      update(() => reduce = true);
      await t.pump();
      await t.pump();
      _feedback(t, target, suite, false);
      await _activate(t, target, 'pointer');
      expect(next, 2);
      _feedback(t, target, suite, false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
