import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final selected in [false, true]) {
      testWidgets(
        '$suite shared visual track has explicit selected semantics $selected',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final calls = <InteractionSource>[];
            await t.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: InteractionScope(
                    data: InteractionData(suite: suite, palette: palette),
                    child: SuitePressable(
                      key: const Key('target'),
                      kind: PressableKind.navItem,
                      selected: false,
                      semanticSelected: selected,
                      semanticFocused: true,
                      semanticLabel: 'Destination, 42',
                      excludeChildSemantics: true,
                      onActivate: calls.add,
                      child: const SizedBox(
                        width: 210,
                        height: 44,
                        child: Text('Destination, 42'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            final node = t.getSemantics(find.byKey(const Key('target')));
            final data = node.getSemanticsData();
            expect(data.label, 'Destination, 42');
            expect(
              data.flagsCollection.isSelected,
              selected ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(data.flagsCollection.isFocused, Tristate.isTrue);
            expect(data.hasAction(SemanticsAction.tap), true);
            await t.tap(find.byKey(const Key('target')));
            await t.pump();
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              node.id,
              SemanticsAction.tap,
            );
            expect(calls, [
              InteractionSource.pointer,
              InteractionSource.keyboard,
            ]);
            await t.pump();
            await t.pump();
            if (suite != InteractionSuite.standard) {
              expect(
                t.hasRunningAnimations,
                false,
                reason: 'Reader clears earlier pointer feedback, not a separate bypass',
              );
            }
            await t.pumpAndSettle();
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
