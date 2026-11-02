import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scope_sections.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/design_system/icons/native_dropdown_indicator_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';

import 'dart:async';

import '../../features/settings/community_sharing_test.dart'
    show SharingFixture, target;
import 'interaction_batch3i_test.dart' show scopedApp;
import '../../features/settings/event_sharing_controller_test.dart' as events;
import 'interaction_batch3o_test.dart' as presets;

Widget scopeApp(
  LocalPrivacyController c,
  InteractionSuite suite,
  String kind, {
  bool reduce = false,
  bool light = false,
}) => scopedApp(
  ListenableBuilder(
    listenable: c,
    builder: (_, _) => SingleChildScrollView(
      child: kind == 'room'
          ? LocalPrivacyRoomSection(controller: c)
          : LocalPrivacyOrganizationsSection(controller: c),
    ),
  ),
  suite,
  reduce: reduce,
  light: light,
);

Future<void> toggle(
  WidgetTester t,
  String id,
  String source, {
  bool checkbox = false,
  bool settle = true,
}) async {
  final row = find.byKey(Key(id));
  await t.ensureVisible(row);
  await t.pump();
  if (source == 'pointer') {
    await t.tapAt(t.getCenter(row));
  } else if (source == 'reader') {
    final node = t.getSemantics(row);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else if (checkbox) {
    final native = find.descendant(of: row, matching: find.byType(Checkbox));
    final suite = find.descendant(
      of: row,
      matching: find.byType(SuiteCheckbox),
    );
    final focus = native.evaluate().isNotEmpty
        ? t.widget<Checkbox>(native).focusNode!
        : t.widget<SuiteCheckbox>(suite).focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final target = find.descendant(
      of: row,
      matching: find.byType(SuitePressable),
    );
    expect(target, findsOneWidget);
    final focus = t.widget<SuitePressable>(target).focusNode!;
    expect(focus.canRequestFocus, isTrue);
    focus.requestFocus();
    await t.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  }
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
    await t.pump();
  }
}

Future<void> clean(
  WidgetTester t,
  LocalPrivacyController c,
  SharingFixture p,
) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  c.dispose();
  await t.runAsync(p.close);
}

void main() {
  for (final suite in InteractionSuite.values) {
    adjacent(suite);
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source room field and audience keep draft-only ownership',
        (t) async {
          final p = SharingFixture(),
              c = LocalPrivacyController(p),
              semantics = t.ensureSemantics();
          try {
            await c.refresh();
            await t.pumpWidget(scopeApp(c, suite, 'room'));
            await t.pumpAndSettle();
            expect(find.byType(StarBridgeSwitch), findsNWidgets(4));
            expect(find.byType(StarBridgeCheckboxTile), findsOneWidget);
            final fields = c.draft!.roomFields,
                audience = c.draft!.roomAllMembersCanView;
            await toggle(t, 'privacy-scope-room-field-presence', source);
            expect(c.draft!.roomFields, fields ^ 1);
            await toggle(
              t,
              'privacy-scope-room-audience-members',
              source,
              checkbox: true,
            );
            expect(c.draft!.roomAllMembersCanView, !audience);
            expect(c.draft!.roomFields, fields ^ 1);
            expect(p.writes, 0);
            expect(p.applies, 0);
          } finally {
            await clean(t, c, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source organization field and all-members preserve mutual exclusion',
        (t) async {
          final p = SharingFixture(),
              c = LocalPrivacyController(p),
              semantics = t.ensureSemantics();
          try {
            await c.refresh();
            c.enableCommunityChoices();
            c.editCommunity(
              target('A')
                  .choice(fields: 3)
                  .copyWith(
                    allMembersCanView: false,
                    administratorsCanView: true,
                  ),
            );
            await t.pumpWidget(scopeApp(c, suite, 'organization'));
            await t.pumpAndSettle();
            expect(find.byType(StarBridgeSwitch), findsNWidgets(8));
            await toggle(t, 'privacy-scope-A-field-presence', source);
            expect(c.draft!.communities!.single.fields, 2);
            await toggle(
              t,
              'privacy-scope-A-audience-members',
              source,
              checkbox: true,
            );
            final value = c.draft!.communities!.single;
            expect(value.allMembersCanView, isTrue);
            expect(value.administratorsCanView, isFalse);
            expect(value.fields, 2);
            final admins = t.widget<StarBridgeCheckboxTile>(
              find.byKey(const Key('privacy-scope-A-audience-administrators')),
            );
            expect(admins.onChanged, isNull);
            expect(p.writes, 0);
            expect(p.applies, 0);
          } finally {
            await clean(t, c, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source event enable preserves selected mask while off',
        (t) async {
          var choice = const EventSharingChoice(
            enabled: false,
            selectedTypes: 36,
          );
          var changes = 0;
          final origins = <InteractionSource>[];
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              scopedApp(
                StatefulBuilder(
                  builder: (context, setState) => SingleChildScrollView(
                    child: EventScopeEditor(
                      scopeKey: 'test-event',
                      title: 'Events',
                      description: 'Separate consent',
                      choice: choice,
                      canEdit: true,
                      onChanged: (next) => setState(() {
                        choice = next;
                        changes++;
                        origins.add(
                          StarBridgeActivationOrigin.sourceOf(context),
                        );
                      }),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            expect(find.byType(StarBridgeSwitch), findsNWidgets(5));
            expect(
              t
                  .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                  .every((w) => w.onChanged == null),
              isTrue,
            );
            await toggle(
              t,
              'privacy-scope-test-event-audience-events-enabled',
              source,
              checkbox: true,
            );
            expect(choice.enabled, isTrue);
            expect(choice.selectedTypes, 36);
            await toggle(t, 'privacy-scope-test-event-field-life', source);
            expect(choice.selectedTypes, 4);
            await toggle(
              t,
              'privacy-scope-test-event-audience-events-enabled',
              source,
              checkbox: true,
            );
            expect(choice.enabled, isFalse);
            expect(choice.selectedTypes, 4);
            expect(choice.effectiveTypes, 0);
            expect(changes, 3);
            expect(
              origins,
              List.filled(
                3,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            );
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pump();
            semantics.dispose();
          }
        },
      );
    }
  }
}

class HeldSave extends SharingFixture {
  Completer<LocalPrivacySnapshot>? held;
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings value) =>
      held?.future ?? super.save(value);
}

void adjacent(InteractionSuite suite) {
  testWidgets('$suite preset caret remains inside the actual menu hit target', (
    t,
  ) async {
    final port = presets.Port();
    await presets.mount(t, port, suite);
    try {
      final selector = find.byKey(
        const ValueKey('overlay-preset-selector-one'),
      );
      final caret = find.descendant(
        of: selector,
        matching: suite == InteractionSuite.standard
            ? find.byType(NativeDropdownIndicatorIcon)
            : find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeIcon &&
                    w.semantic == StarBridgeIconSemantic.menuDown,
              ),
      );
      expect(caret, findsOneWidget);
      if (suite == InteractionSuite.standard) {
        expect(t.getSize(selector), const Size(200, 44));
      }
      await t.tapAt(t.getCenter(caret));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<Object>('overlay-preset-select-two')),
        findsOneWidget,
      );
      expect(port.writes, isEmpty);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump();
      expect(
        find.byKey(const ValueKey<Object>('overlay-preset-select-two')),
        findsNothing,
      );
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }
  });
  testWidgets(
    '$suite cancelled returning pointer press never commits and can retry',
    (t) async {
      final p = SharingFixture(), c = LocalPrivacyController(p);
      try {
        await c.refresh();
        await t.pumpWidget(scopeApp(c, suite, 'room'));
        await t.pumpAndSettle();
        await toggle(t, 'privacy-scope-room-field-presence', 'keyboard');
        await toggle(t, 'privacy-scope-room-field-ship', 'keyboard');
        final fields = c.draft!.roomFields;
        final row = find.byKey(const Key('privacy-scope-room-field-presence'));
        final gesture = await t.startGesture(t.getCenter(row));
        await t.pump(const Duration(milliseconds: 16));
        await gesture.cancel();
        await t.pumpAndSettle();
        expect(c.draft!.roomFields, fields);
        await toggle(t, 'privacy-scope-room-field-presence', 'pointer');
        expect(c.draft!.roomFields, fields ^ 1);
        expect(p.writes, 0);
      } finally {
        await clean(t, c, p);
      }
    },
  );
  testWidgets(
    '$suite returning pointer press remains intact across a painted focus frame',
    (t) async {
      final p = SharingFixture(), c = LocalPrivacyController(p);
      try {
        await c.refresh();
        await t.pumpWidget(scopeApp(c, suite, 'room'));
        await t.pumpAndSettle();
        await toggle(t, 'privacy-scope-room-field-presence', 'keyboard');
        await toggle(t, 'privacy-scope-room-field-ship', 'keyboard');
        final fields = c.draft!.roomFields;
        final row = find.byKey(const Key('privacy-scope-room-field-presence'));
        final gesture = await t.startGesture(t.getCenter(row));
        await t.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await t.pump(const Duration(milliseconds: 16));
        expect(c.draft!.roomFields, fields ^ 1);
        expect(t.binding.hasScheduledFrame, isTrue);
        await t.pumpAndSettle();
        expect(p.writes, 0);
      } finally {
        await clean(t, c, p);
      }
    },
  );
  for (final source in ['keyboard', 'reader']) {
    testWidgets(
      '$suite $source field and checkbox complete without animation tail',
      (t) async {
        final p = SharingFixture(),
            c = LocalPrivacyController(p),
            semantics = t.ensureSemantics();
        try {
          await c.refresh();
          await t.pumpWidget(scopeApp(c, suite, 'room'));
          await t.pumpAndSettle();
          final fields = c.draft!.roomFields,
              audience = c.draft!.roomAllMembersCanView;
          await toggle(
            t,
            'privacy-scope-room-field-presence',
            source,
            settle: false,
          );
          expect(c.draft!.roomFields, fields ^ 1);
          expect(t.binding.hasScheduledFrame, isFalse);
          await toggle(
            t,
            'privacy-scope-room-audience-members',
            source,
            checkbox: true,
            settle: false,
          );
          expect(c.draft!.roomAllMembersCanView, !audience);
          expect(t.binding.hasScheduledFrame, isFalse);
          expect(p.writes, 0);
        } finally {
          await clean(t, c, p);
          semantics.dispose();
        }
      },
    );
  }
  for (final source in ['pointer', 'keyboard', 'reader']) {
    testWidgets(
      '$suite $source real event page edits drafts and saves only explicitly',
      (t) async {
        final h = events.Harness(),
            drafts = PrivacyPageDrafts(),
            semantics = t.ensureSemantics();
        try {
          await t.runAsync(h.ready);
          await t.pumpWidget(
            scopedApp(
              PrivacyDraftScope(
                drafts: drafts,
                child: EventSharingPage(session: h.session),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          expect(find.byType(StarBridgeSwitch), findsNWidgets(15));
          final before = drafts.value(
            'event-choices',
            <String?, EventSharingChoice>{},
          );
          expect(before[null]!.selectedTypes, 47);
          expect(h.writes, isEmpty);
          await toggle(t, 'privacy-scope-event-room-field-life', source);
          await toggle(
            t,
            'privacy-scope-event-room-audience-events-enabled',
            source,
            checkbox: true,
          );
          var value = drafts.value(
            'event-choices',
            <String?, EventSharingChoice>{},
          );
          expect(value[null]!.enabled, isFalse);
          expect(value[null]!.selectedTypes, 15);
          expect(value['A'], before['A']);
          expect(value['B'], before['B']);
          expect(h.writes, isEmpty);
          await toggle(
            t,
            'privacy-scope-event-room-audience-events-enabled',
            source,
            checkbox: true,
          );
          value = drafts.value(
            'event-choices',
            <String?, EventSharingChoice>{},
          );
          expect(value[null]!.selectedTypes, 15);
          final save = drafts.save();
          await t.pumpAndSettle();
          expect(await save, isTrue);
          expect(h.writes, hasLength(1));
          expect(
            (h.writes.single.payload['settings'] as Map)['room'],
            value[null]!.toJson(),
          );
          expect(drafts.dirty, isFalse);
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          drafts.dispose();
          await t.runAsync(h.close);
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '$suite $source saving disables fields and failed save keeps exact draft',
      (t) async {
        final p = HeldSave(),
            c = LocalPrivacyController(p),
            semantics = t.ensureSemantics();
        try {
          await c.refresh();
          await t.pumpWidget(scopeApp(c, suite, 'room'));
          await t.pumpAndSettle();
          await toggle(t, 'privacy-scope-room-field-presence', source);
          final draft = c.draft;
          p.held = Completer<LocalPrivacySnapshot>();
          final save = c.save();
          await t.pump();
          expect(
            t
                .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                .every((w) => w.onChanged == null),
            isTrue,
          );
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byType(StarBridgeCheckboxTile),
                )
                .onChanged,
            isNull,
          );
          p.held!.completeError(StateError('refused'));
          expect(await save, isFalse);
          p.held = null;
          await t.pumpAndSettle();
          expect(identical(c.draft, draft), isTrue);
          expect(p.writes, 0);
          expect(p.applies, 0);
          expect(await c.save(), isTrue);
          await t.pumpAndSettle();
          expect(p.writes, 1);
        } finally {
          await clean(t, c, p);
          semantics.dispose();
        }
      },
    );
  }
  for (final light in [false, true]) {
    testWidgets(
      '$suite light=$light preserves domain accent and compact geometry',
      (t) async {
        final p = SharingFixture(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await t.pumpWidget(scopeApp(c, suite, 'room', light: light));
          await t.pumpAndSettle();
          final control = t.widget<StarBridgeSwitch>(
            find.byKey(const Key('privacy-scope-room-field-presence')),
          );
          final raw = find.byKey(
            const Key('privacy-scope-room-switch-presence'),
          );
          expect(
            t
                .getRect(
                  find.byKey(const Key('privacy-scope-room-field-presence')),
                )
                .height,
            inInclusiveRange(48, 52),
          );
          expect(control.activeTrackColor, isNotNull);
          if (suite == InteractionSuite.standard) {
            expect(
              t.widget<Switch>(raw).activeTrackColor,
              control.activeTrackColor,
            );
          } else {
            expect(
              InteractionScope.of(t.element(raw)).palette.accent,
              control.activeTrackColor,
            );
          }
        } finally {
          await clean(t, c, p);
        }
      },
    );
  }
  testWidgets(
    '$suite placeholder fields have no activation or persistence path',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(
          scopedApp(const LocalPrivacyMainFleetPlaceholder(), suite),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
              .every((w) => w.onChanged == null),
          isTrue,
        );
        final node = t.getSemantics(
          find.byKey(const Key('privacy-scope-official-fleet-field-presence')),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        semantics.dispose();
      }
    },
  );
  testWidgets(
    '$suite rapid active reversals update every request and live reduce stops feedback',
    (t) async {
      final p = SharingFixture(), c = LocalPrivacyController(p);
      try {
        await c.refresh();
        await t.pumpWidget(scopeApp(c, suite, 'room'));
        await t.pumpAndSettle();
        final fields = c.draft!.roomFields;
        final row = find.byKey(const Key('privacy-scope-room-field-presence'));
        for (var i = 0; i < 5; i++) {
          await t.tapAt(t.getCenter(row));
          await t.pump(const Duration(milliseconds: 20));
          expect(c.draft!.roomFields, i.isEven ? fields ^ 1 : fields);
        }
        expect(t.binding.hasScheduledFrame, isTrue);
        await t.pumpWidget(scopeApp(c, suite, 'room', reduce: true));
        await t.pump();
        await t.pump();
        expect(t.binding.hasScheduledFrame, isFalse);
        expect(c.draft!.roomFields, fields ^ 1);
        expect(p.writes, 0);
        expect(p.applies, 0);
      } finally {
        await clean(t, c, p);
      }
    },
  );
}
