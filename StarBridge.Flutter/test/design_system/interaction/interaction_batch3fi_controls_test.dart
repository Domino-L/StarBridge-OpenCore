import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> _frames(WidgetTester t, [int count = 5]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tab(WidgetTester t, FocusNode node) async {
  for (var i = 0; !node.hasPrimaryFocus && i < 60; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason: 'Actual traversal reaches target',
  );
}

Future<void> _chip(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  await _frames(t);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    final node = switch (t.widget(target)) {
      ChoiceChip chip => chip.focusNode!,
      FilterChip chip => chip.focusNode!,
      SuiteChoiceChip chip => chip.focusNode!,
      final widget => throw StateError('Unexpected target $widget'),
    };
    await _tab(t, node);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(_chipSemantics(t, target));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pump();
}

Finder _chipSemantics(WidgetTester t, Finder target) {
  final label = switch (t.widget(target)) {
    ChoiceChip chip => (chip.label as Text).data!,
    FilterChip chip => (chip.label as Text).data!,
    SuiteChoiceChip chip => chip.label,
    final widget => throw StateError('Unexpected chip $widget'),
  };
  return find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$'));
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('3fi $suite $input experience remains an owner command', (
        t,
      ) async {
        size(t, const Size(850, 1000));
        final handle = t.ensureSemantics();
        try {
          final values = <(String, InteractionSource)>[];
          final draft = settings({
            'enableStartupTransition': true,
            'startupTransitionFrameRate': 'Fps120',
            'animationFrameRate': 'Fps120',
          });
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: OverlayWorkspaceSettingsGroup(
                  group: 'startup',
                  fields: const [],
                  settings: draft,
                  onChanged: (_, _) =>
                      fail('Preset must not bypass original owner'),
                  onExperiencePreset: (value) =>
                      values.add((value, currentStarBridgeActivationSource)),
                ),
              ),
              suite,
            ),
          );
          await _frames(t);
          final balanced = find.byKey(const Key('overlay-experience-Balanced'));
          for (var i = 0; i < 3; i++) {
            await _chip(t, balanced, input);
          }
          final source = input == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          expect(values, List.filled(3, ('Balanced', source)));
          expect(draft['animationFrameRate'], 'Fps120');
          final selected = switch (t.widget(
            find.byKey(const Key('overlay-experience-Smooth')),
          )) {
            ChoiceChip chip => chip.selected,
            SuiteChoiceChip chip => chip.selected,
            _ => false,
          };
          expect(selected, isTrue, reason: 'No optimistic preset mutation');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await _frames(t);
        } finally {
          handle.dispose();
        }
      });

      testWidgets(
        '3fi $suite $input event mask keeps unrelated bits and disabled gate',
        (t) async {
          size(t, const Size(850, 1000));
          final handle = t.ensureSemantics();
          try {
            var draft = settings({
              'showEventNotifications': true,
              'eventNotificationTypes': 1024,
            });
            final changes = <(String, Object?, InteractionSource)>[];
            late StateSetter update;
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setter) {
                  update = setter;
                  return scopedApp(
                    SingleChildScrollView(
                      child: OverlayWorkspaceSettingsGroup(
                        group: 'events',
                        fields: overlayWorkspaceFieldSpecs
                            .where((f) => f.field == 'eventNotificationTypes')
                            .toList(),
                        settings: draft,
                        onChanged: (field, value) {
                          changes.add((
                            field,
                            value,
                            currentStarBridgeActivationSource,
                          ));
                          update(() => draft = draft.withValue(field, value));
                        },
                      ),
                    ),
                    suite,
                  );
                },
              ),
            );
            await _frames(t);
            final first = find.byKey(const Key('overlay-event-type-1'));
            await _chip(t, first, input);
            expect(draft['eventNotificationTypes'], 1025);
            await _chip(t, first, input);
            expect(draft['eventNotificationTypes'], 1024);
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(changes, [
              ('eventNotificationTypes', 1025, source),
              ('eventNotificationTypes', 1024, source),
            ]);
            update(
              () => draft = draft.withValue('showEventNotifications', false),
            );
            await _frames(t);
            expect(
              t
                  .getSemantics(_chipSemantics(t, first))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
            await t.tapAt(t.getCenter(first));
            await _frames(t);
            expect(changes, hasLength(2));
            expect(draft['eventNotificationTypes'], 1024);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await _frames(t);
          } finally {
            handle.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fi $suite duration keeps native edit identity and original normalization',
      (t) async {
        size(t, const Size(850, 1100));
        var currentSuite = suite, reduce = false;
        var draft = settings({'showEventNotifications': true});
        final changes = <Map<String, Object?>>[];
        late StateSetter update;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setter) {
              update = setter;
              return scopedApp(
                SingleChildScrollView(
                  child: OverlayWorkspaceSettingsGroup(
                    group: 'events',
                    fields: overlayWorkspaceFieldSpecs
                        .where((f) => f.field == 'eventNotificationDurations')
                        .toList(),
                    settings: draft,
                    onChanged: (field, value) {
                      changes.add(Map<String, Object?>.from(value! as Map));
                      update(() => draft = draft.withValue(field, value));
                    },
                  ),
                ),
                currentSuite,
                reduce: reduce,
              );
            },
          ),
        );
        await _frames(t);
        final input = find.byKey(
          const Key('overlay-duration-memberPresence-input'),
        );
        expect(
          find.ancestor(of: input, matching: find.byType(StarBridgeFieldFrame)),
          findsOneWidget,
        );
        final original = t.widget<TextField>(input);
        await t.enterText(input, '12.50');
        final editing = original.controller!.value.copyWith(
          selection: const TextSelection(baseOffset: 1, extentOffset: 4),
          composing: const TextRange(start: 0, end: 5),
        );
        t.testTextInput.updateEditingValue(editing);
        await t.pump();
        update(() {
          currentSuite = suite == InteractionSuite.glow
              ? InteractionSuite.scan
              : InteractionSuite.glow;
          reduce = true;
        });
        await t.pump();
        await t.pump();
        final after = t.widget<TextField>(input);
        expect(after.controller, same(original.controller));
        expect(after.focusNode, same(original.focusNode));
        expect(after.controller!.value, editing);
        expect(changes, isEmpty, reason: 'Editing and theme do not submit');
        t.testTextInput.updateEditingValue(
          editing.copyWith(composing: TextRange.empty),
        );
        await t.testTextInput.receiveAction(TextInputAction.done);
        await _frames(t);
        // Native Done invokes both the unchanged onSubmitted and focus-loss
        // commit before the owner's rebuild, as in the original editor.
        expect(changes, hasLength(2));
        expect(
          changes.every((value) => value['memberPresence'] == 12.5),
          isTrue,
        );
        expect(after.controller!.text, '12.5');
        for (final entry in [
          ('nope', 12.5),
          ('0.2', 1.0),
          ('99', 30.0),
          ('', 0.0),
        ]) {
          await t.enterText(input, entry.$1);
          await t.testTextInput.receiveAction(TextInputAction.done);
          await _frames(t);
          expect(
            (draft['eventNotificationDurations']! as Map)['memberPresence'],
            entry.$2,
          );
        }
        expect(
          changes,
          hasLength(8),
          reason: 'Four normalized submits preserve the existing submit/blur callbacks; invalid input adds none',
        );
        expect(
          changes.last.keys,
          containsAll([
            'memberPresence',
            'shipChange',
            'localPlayReminder',
            'squadChange',
            'commanderChange',
          ]),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      },
    );

    testWidgets(
      '3fi $suite numeric fractional slider follows actual value and keyboard limit',
      (t) async {
        size(t, const Size(850, 700));
        var draft = settings({
          'showCrosshair': true,
          'crosshairUseThemeColor': true,
          'crosshairOpacity': 1,
        });
        final values = <Object?>[];
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, update) => scopedApp(
              OverlayWorkspaceSettingsGroup(
                group: 'crosshair',
                fields: overlayWorkspaceFieldSpecs
                    .where((f) => f.field == 'crosshairOpacity')
                    .toList(),
                settings: draft,
                onChanged: (field, value) => update(() {
                  values.add(value);
                  draft = draft.withValue(field, value);
                }),
              ),
              suite,
            ),
          ),
        );
        await _frames(t);
        final slider = find.byKey(const Key('overlay-field-crosshairOpacity'));
        await t.tapAt(t.getCenter(slider));
        await _frames(t);
        expect(
          values.last,
          allOf(isA<double>(), greaterThan(0.2), lessThan(0.8)),
        );
        final focus = switch (t.widget(slider)) {
          Slider value => value.focusNode!,
          SuiteSlider value => value.focusNode!,
          _ => throw StateError('Not an actual slider'),
        };
        await _tab(t, focus);
        await t.sendKeyEvent(LogicalKeyboardKey.home);
        await t.pump();
        await t.pump();
        expect(
          draft['crosshairOpacity'],
          overlayWorkspaceFieldSpecs
              .singleWhere((f) => f.field == 'crosshairOpacity')
              .minimum,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.end);
        await t.pump();
        await t.pump();
        expect(draft['crosshairOpacity'], 1.0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      },
    );
  }
}
