import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'actual material notice opener uses the selected rail transition',
    (t) async {
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
      });
      await t.pumpWidget(
        scopedApp(
          const Center(child: CigFankitNoticeButton(key: Key('notice-opener'))),
          InteractionSuite.rail,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('notice-opener')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      final route = ModalRoute.of(
        t.element(find.byType(CigFankitNoticeContent)),
      );
      expect(route, isA<StarBridgeDialogRoute<void>>());
      expect(find.byType(SuiteSurfaceTransition), findsOneWidget);
    },
  );
  testWidgets(
    'actual keyboard material notice opens without an animation tail',
    (t) async {
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
      });
      await t.pumpWidget(
        scopedApp(
          const Center(child: CigFankitNoticeButton(key: Key('notice-opener'))),
          InteractionSuite.rail,
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump();
      final route = ModalRoute.of(
        t.element(find.byType(CigFankitNoticeContent)),
      )!;
      expect(route.animation!.value, 1);
    },
  );
  testWidgets('notice internal controls follow the opener local live scope', (
    t,
  ) async {
    var suite = InteractionSuite.rail, reduce = false;
    late StateSetter update;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
    await t.pumpWidget(
      StatefulBuilder(
        builder: (_, state) {
          update = state;
          return scopedApp(
            StarBridgeInteractionConfiguration(
              suite: suite,
              reduceMotion: reduce,
              child: const Center(
                child: CigFankitNoticeButton(key: Key('notice-opener')),
              ),
            ),
            InteractionSuite.standard,
          );
        },
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('notice-opener')));
    await t.pump();
    final close = find.byKey(const Key('cig-fankit-notice-close'));
    expect(InteractionScope.of(t.element(close)).suite, InteractionSuite.rail);
    update(() {
      suite = InteractionSuite.glow;
      reduce = true;
    });
    await t.pump();
    await t.pump();
    final data = InteractionScope.of(t.element(close));
    expect(data.suite, InteractionSuite.glow);
    expect(data.reduceMotion, isTrue);
    expect(ModalRoute.of(t.element(close))!.animation!.value, 1);
  });
  testWidgets('actual keyboard close removes the material notice immediately', (
    t,
  ) async {
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        scopedApp(
          const Center(child: CigFankitNoticeButton(key: Key('notice-opener'))),
          InteractionSuite.rail,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('notice-opener')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(
        t
            .getSemantics(find.byKey(const Key('cig-fankit-notice-close')))
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        ui.Tristate.isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump();
      expect(find.byType(CigFankitNoticeContent), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
