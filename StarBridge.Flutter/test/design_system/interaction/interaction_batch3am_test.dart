import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/communities/community_roles_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_roles_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_management_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_settings_workspace.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import '../../features/communities/community_roles_test.dart' show RolesFake;
import '../../features/communities/community_management_dialog_test.dart'
    show ManagementTestPort;
import '../../features/communities/community_workspace_test.dart'
    show workspacePayload;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ak_test.dart' as shared show action;
import 'interaction_batch3aa_test.dart' as choices show open, select, reader;

import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';

const target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const applicant = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const invite = 'dddddddddddddddddddddddddddddddd';

class Roles extends RolesFake {
  final origins = <InteractionSource>[];
  String? sentRef, sentId;
  @override
  Future<CommunityProfileOutcome> saveRoles(
    String id,
    String ref,
    List<CommunityRole> roles, {
    bool confirmUncertainRetry = false,
  }) {
    origins.add(currentStarBridgeActivationSource);
    sentRef = ref;
    sentId = id;
    return super.saveRoles(
      id,
      ref,
      roles,
      confirmUncertainRetry: confirmUncertainRetry,
    );
  }
}

class Management extends ManagementTestPort {
  final origins = <InteractionSource>[];
  final readOrigins = <InteractionSource>[];
  bool failRead = false;
  @override
  Future<CommunityAdmissionsPage> readAdmissions(
    String ref,
    String section,
    int offset,
  ) {
    readOrigins.add(currentStarBridgeActivationSource);
    if (failRead) {
      return Future.error(const CommunityFailure('unavailable'));
    }
    return super.readAdmissions(ref, section, offset);
  }

  @override
  Future<CommunityAdmissionOutcome> manageAdmissions(
    CommunityAdmissionIntent intent,
  ) {
    origins.add(currentStarBridgeActivationSource);
    return super.manageAdmissions(intent);
  }
}

class Settings extends Management
    implements CommunityWorkspacePort, CommunityRolesPort {
  final roles = Roles();
  int summaries = 0;
  @override
  bool get rolesAvailable => true;
  @override
  Future<CommunityWorkspace> readWorkspace(
    String ref,
    String query,
    int offset,
  ) async {
    summaries++;
    return snapshot();
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) => Future.error(const CommunityFailure('unavailable'));
  @override
  Future<CommunityEditingRoles> readRoles({
    String? targetRef,
    String? editRef,
  }) => roles.readRoles(targetRef: targetRef, editRef: editRef);
  @override
  Future<CommunityProfileOutcome> saveRoles(
    String id,
    String ref,
    List<CommunityRole> values, {
    bool confirmUncertainRetry = false,
  }) => roles.saveRoles(
    id,
    ref,
    values,
    confirmUncertainRetry: confirmUncertainRetry,
  );
}

CommunityWorkspace snapshot() {
  final data = workspacePayload();
  (data['access'] as Map)['isOwner'] = true;
  return CommunityWorkspace.parse(data);
}

Widget settings(
  Settings port, {
  VoidCallback? onMembers,
  ValueChanged<Set<String>>? onChanged,
}) => CommunitySettingsWorkspace(
  port: port,
  workspace: snapshot(),
  targetRef: target,
  onMembers: onMembers ?? () {},
  onWorkspaceChanged: onChanged,
  dangerActions: const SizedBox(),
  hasDangerActions: false,
);
Future<void> action(
  WidgetTester t,
  Key key,
  String source, {
  bool settle = true,
}) async {
  if (source == 'reader') {
    final chip = find.byWidgetPredicate(
      (w) => w is StarBridgeChoiceChip && w.controlKey == key,
    );
    if (chip.evaluate().isNotEmpty) {
      choices.reader(t, t.widget<StarBridgeChoiceChip>(chip).label);
      await t.pump();
      await t.pump();
      if (settle) {
        await settleCommunityImages(t);
      }
      return;
    }
  }
  final row = find.byWidgetPredicate(
    (w) => w is StarBridgeActionRow && w.controlKey == key,
  );
  final tile = find.descendant(
    of: find.byKey(key),
    matching: find.byType(ListTile),
  );
  if (source == 'keyboard' &&
      row.evaluate().isNotEmpty &&
      tile.evaluate().isNotEmpty) {
    await t.ensureVisible(tile.first);
    final controls = find.descendant(
      of: find.byKey(key),
      matching: find.byType(FocusableActionDetector),
    );
    final owner = controls.evaluate().isEmpty
        ? null
        : t.widget<FocusableActionDetector>(controls.first).focusNode;
    (owner ?? Focus.of(t.element(tile.first))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    if (settle) {
      await settleCommunityImages(t);
    }
  } else {
    await shared.action(t, key, source, settle: settle);
  }
}

Future<void> toggle(WidgetTester t, String id, String source) async {
  final config = find.byWidgetPredicate(
    (w) => w is StarBridgeSwitch && w.controlKey == ValueKey(id),
  );
  await t.ensureVisible(config);
  await t.pumpAndSettle();
  if (source == 'pointer') {
    await t.tap(config);
  } else if (source == 'keyboard') {
    final control = t.widget(find.byKey(ValueKey(id)));
    (control is Switch
            ? control.focusNode!
            : (control as SuiteSwitch).focusNode!)
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final node = t.getSemantics(config);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pumpAndSettle();
}

Future<void> choose(
  WidgetTester t,
  String id,
  String key,
  int value,
  String source,
) async {
  await choices.open(t, ValueKey(key), source);
  await t.pumpAndSettle();
  if (source == 'reader') {
    final anchor = find.byWidgetPredicate(
      (w) =>
          w is StarBridgeMenuAnchor &&
          w.entries.any((e) => e.id == (id, value)),
    );
    final label = t
        .widget<StarBridgeMenuAnchor>(anchor)
        .entries
        .singleWhere((e) => e.id == (id, value))
        .label;
    choices.reader(t, label);
    await t.pump();
    await t.pump();
  } else {
    await choices.select(t, id, value, source);
  }
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'invite copy retains read-only command and clipboard failure $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Management();
          addTearDown(port.changes.close);
          final copied = <String>[];
          var fail = false;
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                if (fail) {
                  throw PlatformException(code: 'clipboard_busy');
                }
                copied.add((call.arguments as Map)['text'] as String);
              }
              return null;
            },
          );
          addTearDown(
            () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          try {
            await mount(
              t,
              CommunityManagementDialog(
                port: port,
                targetRef: target,
                name: 'Organization A',
                embedded: true,
                initialSection: 'invites',
              ),
              suite,
              width: 850,
            );
            await action(t, const Key('management-copy-$invite'), source);
            expect(copied, ['STAR-INVITE']);
            expect(port.intents, isEmpty);
            final state = t.state<CommunityManagementDialogState>(
              find.byType(CommunityManagementDialog),
            );
            expect(state.copyStatus, 'copied');
            fail = true;
            await action(t, const Key('management-copy-$invite'), source);
            expect(state.copyStatus, 'copyFailed');
            expect(copied.length, 1);
            expect(port.intents, isEmpty);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'roles inline navigation draft permission copy delete and original save $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Settings();
          addTearDown(port.changes.close);
          addTearDown(port.roles.events.close);
          var callbacks = 0;
          try {
            await mount(
              t,
              settings(port, onChanged: (_) => callbacks++),
              suite,
              width: 1000,
            );
            await action(t, const Key('settings-quick-roles'), source);
            final state = t.state<CommunityRolesDialogState>(
              find.byType(CommunityRolesDialog),
            );
            await action(t, const Key('role-custom_navigation'), source);
            await t.enterText(find.byKey(const Key('role-name')), 'Navigator');
            await t.pump();
            await toggle(t, 'fleet.profile.edit', source);
            expect(
              state.model.selected!.permissions,
              isNot(contains('fleet.profile.edit')),
            );
            expect(
              state.model.selected!.permissions,
              contains('future.preserved'),
            );
            await action(t, const Key('role-color-#32D296'), source);
            expect(state.model.selected!.color, '#32D296');
            await action(t, const Key('roles-copy'), source);
            expect(state.model.roles.length, 4);
            expect(port.roles.writes, 0);
            await action(t, const Key('roles-delete'), source);
            await action(t, const Key('roles-confirm-cancel'), source);
            expect(state.model.roles.length, 4);
            await action(t, const Key('roles-delete'), source);
            await action(t, const Key('roles-confirm-accept'), source);
            expect(state.model.roles.length, 3);
            expect(port.roles.writes, 0);
            await action(t, const Key('roles-save'), source);
            expect(port.roles.writes, 1);
            expect(callbacks, 1);
            expect(state.model.dirty, false);
            expect(
              port.roles.saved!
                  .singleWhere((r) => r.key == 'custom_navigation')
                  .name,
              'Navigator',
            );
            expect(port.roles.sentId, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(port.roles.sentRef, 'b' * 32);
            expect(
              port.roles.origins.single,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(port.summaries, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      for (final operation in ['approve', 'decline', 'generate', 'revoke']) {
        testWidgets(
          'management precise confirmed intent $suite $source $operation',
          (t) async {
            final semantics = t.ensureSemantics(), port = Management();
            addTearDown(port.changes.close);
            var callbacks = 0;
            try {
              await mount(
                t,
                CommunityManagementDialog(
                  port: port,
                  targetRef: target,
                  name: 'Organization A',
                  embedded: true,
                  onMembersChanged: () => callbacks++,
                ),
                suite,
                width: 850,
              );
              if (operation == 'generate' || operation == 'revoke') {
                await action(
                  t,
                  const Key('management-section-invites'),
                  source,
                );
                if (operation == 'generate') {
                  await choose(
                    t,
                    'community-invite-days',
                    'community-invite-days-control',
                    30,
                    source,
                  );
                  await choose(
                    t,
                    'community-invite-uses',
                    'community-invite-uses-control',
                    5,
                    source,
                  );
                }
              }
              final key = operation == 'generate'
                  ? 'management-generate'
                  : operation == 'revoke'
                  ? 'management-revoke-$invite'
                  : 'management-$operation-$applicant';
              await action(t, Key(key), source);
              expect(port.intents, isEmpty);
              final route =
                  ModalRoute.of(
                        t.element(
                          find.byKey(const Key('management-confirm-accept')),
                        ),
                      )!
                      as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              await action(t, const Key('management-confirm-cancel'), source);
              expect(port.intents, isEmpty);
              await action(t, Key(key), source);
              await action(t, const Key('management-confirm-accept'), source);
              final intent = port.intents.single;
              expect(intent.targetRef, target);
              expect(intent.requestId, matches(RegExp(r'^[a-f0-9]{32}$')));
              expect(
                intent.toPayload()['action'],
                operation == 'generate'
                    ? 'generateInvite'
                    : operation == 'revoke'
                    ? 'revokeInvite'
                    : operation,
              );
              expect(intent.confirmUncertainRetry, false);
              expect(
                intent.entryRef,
                operation == 'generate'
                    ? null
                    : operation == 'revoke'
                    ? invite
                    : applicant,
              );
              if (operation == 'generate') {
                expect((intent.expiresInDays, intent.maxUses), (30, 5));
              }
              expect(
                port.origins.single,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(callbacks, operation == 'approve' ? 1 : 0);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
    for (final operation in ['roles', 'management']) {
      testWidgets(
        'editor disposal retires private secondary confirmation $suite $operation',
        (t) async {
          final roles = Roles(), management = Management();
          addTearDown(roles.events.close);
          addTearDown(management.changes.close);
          final live = await mount(
            t,
            operation == 'roles'
                ? CommunityRolesDialog(
                    port: roles,
                    targetRef: target,
                    embedded: true,
                  )
                : CommunityManagementDialog(
                    port: management,
                    targetRef: target,
                    name: 'Private workspace',
                    embedded: true,
                  ),
            suite,
            width: 900,
          );
          if (operation == 'roles') {
            await action(t, const Key('role-custom_navigation'), 'keyboard');
            await action(t, const Key('roles-delete'), 'keyboard');
          } else {
            await action(
              t,
              const Key('management-approve-$applicant'),
              'keyboard',
            );
          }
          live.change(() => live.visible = false);
          await settleCommunityImages(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(roles.writes, 0);
          expect(management.intents, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'owner permissions and unavailable broadcast remain disabled $suite',
      (t) async {
        final semantics = t.ensureSemantics(), port = Roles();
        addTearDown(port.events.close);
        try {
          await mount(
            t,
            CommunityRolesDialog(port: port, targetRef: target, embedded: true),
            suite,
            width: 900,
          );
          final state = t.state<CommunityRolesDialogState>(
            find.byType(CommunityRolesDialog),
          );
          expect(state.model.selected!.owner, true);
          for (final id in ['fleet.profile.edit']) {
            final config = find.byWidgetPredicate(
              (w) => w is StarBridgeSwitch && w.controlKey == ValueKey(id),
            );
            expect(t.widget<StarBridgeSwitch>(config).onChanged, isNull);
            expect(
              t
                  .getSemantics(config)
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              false,
            );
          }
          await action(t, const Key('role-custom_navigation'), 'keyboard');
          expect(find.byKey(const ValueKey('broadcasts.publish')), findsNothing);
          expect(port.writes, 0);
          expect(state.model.dirty, false);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'read-only applications expose no approval or rejection action $suite',
      (t) async {
        final semantics = t.ensureSemantics(),
            port = Management()..canDecide = false;
        addTearDown(port.changes.close);
        try {
          await mount(
            t,
            CommunityManagementDialog(
              port: port,
              targetRef: target,
              name: 'Organization A',
              embedded: true,
            ),
            suite,
            width: 850,
          );
          for (final key in [
            'management-approve-$applicant',
            'management-decline-$applicant',
          ]) {
            final config = find.byWidgetPredicate(
              (w) => w is StarBridgeActionButton && w.controlKey == Key(key),
            );
            expect(t.widget<StarBridgeActionButton>(config).onActivate, isNull);
            expect(
              t
                  .getSemantics(find.byKey(Key(key)))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              false,
            );
          }
          expect(port.intents, isEmpty);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'settings role draft cancel stays, approved leave follows origin $suite',
      (t) async {
        final port = Settings();
        addTearDown(port.changes.close);
        addTearDown(port.roles.events.close);
        await mount(t, settings(port), suite, width: 1000);
        await action(t, const Key('settings-nav-roles'), 'pointer');
        final state = t.state<CommunityRolesDialogState>(
          find.byType(CommunityRolesDialog),
        );
        await action(t, const Key('role-custom_navigation'), 'pointer');
        await t.enterText(find.byKey(const Key('role-name')), 'Draft');
        await t.pump();
        await action(t, const Key('settings-nav-admissions'), 'pointer');
        await action(t, const Key('roles-confirm-cancel'), 'keyboard');
        expect(
          t.state<CommunityRolesDialogState>(find.byType(CommunityRolesDialog)),
          same(state),
        );
        expect(state.name.text, 'Draft');
        expect(port.roles.writes, 0);
        await action(t, const Key('settings-nav-admissions'), 'keyboard');
        final route =
            ModalRoute.of(
                  t.element(find.byKey(const Key('roles-confirm-accept'))),
                )!
                as StarBridgeDialogRoute;
        expect(route.instant, true);
        await action(t, const Key('roles-confirm-accept'), 'keyboard');
        expect(find.byType(CommunityRolesDialog), findsNothing);
        expect(find.byType(CommunityManagementDialog), findsOneWidget);
        expect(port.roles.writes, 0);
        expect(port.readOrigins.length, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'role failure keeps dirty input and pending writer is not repeated $suite',
      (t) async {
        final port = Roles()
          ..pendingSave = Completer<CommunityProfileOutcome>();
        addTearDown(port.events.close);
        await mount(
          t,
          CommunityRolesDialog(port: port, targetRef: target, embedded: true),
          suite,
          width: 900,
        );
        await action(t, const Key('role-custom_navigation'), 'pointer');
        await t.enterText(find.byKey(const Key('role-name')), 'Retained');
        await t.pump();
        await action(t, const Key('roles-save'), 'keyboard', settle: false);
        expect(port.writes, 1);
        final button = t.widget<StarBridgeActionButton>(
          find.byWidgetPredicate(
            (w) =>
                w is StarBridgeActionButton &&
                w.controlKey == const Key('roles-save'),
          ),
        );
        expect(button.onActivate, isNull);
        port.pendingSave!.complete(
          const CommunityProfileOutcome('rejected', error: 'conflict'),
        );
        await settleCommunityImages(t);
        expect(find.text('Retained'), findsWidgets);
        expect(
          t
              .state<CommunityRolesDialogState>(
                find.byType(CommunityRolesDialog),
              )
              .model
              .dirty,
          true,
        );
        expect(port.writes, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'management late answer after account loss cannot announce success $suite',
      (t) async {
        final port = Management()
          ..hold = Completer<CommunityAdmissionOutcome>();
        addTearDown(port.changes.close);
        var callbacks = 0;
        await mount(
          t,
          CommunityManagementDialog(
            port: port,
            targetRef: target,
            name: 'Private workspace',
            embedded: true,
            onMembersChanged: () => callbacks++,
          ),
          suite,
          width: 850,
        );
        await action(t, const Key('management-approve-$applicant'), 'pointer');
        await action(
          t,
          const Key('management-confirm-accept'),
          'keyboard',
          settle: false,
        );
        expect(port.intents.length, 1);
        port.changes.add(null);
        await t.pump();
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        port.hold!.complete(const CommunityAdmissionOutcome('accepted'));
        await settleCommunityImages(t);
        expect(callbacks, 0);
        expect(port.intents.length, 1);
        expect(find.text('Callsign · Applicant'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'roles live motion setting keeps native controllers and lands confirmation $suite',
      (t) async {
        final port = Roles();
        addTearDown(port.events.close);
        final live = await mount(
          t,
          CommunityRolesDialog(port: port, targetRef: target, embedded: true),
          suite,
          width: 900,
        );
        await action(t, const Key('role-custom_navigation'), 'pointer');
        await t.enterText(find.byKey(const Key('role-name')), 'Live draft');
        await t.pump();
        final state = t.state<CommunityRolesDialogState>(
              find.byType(CommunityRolesDialog),
            ),
            editor = t
                .widget<TextField>(find.byKey(const Key('role-name')))
                .controller;
        await action(t, const Key('roles-delete'), 'pointer', settle: false);
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final route =
            ModalRoute.of(
                  t.element(find.byKey(const Key('roles-confirm-accept'))),
                )!
                as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        await action(t, const Key('roles-confirm-cancel'), 'keyboard');
        expect(state.name.text, 'Live draft');
        expect(
          t.widget<TextField>(find.byKey(const Key('role-name'))).controller,
          same(editor),
        );
        expect(port.writes, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'unknown management explicit warning retry and read failure keeps acknowledged outcome $suite',
      (t) async {
        final port = Management()
          ..outcome = const CommunityAdmissionOutcome(
            'unknown',
            error: 'outcomeUnknown',
          );
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityManagementDialog(
            port: port,
            targetRef: target,
            name: 'Organization A',
            embedded: true,
          ),
          suite,
          width: 850,
        );
        await action(t, const Key('management-decline-$applicant'), 'pointer');
        await action(t, const Key('management-confirm-accept'), 'keyboard');
        expect(port.intents.length, 1);
        await action(t, const Key('management-decline-$applicant'), 'pointer');
        expect(find.textContaining('重复'), findsWidgets);
        expect(port.intents.length, 1);
        await action(t, const Key('management-confirm-cancel'), 'keyboard');
        expect(port.intents.length, 1);
        await action(t, const Key('management-decline-$applicant'), 'pointer');
        port.outcome = const CommunityAdmissionOutcome('accepted');
        port.failRead = true;
        await action(t, const Key('management-confirm-accept'), 'keyboard');
        expect(port.intents.length, 2);
        expect(port.intents.last.confirmUncertainRetry, true);
        final state = t.state<CommunityManagementDialogState>(
          find.byType(CommunityManagementDialog),
        );
        expect(state.model.outcome!.status, 'accepted');
        expect(state.model.error, 'unavailable');
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('settings role editor actual text pixels review $suite', (
      t,
    ) async {
      final port = Roles(), capture = GlobalKey();
      addTearDown(port.events.close);
      await mount(
        t,
        CommunityRolesDialog(port: port, targetRef: target, embedded: true),
        suite,
        width: 1000,
        capture: capture,
      );
      await action(t, const Key('role-custom_navigation'), 'pointer');
      final rect = t.getRect(find.text('身份组与权限').first);
      final nameLabel = t.getRect(find.text('身份组名称'));
      final editorViewport = t.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('role-name')),
              matching: find.byType(ListView),
            )
            .first,
      );
      expect(nameLabel.top, greaterThanOrEqualTo(editorViewport.top));
      await t.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(),
            directory = Directory('build/reviews/interaction-batch3am');
        directory.createSync(recursive: true);
        final bytes = await image.toByteData(format: ImageByteFormat.png),
            raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        var foreground = 0;
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
            final i = (y * image.width + x) * 4;
            if (raw[i] > 100 && raw[i + 1] > 100 && raw[i + 2] > 100) {
              foreground++;
            }
          }
        }
        expect(foreground, greaterThan(20));
        File('${directory.path}/${suite.name}-roles.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox());
    });
  }
}
