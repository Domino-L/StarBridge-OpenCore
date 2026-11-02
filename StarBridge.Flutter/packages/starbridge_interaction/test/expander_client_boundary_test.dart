import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final keep in [false, true]) {
      testWidgets('$suite immediate close exclusion and maintainState=$keep', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final focus = FocusNode(), header = FocusNode();
        final text = TextEditingController(text: 'draft');
        var expanded = true, clicks = 0;
        late StateSetter update;
        await t.pumpWidget(
          InteractionScope(
            data: InteractionData(suite: suite, palette: palette),
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: StatefulBuilder(
                    builder: (_, setState) {
                      update = setState;
                      return SuiteExpander(
                        title: 'Details',
                        subtitle: 'Unsaved draft',
                        expanded: expanded,
                        focusNode: header,
                        maintainState: keep,
                        onChanged: (value) => update(() => expanded = value),
                        child: Column(
                          children: [
                            TextField(controller: text, focusNode: focus),
                            TextButton(
                              onPressed: () => clicks++,
                              child: const Text('Body action'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byType(TextField));
        await t.pump();
        expect(focus.hasFocus, isTrue);
        await t.tap(find.text('Details'));
        await t.pump();
        expect(focus.hasFocus, isFalse);
        expect(header.hasFocus, isTrue);
        expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
        final labels = <String>[];
        void visit(SemanticsNode node) {
          labels.add(node.getSemanticsData().label);
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
        expect(labels, isNot(contains('Body action')));
        await t.tap(find.text('Body action'), warnIfMissed: false);
        expect(clicks, 0);
        await t.pumpAndSettle();
        expect(
          find.byType(TextField, skipOffstage: false),
          keep ? findsOneWidget : findsNothing,
        );
        update(() => expanded = true);
        await t.pumpAndSettle();
        expect(text.text, 'draft');
        final node = t.getSemantics(find.bySemanticsLabel('Details').last);
        expect(node.getSemanticsData().value, 'Unsaved draft');
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        focus.dispose();
        header.dispose();
        text.dispose();
        semantics.dispose();
      });
    }
  }
}
