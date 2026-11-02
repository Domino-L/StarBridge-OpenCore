import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final enabled in [true, false]) {
      testWidgets(
        '$suite assistive activation is keyboard/static enabled=$enabled',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            final sources = <InteractionSource>[];
            await tester.pumpWidget(
              InteractionScope(
                data: InteractionData(suite: suite, palette: palette),
                child: MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: SuitePressable(
                        key: const Key('command'),
                        kind: PressableKind.primary,
                        semanticLabel: 'Activate command',
                        onActivate: enabled ? sources.add : null,
                        child: const Text('Activate command'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final node = tester.getSemantics(find.byKey(const Key('command')));
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              enabled,
            );
            if (enabled) {
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
              expect(sources, [InteractionSource.keyboard]);
              await tester.pump();
              await tester.pump();
              expect(tester.hasRunningAnimations, isFalse);
              await tester.tap(find.byKey(const Key('command')));
              expect(sources, [
                InteractionSource.keyboard,
                InteractionSource.pointer,
              ]);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }
}
