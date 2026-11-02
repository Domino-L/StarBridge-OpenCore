import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

void main() {
  for (final suite in InteractionSuite.values) {
    for (final suffix in [true, false]) {
      testWidgets(
        '$suite scroll clips action semantics and preserves its input owner; suffix=$suffix',
        (t) async {
          final semantics = t.ensureSemantics();
          final scroll = ScrollController(),
              focus = FocusNode(),
              fieldFocus = FocusNode();
          final text = TextEditingController(text: 'Ship');
          final activations = <InteractionSource>[];
          try {
            final action = StarBridgeIconAction(
              controlKey: const Key('clear-query'),
              label: 'Clear query',
              icon: const Icon(Icons.clear),
              focusNode: focus,
              onActivate: activations.add,
            );
            await t.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  extensions: [StarBridgeInteractionTheme(suite: suite)],
                ),
                home: Scaffold(
                  body: CustomScrollView(
                    controller: scroll,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(24),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              TextField(
                                controller: text,
                                focusNode: fieldFocus,
                                decoration: InputDecoration(
                                  labelText: 'Search',
                                  suffixIcon: suffix ? action : null,
                                ),
                              ),
                              if (!suffix) action,
                              const SizedBox(height: 300),
                            ],
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: 30,
                        itemBuilder: (_, index) =>
                            SizedBox(height: 80, child: Text('Row $index')),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            final element = t.element(find.byKey(const Key('clear-query')));
            final visible = _actions(t);
            expect(visible, hasLength(1));
            expect(visible.single.rect.isEmpty, isFalse);
            expect(
              visible.single.getSemanticsData().hasAction(
                ui.SemanticsAction.tap,
              ),
              isTrue,
            );
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              visible.single.id,
              ui.SemanticsAction.tap,
            );
            await t.pumpAndSettle();
            expect(activations, [InteractionSource.keyboard]);
            focus.requestFocus();
            await t.pumpAndSettle();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
            await t.pumpAndSettle();
            expect(activations, [
              InteractionSource.keyboard,
              InteractionSource.keyboard,
            ]);
            await t.tap(find.byKey(const Key('clear-query')));
            await t.pumpAndSettle();
            expect(activations.last, InteractionSource.pointer);
            expect(activations, hasLength(3));
            focus.unfocus();
            await t.pumpAndSettle();
            fieldFocus.requestFocus();
            await t.pumpAndSettle();
            scroll.jumpTo(700);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(
              _actions(t),
              isEmpty,
              reason: 'offscreen controls must not remain reachable through a portal',
            );
            scroll.jumpTo(0);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(_actions(t), hasLength(1));
            expect(
              t.element(find.byKey(const Key('clear-query'))),
              same(element),
            );
            expect(text.text, 'Ship');
            expect(activations, hasLength(3));
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pump();
            semantics.dispose();
            scroll.dispose();
            focus.dispose();
            fieldFocus.dispose();
            text.dispose();
          }
        },
      );
    }
  }
}

List<SemanticsNode> _actions(WidgetTester t) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().label == 'Clear query' &&
        !node.getSemanticsData().flagsCollection.isHidden) {
      nodes.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root =
      t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode;
  if (root != null) visit(root);
  return nodes;
}
