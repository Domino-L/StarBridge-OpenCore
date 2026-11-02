import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scope_sections.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

import '../../features/settings/community_sharing_test.dart'
    show SharingFixture, target;
import 'interaction_batch3bo_test.dart' show scopeApp, clean;
import 'interaction_batch3do_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> _twoFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

FocusNode _fieldFocus(WidgetTester t, String id) {
  final row = find.byKey(Key(id));
  expect(row, findsOneWidget);
  final target = find.descendant(
    of: row,
    matching: find.byType(SuitePressable),
  );
  expect(target, findsOneWidget);
  final focus = t.widget<SuitePressable>(target).focusNode!;
  expect(focus.canRequestFocus, isTrue);
  return focus;
}

FocusNode _checkboxFocus(WidgetTester t, String id) {
  final row = find.byKey(Key(id));
  expect(row, findsOneWidget);
  final native = find.descendant(of: row, matching: find.byType(Checkbox));
  if (native.evaluate().isNotEmpty) {
    expect(native, findsOneWidget);
    return t.widget<Checkbox>(native).focusNode!;
  }
  final custom = find.descendant(of: row, matching: find.byType(SuiteCheckbox));
  expect(custom, findsOneWidget);
  return t.widget<SuiteCheckbox>(custom).focusNode!;
}

/// Observe the widget's public node but move focus exclusively with actual Tab.
/// No requestFocus, nearest Focus ancestor, controller edit or direct callback
/// substitutes for the user input whose behavior these cases establish.
Future<void> _tabSpace(WidgetTester t, FocusNode target) async {
  expect(target.canRequestFocus, isTrue);
  var steps = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await _twoFrames(t);
    steps++;
  } while (!target.hasPrimaryFocus && steps < 48);
  expect(steps, inInclusiveRange(1, 48));
  expect(FocusManager.instance.primaryFocus, same(target));
  await t.sendKeyEvent(LogicalKeyboardKey.space);
  await _twoFrames(t);
}

void _keyboardFieldPresentation(
  WidgetTester t,
  String controlId,
  InteractionSuite suite,
) {
  final control = find.byKey(Key(controlId));
  expect(control, findsOneWidget);
  if (suite == InteractionSuite.standard) {
    expect(TickerMode.valuesOf(t.element(control)).enabled, isFalse);
  } else {
    expect(
      t.widget<SuiteSwitch>(control).changeSource,
      InteractionSource.keyboard,
    );
  }
}

void _draftOnly(
  LocalPrivacyController owner,
  SharingFixture port, {
  required LocalPrivacySettings saved,
  required int revision,
  required int epoch,
  required Object publication,
  required LocalPrivacySettings expected,
}) {
  expect(owner.status, LocalPrivacyStatus.ready);
  expect(owner.canEdit, isTrue);
  expect(owner.hasSaved, isTrue);
  expect(owner.dirty, isTrue);
  expect(owner.saving, isFalse);
  expect(owner.revision, revision);
  expect(owner.scopeEpoch, epoch);
  expect(owner.publicationView, same(publication));
  expect(owner.draft!.toJson(), expected.toJson());
  expect(port.settings, same(saved));
  expect(port.revision, revision);
  expect(port.writes, 0);
  expect(port.applies, 0);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite real Tab Space room fields and audience stay draft-only and returning pointer keeps local motion enabled',
      (t) async {
        size(t, const Size(1000, 850));
        final port = SharingFixture();
        final owner = LocalPrivacyController(port);
        final semantics = t.ensureSemantics();
        final sources = <InteractionSource>[];
        void observe() => sources.add(currentStarBridgeActivationSource);
        try {
          await owner.refresh();
          await t.pumpWidget(scopeApp(owner, suite, 'room'));
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(
            t
                .widget<LocalPrivacyRoomSection>(
                  find.byType(LocalPrivacyRoomSection),
                )
                .controller,
            same(owner),
          );
          expect(owner.dirty, isFalse);
          final saved = port.settings;
          final revision = owner.revision;
          final epoch = owner.scopeEpoch;
          final publication = owner.publicationView;
          expect(owner.draft, same(saved));
          expect(saved.roomFields, 15);
          expect(find.byType(StarBridgeSwitch), findsNWidgets(4));
          expect(find.byType(StarBridgeCheckboxTile), findsOneWidget);
          owner.addListener(observe);

          await _tabSpace(
            t,
            _fieldFocus(t, 'privacy-scope-room-field-presence'),
          );
          _draftOnly(
            owner,
            port,
            saved: saved,
            revision: revision,
            epoch: epoch,
            publication: publication,
            expected: saved.copyWith(roomFields: 14),
          );
          expect(sources, [InteractionSource.keyboard]);
          expect(
            t
                .widget<StarBridgeSwitch>(
                  find.byKey(const Key('privacy-scope-room-field-presence')),
                )
                .value,
            isFalse,
          );
          _keyboardFieldPresentation(
            t,
            'privacy-scope-room-switch-presence',
            suite,
          );

          await _tabSpace(
            t,
            _checkboxFocus(t, 'privacy-scope-room-audience-members'),
          );
          _draftOnly(
            owner,
            port,
            saved: saved,
            revision: revision,
            epoch: epoch,
            publication: publication,
            expected: saved.copyWith(
              roomFields: 14,
              roomAllMembersCanView: !saved.roomAllMembersCanView,
            ),
          );
          expect(sources, [
            InteractionSource.keyboard,
            InteractionSource.keyboard,
          ]);
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byKey(const Key('privacy-scope-room-audience-members')),
                )
                .value,
            !saved.roomAllMembersCanView,
          );

          final row = find.byKey(
            const Key('privacy-scope-room-field-presence'),
          );
          await t.ensureVisible(row);
          await t.pump();
          await t.tapAt(t.getCenter(row));
          await t.pump(const Duration(milliseconds: 16));
          _draftOnly(
            owner,
            port,
            saved: saved,
            revision: revision,
            epoch: epoch,
            publication: publication,
            expected: saved.copyWith(
              roomFields: 15,
              roomAllMembersCanView: !saved.roomAllMembersCanView,
            ),
          );
          expect(sources, [
            InteractionSource.keyboard,
            InteractionSource.keyboard,
            InteractionSource.pointer,
          ]);
          final control = find.byKey(
            const Key('privacy-scope-room-switch-presence'),
          );
          // Local permission/source only, not a claim of pixel animation.
          expect(TickerMode.valuesOf(t.element(control)).enabled, isTrue);
          if (suite != InteractionSuite.standard) {
            expect(
              t.widget<SuiteSwitch>(control).changeSource,
              InteractionSource.pointer,
            );
          }
          expect(
            currentStarBridgeActivationSource,
            // The legacy compatibility getter falls back to pointer outside
            // an active command; this is not captureStarBridgeActivationSource.
            InteractionSource.pointer,
          );
          expect(t.takeException(), isNull);
        } finally {
          owner.removeListener(observe);
          await clean(t, owner, port);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite real Tab Space organization field and members preserve grant identity and mutual exclusion',
      (t) async {
        size(t, const Size(1000, 850));
        // Pre-existing typed saved facts, not a UI grant callback or edit.
        final port = SharingFixture()
          ..settings = LocalPrivacySettings.editorDefaults.copyWith(
            communities: [
              target('A')
                  .choice(fields: 3)
                  .copyWith(
                    administratorsCanView: true,
                    allMembersCanView: false,
                  ),
            ],
          );
        final owner = LocalPrivacyController(port);
        final semantics = t.ensureSemantics();
        final sources = <InteractionSource>[];
        void observe() => sources.add(currentStarBridgeActivationSource);
        try {
          await owner.refresh();
          await t.pumpWidget(scopeApp(owner, suite, 'organization'));
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(
            t
                .widget<LocalPrivacyOrganizationsSection>(
                  find.byType(LocalPrivacyOrganizationsSection),
                )
                .controller,
            same(owner),
          );
          final saved = port.settings;
          final originalScope = saved.communities!.single;
          final revision = owner.revision;
          final epoch = owner.scopeEpoch;
          final publication = owner.publicationView;
          expect(owner.dirty, isFalse);
          expect(owner.draft, same(saved));
          expect(find.byType(StarBridgeSwitch), findsNWidgets(8));
          owner.addListener(observe);

          await _tabSpace(t, _fieldFocus(t, 'privacy-scope-A-field-presence'));
          _draftOnly(
            owner,
            port,
            saved: saved,
            revision: revision,
            epoch: epoch,
            publication: publication,
            expected: saved.copyWith(
              communities: [originalScope.copyWith(fields: 2)],
            ),
          );
          expect(sources, [InteractionSource.keyboard]);
          _keyboardFieldPresentation(
            t,
            'privacy-scope-A-switch-presence',
            suite,
          );
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byKey(
                    const Key('privacy-scope-A-audience-administrators'),
                  ),
                )
                .onChanged,
            isNotNull,
          );

          await _tabSpace(
            t,
            _checkboxFocus(t, 'privacy-scope-A-audience-members'),
          );
          _draftOnly(
            owner,
            port,
            saved: saved,
            revision: revision,
            epoch: epoch,
            publication: publication,
            expected: saved.copyWith(
              communities: [
                originalScope.copyWith(
                  fields: 2,
                  administratorsCanView: false,
                  allMembersCanView: true,
                ),
              ],
            ),
          );
          expect(sources, [
            InteractionSource.keyboard,
            InteractionSource.keyboard,
          ]);
          final scope = owner.draft!.communities!.single;
          expect(scope.code, originalScope.code);
          expect(scope.joinedAt, originalScope.joinedAt);
          expect(scope.visibilityGroupIds, originalScope.visibilityGroupIds);
          expect(scope.memberOverrides, originalScope.memberOverrides);
          final admins = t.widget<StarBridgeCheckboxTile>(
            find.byKey(const Key('privacy-scope-A-audience-administrators')),
          );
          expect(admins.value, isFalse);
          expect(admins.onChanged, isNull);
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byKey(const Key('privacy-scope-A-audience-members')),
                )
                .value,
            isTrue,
          );
          expect(owner.unconfirmedCommunities.map((choice) => choice.code), [
            'B',
          ]);
          expect(
            currentStarBridgeActivationSource,
            // The legacy compatibility getter falls back to pointer outside
            // an active command; this is not captureStarBridgeActivationSource.
            InteractionSource.pointer,
          );
          expect(t.takeException(), isNull);
        } finally {
          owner.removeListener(observe);
          await clean(t, owner, port);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite real Tab Space event enable life and disable preserve selected mask and exact keyboard origins',
      (t) async {
        size(t, const Size(1000, 850));
        var choice = const EventSharingChoice(
          enabled: false,
          selectedTypes: 36,
        );
        final changes = <EventSharingChoice>[];
        final sources = <InteractionSource>[];
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
                      changes.add(next);
                      sources.add(currentStarBridgeActivationSource);
                    }),
                  ),
                ),
              ),
              suite,
            ),
          );
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(StarBridgeSwitch), findsNWidgets(5));
          expect(
            t
                .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                .every((control) => control.onChanged == null),
            isTrue,
          );
          expect(choice.effectiveTypes, 0);
          expect(changes, isEmpty);

          await _tabSpace(
            t,
            _checkboxFocus(
              t,
              'privacy-scope-test-event-audience-events-enabled',
            ),
          );
          expect(
            choice,
            const EventSharingChoice(enabled: true, selectedTypes: 36),
          );
          expect(choice.effectiveTypes, 36);
          expect(changes, hasLength(1));
          expect(sources, [InteractionSource.keyboard]);
          expect(
            t
                .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                .every((control) => control.onChanged != null),
            isTrue,
          );

          await _tabSpace(
            t,
            _fieldFocus(t, 'privacy-scope-test-event-field-life'),
          );
          expect(
            choice,
            const EventSharingChoice(enabled: true, selectedTypes: 4),
          );
          expect(choice.effectiveTypes, 4);
          expect(changes, hasLength(2));
          _keyboardFieldPresentation(
            t,
            'privacy-scope-test-event-switch-life',
            suite,
          );

          await _tabSpace(
            t,
            _checkboxFocus(
              t,
              'privacy-scope-test-event-audience-events-enabled',
            ),
          );
          expect(
            choice,
            const EventSharingChoice(enabled: false, selectedTypes: 4),
          );
          expect(choice.effectiveTypes, 0);
          expect(changes, const [
            EventSharingChoice(enabled: true, selectedTypes: 36),
            EventSharingChoice(enabled: true, selectedTypes: 4),
            EventSharingChoice(enabled: false, selectedTypes: 4),
          ]);
          expect(sources, List.filled(3, InteractionSource.keyboard));
          expect(
            t
                .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                .every((control) => control.onChanged == null),
            isTrue,
          );
          expect(
            t
                .widget<StarBridgeCheckboxTile>(
                  find.byKey(
                    const Key(
                      'privacy-scope-test-event-audience-events-enabled',
                    ),
                  ),
                )
                .onChanged,
            isNotNull,
          );
          expect(
            currentStarBridgeActivationSource,
            // The legacy compatibility getter falls back to pointer outside
            // an active command; this is not captureStarBridgeActivationSource.
            InteractionSource.pointer,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
