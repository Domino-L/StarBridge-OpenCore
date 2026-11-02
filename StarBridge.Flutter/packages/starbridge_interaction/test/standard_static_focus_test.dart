import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget app({
  required PressableKind kind,
  required bool reduce,
  FocusNode? node,
  FocusNode? next,
  ValueChanged<InteractionSource>? activate,
  InteractionSuite suite = InteractionSuite.standard,
}) => InteractionScope(
  data: InteractionData(suite: suite, reduceMotion: reduce, palette: palette),
  child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuitePressable(
              key: const Key('target'),
              kind: kind,
              focusNode: node,
              semanticLabel: 'Target',
              padding: const EdgeInsets.all(12),
              onActivate: activate,
              child: const Text('Target'),
            ),
            if (next != null)
              Focus(focusNode: next, child: const Text('Other')),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  for (final kind in PressableKind.values) {
    testWidgets('$kind reduced focus return and pointer/reader are static', (
      t,
    ) async {
      final node = FocusNode(), next = FocusNode();
      addTearDown(node.dispose);
      addTearDown(next.dispose);
      final sources = <InteractionSource>[];
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(
          app(
            kind: kind,
            reduce: true,
            node: node,
            next: next,
            activate: sources.add,
          ),
        );
        await t.pumpAndSettle();
        node.requestFocus();
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(sources, [InteractionSource.keyboard]);
        next.requestFocus();
        await t.pumpAndSettle();
        node.requestFocus();
        await t.pump();
        await t.pump();
        expect(node.hasFocus, isTrue);
        expect(t.hasRunningAnimations, isFalse);
        final exposed = t.getSemantics(find.byKey(const Key('target')));
        t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          exposed.id,
          SemanticsAction.tap,
        );
        await t.pump();
        await t.pump();
        await t.tap(find.byKey(const Key('target')));
        await t.pump();
        await t.pump();
        expect(sources, [
          InteractionSource.keyboard,
          InteractionSource.keyboard,
          InteractionSource.pointer,
        ]);
        expect(t.hasRunningAnimations, isFalse);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
  for (final kind in [
    PressableKind.primary,
    PressableKind.row,
    PressableKind.icon,
  ]) {
    testWidgets(
      '$kind normal pointer feedback survives; live reduce clears old ink',
      (t) async {
        var reduce = false;
        late StateSetter update;
        final node = FocusNode();
        addTearDown(node.dispose);
        final sources = <InteractionSource>[];
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setter) {
              update = setter;
              return app(
                kind: kind,
                reduce: reduce,
                node: node,
                activate: sources.add,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        node.requestFocus();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('target')));
        await t.pump(const Duration(milliseconds: 35));
        expect(t.hasRunningAnimations, isTrue);
        expect(node.hasFocus, isTrue);
        update(() => reduce = true);
        await t.pump();
        await t.pump();
        expect(node.hasFocus, isTrue);
        expect(t.hasRunningAnimations, isFalse);
        expect(sources, [InteractionSource.pointer]);
        update(() => reduce = false);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('target')));
        await t.pump(const Duration(milliseconds: 35));
        expect(t.hasRunningAnimations, isTrue);
        expect(sources, [InteractionSource.pointer, InteractionSource.pointer]);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('default focus owner survives reduction and suite switches', (
    t,
  ) async {
    var reduce = false, suite = InteractionSuite.standard;
    late StateSetter update;
    await t.pumpWidget(
      StatefulBuilder(
        builder: (_, setter) {
          update = setter;
          return app(
            kind: PressableKind.row,
            reduce: reduce,
            suite: suite,
            activate: (_) {},
          );
        },
      ),
    );
    await t.pumpAndSettle();
    FocusNode owner() => t
        .widget<FocusableActionDetector>(
          find
              .descendant(
                of: find.byKey(const Key('target')),
                matching: find.byType(FocusableActionDetector),
              )
              .first,
        )
        .focusNode!;
    final node = owner();
    node.requestFocus();
    await t.pumpAndSettle();
    update(() => reduce = true);
    await t.pump();
    await t.pump();
    expect(owner(), same(node));
    expect(node.hasFocus, isTrue);
    for (final next in InteractionSuite.values) {
      update(() => suite = next);
      await t.pumpAndSettle();
      expect(owner(), same(node));
      expect(node.hasFocus, isTrue);
    }
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
