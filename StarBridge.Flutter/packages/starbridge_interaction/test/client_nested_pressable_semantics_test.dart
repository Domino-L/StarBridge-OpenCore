import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show host;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final label in <String?>[null, '']) {
      testWidgets('$suite retains plain child aggregation for label=$label', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        await t.pumpWidget(
          host(
            suite,
            SuitePressable(
              kind: PressableKind.row,
              key: const Key('plain'),
              semanticLabel: label,
              onActivate: (_) {},
              child: const Text('Visible'),
            ),
          ),
        );
        await t.pumpAndSettle();
        final data = t
            .getSemantics(find.byKey(const Key('plain')))
            .getSemanticsData();
        expect(data.label, 'Visible');
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(find.bySemanticsLabel('Visible'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        semantics.dispose();
      });
    }
    testWidgets('$suite explicit child exclusion keeps only parent command', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      var rows = 0, avatars = 0;
      await t.pumpWidget(
        host(
          suite,
          SuitePressable(
            kind: PressableKind.row,
            key: const Key('excluded'),
            semanticLabel: 'Row',
            excludeChildSemantics: true,
            onActivate: (_) => rows++,
            child: SuitePressable(
              kind: PressableKind.icon,
              semanticLabel: 'Avatar',
              onActivate: (_) => avatars++,
              child: const Text('A'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final node = t.getSemantics(find.byKey(const Key('excluded')));
      expect(node.getSemanticsData().label, 'Row');
      expect(find.bySemanticsLabel('Avatar'), findsNothing);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await t.pump();
      expect(rows, 1);
      expect(avatars, 0);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
    for (final raw in [false, true]) {
      testWidgets(
        '$suite independently activate parent and ${raw ? 'legacy' : 'suite'} avatar',
        (t) async {
          final semantics = t.ensureSemantics();
          var rows = 0, avatars = 0;
          final inner = raw
              ? Semantics(
                  button: true,
                  label: 'Avatar',
                  onTap: () => avatars++,
                  child: FocusableActionDetector(
                    child: GestureDetector(
                      onTap: () => avatars++,
                      child: const ExcludeSemantics(child: Text('A')),
                    ),
                  ),
                )
              : SuitePressable(
                  kind: PressableKind.icon,
                  semanticLabel: 'Avatar',
                  excludeChildSemantics: true,
                  onActivate: (_) => avatars++,
                  child: const Text('A'),
                );
          await t.pumpWidget(
            host(
              suite,
              SizedBox(
                width: 320,
                child: SuitePressable(
                  kind: PressableKind.row,
                  semanticLabel: 'Row',
                  onActivate: (_) => rows++,
                  child: Row(
                    children: [
                      inner,
                      const ExcludeSemantics(child: Text('Conversation')),
                    ],
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          List<SemanticsNode> targets(String label) {
            final result = <SemanticsNode>[];
            void visit(SemanticsNode node) {
              final data = node.getSemanticsData();
              if (data.label == label && data.hasAction(SemanticsAction.tap)) {
                result.add(node);
              }
              node.visitChildren((child) {
                visit(child);
                return true;
              });
            }

            visit(
              t
                  .binding
                  .renderViews
                  .single
                  .owner!
                  .semanticsOwner!
                  .rootSemanticsNode!,
            );
            return result;
          }

          expect(targets('Avatar'), hasLength(1));
          expect(targets('Row'), hasLength(1));
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            targets('Avatar').single.id,
            SemanticsAction.tap,
          );
          await t.pump();
          expect(avatars, 1);
          expect(rows, 0);
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            targets('Row').single.id,
            SemanticsAction.tap,
          );
          await t.pump();
          expect(avatars, 1);
          expect(rows, 1);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
  }
}
