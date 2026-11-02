import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Future<void> _frames(WidgetTester t, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tab(
  WidgetTester t,
  FocusNode expected, {
  bool reverse = false,
}) async {
  if (reverse) {
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  try {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
  } finally {
    if (reverse) {
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  }
  await _frames(t, count: 2);
  expect(
    FocusManager.instance.primaryFocus,
    same(expected),
    reason: 'Actual Tab traversal must reach ${expected.debugLabel}',
  );
  expect(expected.hasPrimaryFocus, isTrue);
}

Future<void> _enter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await _frames(t);
}

Widget _host(InteractionSuite suite, Widget child) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  for (final suite in InteractionSuite.values) {
    for (final keep in [false, true]) {
      testWidgets(
        '$suite nonmodal expander Tab crosses both edges and keyboard collapse skips body maintainState=$keep',
        (t) async {
          final before = FocusNode(debugLabel: 'before');
          final header = FocusNode(debugLabel: 'header');
          final field = FocusNode(debugLabel: 'draft-field');
          final first = FocusNode(debugLabel: 'body-first');
          final last = FocusNode(debugLabel: 'body-last');
          final after = FocusNode(debugLabel: 'after');
          final text = TextEditingController();
          var expanded = true, toggles = 0, bodyActions = 0;
          try {
            await t.pumpWidget(
              _host(
                suite,
                SizedBox(
                  width: 430,
                  child: StatefulBuilder(
                    builder: (context, setState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          focusNode: before,
                          autofocus: true,
                          onPressed: () => bodyActions++,
                          child: const Text('Before'),
                        ),
                        SuiteExpander(
                          title: 'Group',
                          expanded: expanded,
                          focusNode: header,
                          maintainState: keep,
                          onChanged: (value) => setState(() {
                            expanded = value;
                            toggles++;
                          }),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                key: const Key('controlled-draft'),
                                controller: text,
                                focusNode: field,
                                showCursor: false,
                              ),
                              TextButton(
                                focusNode: first,
                                onPressed: () => bodyActions++,
                                child: const Text('First body action'),
                              ),
                              TextButton(
                                focusNode: last,
                                onPressed: () => bodyActions++,
                                child: const Text('Last body action'),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          focusNode: after,
                          onPressed: () => bodyActions++,
                          child: const Text('After'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await _frames(t);
            expect(FocusManager.instance.primaryFocus, same(before));

            // The old closed-loop body fails here: last -> field, never after.
            for (final expected in [header, field, first, last, after]) {
              await _tab(t, expected);
            }
            for (final expected in [last, first, field, header, before]) {
              await _tab(t, expected, reverse: true);
            }
            expect(bodyActions, 0);
            expect(toggles, 0);

            await _tab(t, header);
            await _enter(t);
            expect(expanded, isFalse);
            expect(toggles, 1);
            expect(FocusManager.instance.primaryFocus, same(header));
            await _tab(t, after);
            await _tab(t, header, reverse: true);
            expect(field.hasFocus, isFalse);
            expect(first.hasFocus, isFalse);
            expect(last.hasFocus, isFalse);

            await _enter(t);
            expect(expanded, isTrue);
            expect(toggles, 2);
            await _tab(t, field);
            await t.enterText(
              find.byKey(const Key('controlled-draft')),
              'retained draft',
            );
            await _frames(t, count: 2);
            expect(text.text, 'retained draft');

            // Close with actual header Enter, not a direct onChanged call.
            await _tab(t, header, reverse: true);
            await _enter(t);
            expect(expanded, isFalse);
            expect(toggles, 3);
            expect(
              text.text,
              'retained draft',
              reason: 'The caller-owned draft survives either maintainState policy.',
            );
            await _tab(t, after);
            await _tab(t, header, reverse: true);
            await _enter(t);
            expect(expanded, isTrue);
            expect(toggles, 4);
            await _tab(t, field);
            final reopened = t.widget<TextField>(
              find.byKey(const Key('controlled-draft')),
            );
            expect(reopened.controller, same(text));
            expect(reopened.controller!.text, 'retained draft');
            expect(bodyActions, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await _frames(t);
            for (final node in [before, header, field, first, last, after]) {
              node.dispose();
            }
            text.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      testWidgets(
        '$suite expander parent-scope traversal keeps the modal outer loop closed maintainState=$keep',
        (t) async {
          final outside = FocusNode(debugLabel: 'outside-open');
          final before = FocusNode(debugLabel: 'modal-before');
          final header = FocusNode(debugLabel: 'modal-header');
          final first = FocusNode(debugLabel: 'modal-body-first');
          final last = FocusNode(debugLabel: 'modal-body-last');
          final after = FocusNode(debugLabel: 'modal-after-close');
          var opens = 0, bodyActions = 0, toggles = 0;
          var expanded = true;
          try {
            await t.pumpWidget(
              _host(
                suite,
                Builder(
                  builder: (context) => TextButton(
                    focusNode: outside,
                    autofocus: true,
                    onPressed: () {
                      opens++;
                      unawaited(
                        showSuiteDialog<void>(
                          context,
                          (dialogContext) => Dialog(
                            child: SizedBox(
                              width: 400,
                              height: 360,
                              child: StatefulBuilder(
                                builder: (context, setState) => Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      focusNode: before,
                                      autofocus: true,
                                      onPressed: () => bodyActions++,
                                      child: const Text('Modal before'),
                                    ),
                                    SuiteExpander(
                                      title: 'Modal group',
                                      expanded: expanded,
                                      focusNode: header,
                                      maintainState: keep,
                                      onChanged: (value) => setState(() {
                                        expanded = value;
                                        toggles++;
                                      }),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            focusNode: first,
                                            onPressed: () => bodyActions++,
                                            child: const Text('Modal first'),
                                          ),
                                          TextButton(
                                            focusNode: last,
                                            onPressed: () => bodyActions++,
                                            child: const Text('Modal last'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      focusNode: after,
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      child: const Text(
                                        'Modal after and close',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          source: InteractionSource.keyboard,
                        ),
                      );
                    },
                    child: const Text('Open modal'),
                  ),
                ),
              ),
            );
            await _frames(t);
            expect(FocusManager.instance.primaryFocus, same(outside));
            await _enter(t);
            expect(opens, 1);
            expect(find.byType(Dialog), findsOneWidget);
            expect(FocusManager.instance.primaryFocus, same(before));

            // Escaping the body must go to another control INSIDE the route.
            for (final expected in [header, first, last, after, before]) {
              await _tab(t, expected);
              expect(outside.hasFocus, isFalse);
            }
            for (final expected in [after, last, first, header, before]) {
              await _tab(t, expected, reverse: true);
              expect(outside.hasFocus, isFalse);
            }

            await _tab(t, header);
            await _enter(t);
            expect(expanded, isFalse);
            expect(toggles, 1);
            await _tab(t, after);
            await _tab(t, before);
            await _tab(t, after, reverse: true);
            await _tab(t, header, reverse: true);
            expect(outside.hasFocus, isFalse);
            expect(first.hasFocus, isFalse);
            expect(last.hasFocus, isFalse);
            expect(bodyActions, 0);
            expect(opens, 1);

            // Even after the inner body is skipped, only a real close action may
            // return focus to the outside opener.
            await _tab(t, after);
            await _enter(t);
            expect(find.byType(Dialog), findsNothing);
            expect(FocusManager.instance.primaryFocus, same(outside));
            expect(bodyActions, 0);
            expect(opens, 1);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await _frames(t);
            for (final node in [outside, before, header, first, last, after]) {
              node.dispose();
            }
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
