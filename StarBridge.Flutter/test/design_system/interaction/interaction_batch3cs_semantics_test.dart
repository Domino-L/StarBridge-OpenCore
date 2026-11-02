import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show exposedNodes;

SemanticsNode targetNode(WidgetTester t) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    if (node.getSemanticsData().flagsCollection.isButton) nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.getSemantics(find.byKey(const Key('focus-target'))));
  expect(nodes, hasLength(1));
  return nodes.single;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite exposed-node helper keeps two real same-name buttons', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      final calls = <(String, InteractionSource)>[];
      Widget button(String id) => StarBridgeActionButton(
        semanticLabel: 'Same action',
        onActivate: (source) => calls.add((id, source)),
        child: const Text('Same action'),
      );
      try {
        await t.pumpWidget(
          scopedApp(Row(children: [button('first'), button('second')]), suite),
        );
        await t.pumpAndSettle();
        final buttons = exposedNodes(t).where((node) {
          final data = node.getSemanticsData();
          return data.flagsCollection.isButton && data.label == 'Same action';
        }).toList();
        expect(buttons, hasLength(2));
        for (final node in buttons) {
          expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          t.binding.performSemanticsAction(
            ui.SemanticsActionEvent(
              type: ui.SemanticsAction.tap,
              viewId: t.view.viewId,
              nodeId: node.id,
            ),
          );
        }
        await t.pump();
        expect(
          calls,
          unorderedEquals([
            ('first', InteractionSource.keyboard),
            ('second', InteractionSource.keyboard),
          ]),
        );
      } finally {
        semantics.dispose();
      }
    });
    for (final kind in ['text', 'implicit-text', 'icon', 'native-icon']) {
      testWidgets(
        '$suite $kind owns its label and follows focus replacement/disable',
        (t) async {
          final semantics = t.ensureSemantics();
          final first = FocusNode(), second = FocusNode();
          var focus = first, enabled = true;
          late StateSetter update;
          final inputs = <InteractionSource>[];
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, state) {
                  update = state;
                  final callback = enabled ? inputs.add : null;
                  final control = switch (kind) {
                    'text' || 'implicit-text' => StarBridgeActionButton(
                      controlKey: const Key('focus-target'),
                      focusNode: focus,
                      semanticLabel: kind == 'text' ? 'Target action' : null,
                      onActivate: callback,
                      child: const Text('Target action'),
                    ),
                    'icon' => StarBridgeIconAction(
                      controlKey: const Key('focus-target'),
                      focusNode: focus,
                      label: 'Target action',
                      onActivate: callback,
                      icon: const Icon(Icons.close),
                    ),
                    _ => StarBridgeNativeIconAction(
                      controlKey: const Key('focus-target'),
                      focusNode: focus,
                      label: 'Target action',
                      onActivate: callback,
                      icon: const Icon(Icons.close),
                    ),
                  };
                  return scopedApp(
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [const Text('Unrelated heading'), control],
                      ),
                    ),
                    suite,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            expect(targetNode(t).getSemanticsData().label, 'Target action');
            first.requestFocus();
            await t.pump();
            await t.pump();
            expect(first.hasFocus, isTrue);
            expect(
              targetNode(t).getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.isTrue,
            );
            update(() => focus = second);
            await t.pump();
            await t.pump();
            expect(
              targetNode(t).getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.isFalse,
            );
            first.requestFocus();
            await t.pump();
            expect(
              targetNode(t).getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.isFalse,
            );
            second.requestFocus();
            await t.pump();
            await t.pump();
            final active = targetNode(t);
            expect(
              active.getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.isTrue,
            );
            t.binding.performSemanticsAction(
              ui.SemanticsActionEvent(
                type: ui.SemanticsAction.tap,
                viewId: t.view.viewId,
                nodeId: active.id,
              ),
            );
            await t.pump();
            expect(inputs, [InteractionSource.keyboard]);
            update(() => enabled = false);
            await t.pump();
            await t.pump();
            final disabled = targetNode(t).getSemanticsData();
            expect(disabled.label, 'Target action');
            expect(disabled.hasAction(ui.SemanticsAction.tap), isFalse);
            expect(disabled.flagsCollection.isFocused, ui.Tristate.none);
            expect(inputs, hasLength(1));
            await t.pumpWidget(const SizedBox());
            await t.pump();
            first.requestFocus();
            second.requestFocus();
            await t.pump();
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
            first.dispose();
            second.dispose();
          }
        },
      );
    }
  }
}
