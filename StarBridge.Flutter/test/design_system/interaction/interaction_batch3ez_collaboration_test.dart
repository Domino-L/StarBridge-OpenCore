import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_playstyle_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_schedule_editor.dart';
import 'package:starbridge_flutter/shared/clock_field.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3i_test.dart' show scopedApp;

const _schedule = PersonalProfileSchedule(
  timeZoneId: 'America/Regina',
  rhythm: PersonalProfileActivityRhythm.weekends,
  windows: [
    PersonalProfileAvailabilityWindow(
      days: [1, 3],
      startTime: '23:30',
      endTime: '02:15',
    ),
  ],
);

Finder _key(String id) => find.byKey(Key(id));
Finder _header(String id) =>
    find.descendant(of: _key(id), matching: find.byType(SuitePressable)).first;
Finder _chip(String id) =>
    find.ancestor(of: _key(id), matching: find.byType(StarBridgeChoiceChip));
SuiteExpander _expander(WidgetTester t, String id) {
  final target = _key(id);
  final nested = find.descendant(
    of: target,
    matching: find.byType(SuiteExpander),
  );
  return t.widget<SuiteExpander>(
    t.widget(target) is SuiteExpander ? target : nested,
  );
}

Future<void> _use(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  if (source == 'reader') {
    // The adapter itself is not a render/semantics boundary. Its suite chip
    // paints outside the inner pressable, while standard mode merges a native
    // FilterChip. Address the actual labelled accessibility node, not whichever
    // ancestor node getSemantics resolves for the adapter's outer render object.
    final widget = t.widget(target);
    final label = switch (widget) {
      StarBridgeChoiceChip(:final label) => label,
      SuitePressable(:final semanticLabel) => semanticLabel,
      _ => null,
    };
    if (label != null) {
      final accessible = find.bySemanticsLabel(
        RegExp('^${RegExp.escape(label)}\$'),
      );
      expect(accessible, findsOneWidget);
      await activate(t, accessible, source);
      return;
    }
  }
  await activate(t, target, source);
}

class _Probe {
  late InteractionSuite suite;
  late StateSetter update;
  bool enabled = true, reduce = false, light = false;
  final form = GlobalKey<FormState>();
  final play = GlobalKey<PersonalProfilePlayStyleEditorState>();
  final schedules = <PersonalProfileSchedule>[];
  final styles = <PersonalProfilePlayStyle>[];
  final sources = <InteractionSource>[];
  Widget app({bool schedule = true}) => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: schedule
                  ? PersonalProfileScheduleEditor(
                      initial: _schedule,
                      timeZones: const {
                        'America/Regina': 'Regina',
                        'UTC': 'UTC',
                      },
                      enabled: enabled,
                      onChanged: (value) {
                        schedules.add(value);
                        sources.add(currentStarBridgeActivationSource);
                      },
                    )
                  : Column(
                      children: [
                        StarBridgeActionButton(
                          controlKey: const Key('open-all-playstyle'),
                          onActivate: (_) => play.currentState!.openAll(),
                          child: const Text('Open all'),
                        ),
                        PersonalProfilePlayStyleEditor(
                          key: play,
                          projection: const PersonalProfileProjection.loading(),
                          enabled: enabled,
                          onChanged: (value) {
                            styles.add(value);
                            sources.add(currentStarBridgeActivationSource);
                          },
                        ),
                      ],
                    ),
            ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<_Probe> _mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool schedule = true,
}) async {
  size(t, const Size(1000, 1300));
  final p = _Probe()..suite = suite;
  await t.pumpWidget(p.app(schedule: schedule));
  await t.pumpAndSettle();
  return p;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite schedule $source keeps days, exact times and three-window limit',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await _mount(t, suite);
            await _use(t, _header('profile-schedule-editor'), source);
            await t.pumpAndSettle();
            expect(_expander(t, 'profile-schedule-editor').expanded, isTrue);
            expect(p.schedules, isEmpty);
            // Times are the shared hour and minute lists, never text boxes.
            expect(find.byType(StarBridgeTimeRangeField), findsOneWidget);
            expect(find.byType(TextFormField), findsNothing);
            await _use(t, _chip('profile-window-0-day-0'), source);
            await t.pumpAndSettle();
            expect(p.schedules.single.windows.single.days, [1, 3, 0]);
            expect(p.schedules.single.windows.single.startTime, '23:30');
            expect(p.schedules.single.windows.single.endTime, '02:15');
            expect(p.schedules.single.timeZoneId, 'America/Regina');
            expect(
              p.schedules.single.rhythm,
              PersonalProfileActivityRhythm.weekends,
            );
            expect(
              p.sources.single,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await _use(t, _key('profile-add-window'), source);
            await _use(t, _key('profile-add-window'), source);
            await t.pumpAndSettle();
            expect(p.schedules.last.windows, hasLength(3));
            expect(p.schedules.last.windows[1].days, [1, 2, 3, 4, 5]);
            expect(p.schedules.last.windows[1].startTime, '19:00');
            final add = find.ancestor(
              of: _key('profile-add-window'),
              matching: find.byType(StarBridgeActionButton),
            );
            expect(t.widget<StarBridgeActionButton>(add).onActivate, isNull);
            await _use(t, _key('profile-remove-window-0'), source);
            await t.pumpAndSettle();
            expect(p.schedules.last.windows, hasLength(2));
            expect(p.schedules.last.windows.first.startTime, '19:00');
            expect(p.schedules.last.windows.first.endTime, '22:00');
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite playstyle $source keeps partial groups, limit and removable choice',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await _mount(t, suite, schedule: false);
            await _use(t, _header('profile-interests-editor'), source);
            await t.pumpAndSettle();
            expect(_expander(t, 'profile-interests-editor').expanded, isTrue);
            expect(p.styles, isEmpty);
            for (final id in ['pve', 'pvp', 'mining']) {
              await _use(t, _chip('profile-interests-$id'), source);
              await t.pumpAndSettle();
            }
            expect(p.styles.last.interests, ['pve', 'pvp', 'mining']);
            expect(p.styles.last.roles, isNull);
            expect(p.styles.last.support, isNull);
            expect(p.styles, hasLength(3));
            expect(
              t
                  .widget<StarBridgeChoiceChip>(
                    _chip('profile-interests-racing'),
                  )
                  .onSelected,
              isNull,
            );
            expect(
              t
                  .widget<StarBridgeChoiceChip>(_chip('profile-interests-pve'))
                  .onSelected,
              isNotNull,
            );
            await _use(t, _chip('profile-interests-pve'), source);
            await _use(t, _chip('profile-interests-racing'), source);
            await t.pumpAndSettle();
            expect(p.styles.last.interests, ['pvp', 'mining', 'racing']);
            expect(p.styles, hasLength(5));
            expect(
              p.sources,
              everyElement(
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            );
            await _use(t, _header('profile-interests-editor'), source);
            await t.pumpAndSettle();
            expect(_expander(t, 'profile-interests-editor').expanded, isFalse);
            await _use(t, _header('profile-interests-editor'), source);
            await t.pumpAndSettle();
            expect(
              t
                  .widget<StarBridgeChoiceChip>(
                    _chip('profile-interests-racing'),
                  )
                  .selected,
              isTrue,
            );
            expect(p.styles, hasLength(5));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite collapsed invalid schedule retains field state and live settings',
      (t) async {
        final p = await _mount(t, suite);
        await _use(t, _header('profile-schedule-editor'), 'pointer');
        await t.pumpAndSettle();
        // Times are picked, so the invalid window comes from its days.
        final start = find.byKey(const ValueKey('profile-window-0-start-hour'));
        for (final day in [1, 3]) {
          await _use(t, _chip('profile-window-0-day-$day'), 'pointer');
        }
        await t.pump();
        expect(p.schedules.last.windows.single.days, isEmpty);
        final fieldState = t.state(start);
        await _use(t, _header('profile-schedule-editor'), 'pointer');
        await t.pumpAndSettle();
        expect(p.form.currentState!.validate(), isFalse);
        await t.pump();
        p.update(() {
          p.reduce = true;
          p.light = true;
          p.enabled = false;
        });
        await t.pump();
        await _use(t, _header('profile-schedule-editor'), 'keyboard');
        await t.pump();
        expect(t.state(start), same(fieldState));
        expect(
          t.widget<StarBridgeSelectFormField<int>>(start).onChanged,
          isNull,
        );
        expect(
          t
              .widget<StarBridgeChoiceChip>(_chip('profile-window-0-day-1'))
              .onSelected,
          isNull,
        );
        expect(p.schedules, hasLength(2), reason: 'the two day changes only');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard openAll is pure presentation and disabled headers remain operable',
      (t) async {
        final p = await _mount(t, suite, schedule: false);
        await _use(t, _key('open-all-playstyle'), 'keyboard');
        for (final group in ['roles', 'interests', 'support']) {
          expect(_expander(t, 'profile-$group-editor').expanded, isTrue);
        }
        expect(p.styles, isEmpty);
        await t.pumpAndSettle();
        p.update(() => p.enabled = false);
        await t.pumpAndSettle();
        expect(
          t
              .widget<StarBridgeChoiceChip>(_chip('profile-interests-pve'))
              .onSelected,
          isNull,
        );
        await _use(t, _header('profile-roles-editor'), 'keyboard');
        await t.pumpAndSettle();
        expect(_expander(t, 'profile-roles-editor').expanded, isFalse);
        expect(p.styles, isEmpty);
        expect(p.form.currentState!.validate(), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
}
