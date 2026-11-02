import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _fieldKey = Key('client-expander-time');
Finder _field() => find.byKey(_fieldKey, skipOffstage: false);
Finder _editable() => find.descendant(
  of: _field(),
  matching: find.byType(EditableText, skipOffstage: false),
  skipOffstage: false,
);

Future<void> _openOrClose(WidgetTester t) async {
  await t.tap(find.text('Details'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _mount(
  WidgetTester t,
  InteractionSuite suite,
  GlobalKey<FormState> form, {
  required bool keep,
  required bool initiallyExpanded,
}) async {
  var expanded = initiallyExpanded;
  await t.pumpWidget(
    InteractionScope(
      data: InteractionData(suite: suite, palette: palette),
      child: MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (_, setState) => SuiteExpander(
                  title: 'Details',
                  expanded: expanded,
                  maintainState: keep,
                  onChanged: (value) => setState(() => expanded = value),
                  child: TextFormField(
                    key: _fieldKey,
                    initialValue: '19:00',
                    showCursor: false,
                    decoration: const InputDecoration(labelText: 'Time'),
                    validator: (value) =>
                        value == '24:00' ? 'Invalid time' : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite client native field identity, validation and selection survive kept entry/exit',
      (t) async {
        final form = GlobalKey<FormState>();
        await _mount(t, suite, form, keep: true, initiallyExpanded: false);
        final originalField = t.state(_field());
        final originalEditable = t.state(_editable());
        await _openOrClose(t);
        expect(
          t.state(_field()),
          same(originalField),
          reason: 'Entrance must not remount a maintained field',
        );
        expect(t.state(_editable()), same(originalEditable));
        await t.pumpAndSettle();
        expect(t.state(_field()), same(originalField));
        await t.enterText(_field(), '24:00');
        final controller = t.widget<EditableText>(_editable()).controller;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        expect(form.currentState!.validate(), isFalse);
        await t.pump();
        await _openOrClose(t);
        expect(
          t.state(_field()),
          same(originalField),
          reason: 'Exit must not recreate a maintained field',
        );
        expect(t.state(_editable()), same(originalEditable));
        expect(
          t.widget<EditableText>(_editable()).controller,
          same(controller),
        );
        expect(controller.text, '24:00');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        await t.pumpAndSettle();
        expect(t.state(_field()), same(originalField));
        expect(
          form.currentState!.validate(),
          isFalse,
          reason: 'Collapsed retained invalid fields still participate in the real Form',
        );
        await t.pump();
        await _openOrClose(t);
        await t.pumpAndSettle();
        expect(t.state(_field()), same(originalField));
        expect(t.state(_editable()), same(originalEditable));
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(find.text('Invalid time'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite client non-kept field survives exit then disposes and remounts only after closing',
      (t) async {
        final form = GlobalKey<FormState>();
        await _mount(t, suite, form, keep: false, initiallyExpanded: true);
        final originalField = t.state(_field());
        await t.enterText(_field(), '24:00');
        expect(form.currentState!.validate(), isFalse);
        await t.pump();
        await _openOrClose(t);
        expect(
          t.state(_field()),
          same(originalField),
          reason: 'Non-kept content still has one identity throughout its exit',
        );
        expect(originalField.mounted, isTrue);
        await t.pumpAndSettle();
        expect(_field(), findsNothing);
        expect(originalField.mounted, isFalse);
        expect(form.currentState!.validate(), isTrue);
        await _openOrClose(t);
        final reopened = t.state(_field());
        expect(reopened, isNot(same(originalField)));
        await t.pumpAndSettle();
        expect(
          t.state(_field()),
          same(reopened),
          reason: 'Fresh entrance must not remount again at its final frame',
        );
        expect(t.widget<EditableText>(_editable()).controller.text, '19:00');
        expect(form.currentState!.validate(), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
}
