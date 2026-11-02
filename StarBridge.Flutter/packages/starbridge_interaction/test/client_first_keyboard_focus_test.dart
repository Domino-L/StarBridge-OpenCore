import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'standard_static_focus_test.dart' show app;
import 'boundary_test.dart' show palette;

void main() {
  for (final kind in PressableKind.values) {
    testWidgets('$kind standard focus semantics reflects the actual owner', (
      t,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        app(kind: kind, reduce: false, node: node, activate: (_) {}),
      );
      await t.pumpAndSettle();
      final target = find.byKey(const Key('target'));
      var data = t.getSemantics(target).getSemanticsData();
      expect(data.flagsCollection.isFocused, isNot(Tristate.none));
      expect(data.hasAction(SemanticsAction.focus), isTrue);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        t.getSemantics(target).id,
        SemanticsAction.focus,
      );
      await t.pump();
      expect(node.hasFocus, isTrue);
      // Focus commits immediately; its listening semantic widget rebuilds
      // on the next frame, as with Flutter's unmodified Focus widget.
      await t.pump();
      data = t.getSemantics(target).getSemanticsData();
      expect(data.flagsCollection.isFocused, Tristate.isTrue);
      node.unfocus();
      await t.pump();
      await t.pump();
      expect(
        t.getSemantics(target).getSemanticsData().flagsCollection.isFocused,
        Tristate.isFalse,
      );
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets(
        '$kind first $key after pointer has static focus and no ink',
        (t) async {
          final node = FocusNode();
          addTearDown(node.dispose);
          final sources = <InteractionSource>[];
          await t.pumpWidget(
            app(kind: kind, reduce: false, node: node, activate: sources.add),
          );
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('target')));
          await t.pumpAndSettle();
          expect(sources, [InteractionSource.pointer]);
          expect(node.hasFocus, isTrue);
          sources.clear();
          await t.sendKeyEvent(key);
          await t.pump();
          expect(sources, [InteractionSource.keyboard]);
          expect(node.hasFocus, isTrue);
          final base = switch (kind) {
            PressableKind.primary => palette.accent,
            PressableKind.danger => palette.danger,
            PressableKind.secondary || PressableKind.card => palette.raised,
            _ => Colors.transparent,
          };
          final focusColor = switch (kind) {
            PressableKind.primary => palette.onAccent,
            PressableKind.danger => palette.onDanger,
            PressableKind.secondary || PressableKind.icon => palette.accent,
            _ => palette.focusRing,
          };
          final ink =
              t.widget<Ink>(find.byType(Ink).first).decoration as BoxDecoration;
          expect(
            ink.color,
            Color.alphaBlend(focusColor.withValues(alpha: 0.14), base),
            reason: 'Keep original native button/row focus contrast when making it immediate.',
          );
          expect(
            t.hasRunningAnimations,
            isFalse,
            reason: 'First keyboard input must not start native focus ink, not merely skip its ripple.',
          );
          await t.pump(const Duration(milliseconds: 80));
          expect(t.hasRunningAnimations, isFalse);
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('$kind disabled pointer has no native splash or focus', (
      t,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await t.pumpWidget(app(kind: kind, reduce: false, node: node));
      await t.pumpAndSettle();
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(const Key('target'))),
      );
      await t.pump(const Duration(milliseconds: 35));
      expect(t.hasRunningAnimations, isFalse);
      expect(node.hasFocus, isFalse);
      await gesture.up();
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      expect(t.widget<InkWell>(find.byType(InkWell)).onTapDown, isNull);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  }
}
