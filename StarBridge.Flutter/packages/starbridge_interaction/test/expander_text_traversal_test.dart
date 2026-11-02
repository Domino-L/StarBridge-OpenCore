import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Future<void> _tab(
  WidgetTester t,
  FocusNode expected, {
  bool reverse = false,
}) async {
  if (reverse) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump();
  await t.pump();
  expect(
    FocusManager.instance.primaryFocus,
    same(expected),
    reason: 'Text-only body must not become a keyboard stop',
  );
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final keep in [false, true]) {
      testWidgets(
        '$suite Tab skips text-only disclosure body maintainState=$keep',
        (t) async {
          final before = FocusNode(debugLabel: 'before-text-section');
          final header = FocusNode(debugLabel: 'text-section-header');
          final after = FocusNode(debugLabel: 'after-text-section');
          addTearDown(before.dispose);
          addTearDown(header.dispose);
          addTearDown(after.dispose);
          var expanded = true;
          await t.pumpWidget(
            InteractionScope(
              data: InteractionData(suite: suite, palette: palette),
              child: MaterialApp(
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (_, setState) => Column(
                      children: [
                        TextButton(
                          autofocus: true,
                          focusNode: before,
                          onPressed: () {},
                          child: const Text('Before'),
                        ),
                        SuiteExpander(
                          title: 'Text-only section',
                          expanded: expanded,
                          focusNode: header,
                          maintainState: keep,
                          onChanged: (value) =>
                              setState(() => expanded = value),
                          child: const Text(
                            'Read-only facts, no interactive controls',
                          ),
                        ),
                        TextButton(
                          focusNode: after,
                          onPressed: () {},
                          child: const Text('After'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(before.hasPrimaryFocus, isTrue);
          await _tab(t, header);
          await _tab(t, after);
          await _tab(t, header, reverse: true);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          await t.pump();
          expect(expanded, isFalse);
          await _tab(t, after);
          await _tab(t, header, reverse: true);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          await t.pump();
          expect(expanded, isTrue);
          await _tab(t, after);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
