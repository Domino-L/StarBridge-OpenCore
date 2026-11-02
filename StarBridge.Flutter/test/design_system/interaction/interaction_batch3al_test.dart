import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_disband_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_disband_port.dart';

import '../../features/communities/community_member_role_test.dart'
    show MemberRoleFake;
import '../../features/communities/community_member_removal_test.dart'
    show RemovalFake;
import '../../features/communities/community_ownership_transfer_test.dart'
    show TransferFake;
import '../../features/communities/community_ownership_exit_test.dart'
    show ExitFake;
import '../../features/communities/community_disband_test.dart'
    show DisbandFake;
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ak_test.dart' as shared show action;

Future<void> action(
  WidgetTester t,
  Key key,
  String source, {
  bool settle = true,
}) async {
  final rows = find.byWidgetPredicate(
    (w) => w is StarBridgeActionRow && w.controlKey == key,
  );
  if (source == 'keyboard' && rows.evaluate().isNotEmpty) {
    final row = find
        .descendant(of: find.byKey(key), matching: find.byType(ListTile))
        .first;
    await t.ensureVisible(row);
    final ancestors = find
        .ancestor(of: row, matching: find.byType(FocusableActionDetector))
        .evaluate()
        .toSet();
    final owners = find
        .descendant(
          of: find.byKey(key),
          matching: find.byType(FocusableActionDetector),
        )
        .evaluate()
        .where(ancestors.contains)
        .toList();
    expect(owners, hasLength(1));
    final focus = (owners.single.widget as FocusableActionDetector).focusNode;
    expect(focus, isNotNull);
    expect(focus!.canRequestFocus, isTrue);
    focus.requestFocus();
    await t.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
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

const target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const member = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const edit = 'cccccccccccccccccccccccccccccccc';
typedef Write = (String, String, InteractionSource);

class Role extends MemberRoleFake {
  final calls = <Write>[];
  @override
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String id,
    String ref,
    String key, {
    bool confirmUncertainRetry = false,
  }) {
    calls.add((id, ref, currentStarBridgeActivationSource));
    return super.saveMemberRole(
      id,
      ref,
      key,
      confirmUncertainRetry: confirmUncertainRetry,
    );
  }
}

class Removal extends RemovalFake {
  final calls = <Write>[];
  @override
  Future<CommunityMemberRemovalOutcome> removeMember(
    String id,
    String ref, {
    bool confirmUncertainRetry = false,
  }) {
    calls.add((id, ref, currentStarBridgeActivationSource));
    return super.removeMember(
      id,
      ref,
      confirmUncertainRetry: confirmUncertainRetry,
    );
  }
}

class Transfer extends TransferFake {
  final calls = <Write>[];
  @override
  Future<CommunityOwnershipTransferOutcome> transferOwnership(
    String id,
    String ref, {
    bool confirmUncertainRetry = false,
  }) {
    calls.add((id, ref, currentStarBridgeActivationSource));
    return super.transferOwnership(
      id,
      ref,
      confirmUncertainRetry: confirmUncertainRetry,
    );
  }
}

class Exit extends ExitFake {
  final calls = <Write>[];
  @override
  Future<CommunityOwnershipTransferOutcome> leaveWithSuccessor(
    String id,
    String ref, {
    bool confirmUncertainRetry = false,
  }) {
    // No tester API inside this asynchronous production callback.
    writes++;
    calls.add((id, ref, currentStarBridgeActivationSource));
    confirmations.add(confirmUncertainRetry);
    return pendingWrite?.future ?? Future.value(outcome);
  }
}

class Disband extends DisbandFake {
  InteractionSource? source;
  @override
  Future<CommunityDisbandOutcome> disband(
    String targetRef,
    String confirmationRef,
    String password,
  ) {
    source = currentStarBridgeActivationSource;
    return super.disband(targetRef, confirmationRef, password);
  }
}

void owner(WorkspaceTestPort port) {
  port.reader = (ref, query, offset) async {
    final p = workspacePayload(target: ref, query: query);
    (p['access'] as Map)['isOwner'] = true;
    ((p['members'] as List).single as Map)['isSelf'] = false;
    return CommunityWorkspace.parse(p);
  };
}

Widget workspace(CommunityWorkspacePort port) => CommunityWorkspaceView(
  port: port,
  targetRef: target,
  organizationKey: 'same',
);
Future<void> openMember(WidgetTester t, String operation, String source) async {
  await action(t, const ValueKey('member-actions-$member'), source);
  final id = operation == 'role'
      ? 'assign-member-$member'
      : operation == 'remove'
      ? 'remove-member-$member'
      : 'transfer-owner-$member';
  await action(t, ValueKey<Object>(id), source);
}

Type typeOf(String operation) => operation == 'role'
    ? CommunityMemberRoleDialog
    : operation == 'remove'
    ? CommunityMemberRemovalDialog
    : CommunityOwnershipTransferDialog;
Future<void> standalone(
  WidgetTester t,
  Widget child,
  InteractionSuite suite,
  String source, {
  GlobalKey? capture,
}) async {
  await mount(
    t,
    Builder(
      builder: (context) => StarBridgeActionButton(
        controlKey: const Key('open'),
        onActivate: (_) => showStarBridgeDialog<bool>(
          context,
          barrierDismissible: false,
          builder: (_) => child,
        ),
        child: const Text('Open'),
      ),
    ),
    suite,
    capture: capture,
  );
  await action(t, const Key('open'), source);
}

Future<void> confirmRole(WidgetTester t, String source) async {
  await action(t, const Key('assign-option-custom_navigation'), source);
  await action(t, const Key('member-role-save'), source);
  expect(find.byKey(const Key('member-role-confirm-accept')), findsOneWidget);
  await action(t, const Key('member-role-confirm-accept'), source);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'workspace read authorization loss retires member confirmation without broadcast $suite',
      (t) async {
        final port = Role();
        owner(port);
        addTearDown(port.changes.close);
        await mount(t, workspace(port), suite, width: 800);
        await openMember(t, 'role', 'keyboard');
        await action(
          t,
          const Key('assign-option-custom_navigation'),
          'keyboard',
        );
        await action(t, const Key('member-role-save'), 'keyboard');
        port.reader = (_, _, _) async =>
            throw const CommunityFailure('notAllowed');
        await t
            .state<CommunityWorkspaceViewState>(
              find.byType(CommunityWorkspaceView),
            )
            .model
            .load(silent: true);
        await settleCommunityImages(t);
        expect(find.byType(CommunityMemberRoleDialog), findsNothing);
        expect(
          find.byKey(const Key('member-role-confirm-accept')),
          findsNothing,
        );
        expect(port.writes, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final operation in ['role', 'remove', 'transfer']) {
        testWidgets(
          'member actual workspace menu confirm readback $suite $source $operation',
          (t) async {
            final semantics = t.ensureSemantics();
            final dynamic port = operation == 'role'
                ? Role()
                : operation == 'remove'
                ? Removal()
                : Transfer();
            owner(port);
            addTearDown(port.changes.close as Future<void> Function());
            try {
              await mount(t, workspace(port), suite, width: 800);
              await openMember(t, operation, source);
              final route =
                  ModalRoute.of(t.element(find.byType(typeOf(operation))))!
                      as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              expect(port.writes, 0);
              if (operation == 'role') {
                await confirmRole(t, source);
                expect(port.currentRole, 'custom_navigation');
                expect(port.reads, 2);
              } else {
                await action(t, Key('member-$operation-confirm'), source);
              }
              expect(port.writes, 1);
              final call = (port.calls as List<Write>).single;
              expect(call.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
              expect(call.$2, edit);
              expect(
                call.$3,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(find.byType(typeOf(operation)), findsNothing);
              expect(find.byType(CommunityWorkspaceView), findsOneWidget);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        'exit candidate is readonly and original explicit writer $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              port = Exit(),
              directory = WorkspaceTestPort();
          owner(directory);
          addTearDown(port.changes.close);
          addTearDown(directory.changes.close);
          try {
            await standalone(
              t,
              CommunityOwnershipExitDialog(
                port: port,
                workspacePort: directory,
                targetRef: target,
              ),
              suite,
              source,
            );
            await action(t, const Key('successor-action-$member'), source);
            expect(port.writes, 0);
            await action(t, const Key('ownership-exit-back'), source);
            expect(port.writes, 0);
            await action(t, const Key('successor-action-$member'), source);
            await action(t, const Key('ownership-exit-confirm'), source);
            expect(port.writes, 1);
            expect(port.calls.single.$2, edit);
            expect(port.calls.single.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(
              port.calls.single.$3,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'disband retains original credential explicit submission $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Disband();
          addTearDown(port.changes.close);
          try {
            await standalone(
              t,
              CommunityDisbandDialog(port: port, targetRef: target),
              suite,
              source,
            );
            expect(port.writes, 0);
            await t.enterText(
              find.byKey(const Key('community-disband-password')),
              ' fixture credential ',
            );
            await t.pump();
            await action(t, const Key('community-disband-confirm'), source);
            expect(port.writes, 1);
            expect(port.sentPassword, ' fixture credential ');
            expect(
              port.source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(find.byType(CommunityDisbandDialog), findsNothing);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final operation in ['role', 'remove', 'transfer']) {
      testWidgets(
        'workspace disposal clears owned member and secondary route $suite $operation',
        (t) async {
          final dynamic port = operation == 'role'
              ? Role()
              : operation == 'remove'
              ? Removal()
              : Transfer();
          owner(port);
          addTearDown(port.changes.close as Future<void> Function());
          final live = await mount(t, workspace(port), suite, width: 800);
          await openMember(t, operation, 'keyboard');
          if (operation == 'role') {
            await action(
              t,
              const Key('assign-option-custom_navigation'),
              'keyboard',
            );
            await action(t, const Key('member-role-save'), 'keyboard');
          }
          live.change(() => live.visible = false);
          await settleCommunityImages(t);
          expect(find.byType(typeOf(operation)), findsNothing);
          expect(
            find.byKey(const Key('member-role-confirm-accept')),
            findsNothing,
          );
          expect(port.writes, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'role cancel leaves editable choice and failure requires reread $suite',
      (t) async {
        final port = Role()
          ..outcome = const CommunityMemberRoleOutcome(
            'rejected',
            error: 'conflict',
          );
        addTearDown(port.changes.close);
        await standalone(
          t,
          CommunityMemberRoleDialog(
            port: port,
            targetRef: target,
            memberRef: member,
          ),
          suite,
          'pointer',
        );
        await action(
          t,
          const Key('assign-option-custom_navigation'),
          'pointer',
        );
        await action(t, const Key('member-role-close'), 'pointer');
        await action(t, const Key('member-role-confirm-cancel'), 'keyboard');
        expect(port.writes, 0);
        await action(t, const Key('member-role-save'), 'pointer');
        await action(t, const Key('member-role-confirm-accept'), 'keyboard');
        expect(port.writes, 1);
        expect(find.byType(CommunityMemberRoleDialog), findsOneWidget);
        expect(port.calls.single.$3, InteractionSource.keyboard);
        await action(t, const Key('member-role-reload'), 'pointer');
        await action(t, const Key('member-role-confirm-cancel'), 'keyboard');
        expect(port.reads, 1);
        expect(port.writes, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'pending removal disables all writes and identity drops late result $suite',
      (t) async {
        final port = Removal()
          ..pendingWrite = Completer<CommunityMemberRemovalOutcome>();
        owner(port);
        addTearDown(port.changes.close);
        await mount(t, workspace(port), suite, width: 800);
        await openMember(t, 'remove', 'pointer');
        await action(
          t,
          const Key('member-remove-confirm'),
          'pointer',
          settle: false,
        );
        expect(port.writes, 1);
        final current = t.widget<StarBridgeActionButton>(
          find.byWidgetPredicate(
            (w) =>
                w is StarBridgeActionButton &&
                w.controlKey == const Key('member-remove-confirm'),
          ),
        );
        expect(current.onActivate, isNull);
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(find.byType(CommunityMemberRemovalDialog), findsNothing);
        port.pendingWrite!.complete(
          const CommunityMemberRemovalOutcome('accepted'),
        );
        await settleCommunityImages(t);
        expect(port.writes, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'role confirmation follows live reduce and palette before final write $suite',
      (t) async {
        final port = Role();
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open'),
              onActivate: (_) => showStarBridgeDialog<bool>(
                context,
                barrierDismissible: false,
                builder: (_) => CommunityMemberRoleDialog(
                  port: port,
                  targetRef: target,
                  memberRef: member,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
          suite,
        );
        await action(t, const Key('open'), 'keyboard');
        await action(
          t,
          const Key('assign-option-custom_navigation'),
          'pointer',
        );
        await action(
          t,
          const Key('member-role-save'),
          'pointer',
          settle: false,
        );
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final route =
            ModalRoute.of(
                  t.element(
                    find.byKey(const Key('member-role-confirm-accept')),
                  ),
                )!
                as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        expect(port.writes, 0);
        await action(t, const Key('member-role-confirm-cancel'), 'keyboard');
        expect(port.writes, 0);
        expect(find.byType(CommunityMemberRoleDialog), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'disband native editor persists style change but clears identity loss $suite',
      (t) async {
        final port = Disband();
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityDisbandDialog(port: port, targetRef: target),
          suite,
        );
        final field = find.byKey(const Key('community-disband-password'));
        await t.enterText(field, 'fixture');
        await t.pump();
        final editor = t.widget<TextField>(field).controller!;
        live.change(() {
          live.reduce = true;
          live.light = true;
          live.suite = suite == InteractionSuite.glow
              ? InteractionSuite.scan
              : InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(t.widget<TextField>(field).controller, same(editor));
        expect(editor.text, 'fixture');
        expect(port.writes, 0);
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(editor.text, isEmpty);
        expect(field, findsNothing);
        expect(port.writes, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'unknown exit requires reread and explicit retry without going back $suite',
      (t) async {
        final port = Exit()
          ..outcome = const CommunityOwnershipTransferOutcome(
            'unknown',
            error: 'outcomeUnknown',
          );
        final directory = WorkspaceTestPort();
        owner(directory);
        addTearDown(port.changes.close);
        addTearDown(directory.changes.close);
        await standalone(
          t,
          CommunityOwnershipExitDialog(
            port: port,
            workspacePort: directory,
            targetRef: target,
          ),
          suite,
          'pointer',
        );
        await action(t, const Key('successor-action-$member'), 'pointer');
        await action(t, const Key('ownership-exit-confirm'), 'pointer');
        expect(port.writes, 1);
        expect(find.byKey(const Key('ownership-exit-back')), findsNothing);
        await action(t, const Key('ownership-exit-reload'), 'keyboard');
        expect(port.writes, 1);
        port.outcome = const CommunityOwnershipTransferOutcome('accepted');
        await action(t, const Key('ownership-exit-confirm'), 'keyboard');
        expect(port.writes, 2);
        expect(port.confirmations, [false, true]);
        expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'unknown disband clears credential and has no automatic retry $suite',
      (t) async {
        final port = Disband()
          ..outcome = const CommunityDisbandOutcome(
            'unknown',
            error: 'outcomeUnknown',
          );
        addTearDown(port.changes.close);
        await standalone(
          t,
          CommunityDisbandDialog(port: port, targetRef: target),
          suite,
          'pointer',
        );
        await t.enterText(
          find.byKey(const Key('community-disband-password')),
          'fixture',
        );
        await t.pump();
        await action(t, const Key('community-disband-confirm'), 'keyboard');
        expect(port.writes, 1);
        expect(
          find.byKey(const Key('community-disband-password')),
          findsNothing,
        );
        expect(find.byKey(const Key('community-disband-reload')), findsNothing);
        expect(find.byType(CommunityDisbandDialog), findsOneWidget);
        await action(t, const Key('community-disband-cancel'), 'keyboard');
        expect(port.writes, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('member confirmation review $suite', (t) async {
      final capture = GlobalKey(), port = Transfer();
      addTearDown(port.changes.close);
      await standalone(
        t,
        CommunityOwnershipTransferDialog(
          port: port,
          targetRef: target,
          memberRef: member,
          organizationName: '组织确认',
        ),
        suite,
        'pointer',
        capture: capture,
      );
      expect(find.textContaining('副负责人'), findsOneWidget);
      final bodyRect = t.getRect(find.textContaining('副负责人'));
      await t.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        var foreground = 0;
        for (var y = bodyRect.top.ceil(); y < bodyRect.bottom.floor(); y++) {
          for (var x = bodyRect.left.ceil(); x < bodyRect.right.floor(); x++) {
            final i = (y * image.width + x) * 4;
            if (raw[i] > 100 &&
                raw[i + 1] > 100 &&
                raw[i + 2] > 100 &&
                raw[i + 3] > 240) {
              foreground++;
            }
          }
        }
        expect(foreground, greaterThan(20));
        final path = 'build/reviews/interaction-batch3al';
        Directory(path).createSync(recursive: true);
        File('$path/${suite.name}-member-confirm.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox());
    });
  }
}
