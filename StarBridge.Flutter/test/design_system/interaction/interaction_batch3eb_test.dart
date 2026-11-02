import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3al_test.dart'
    show Role, Write, Exit, owner, workspace, target, member, edit;
import 'interaction_batch3ae_test.dart' show mount;
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

// Actual keyboard regressions. Focus nodes are public observation targets:
// only Tab, Arrow and Enter change focus/selection or execute a command.
Future<void> _frames(WidgetTester t, {int count = 3}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

FocusNode _publicFocus(WidgetTester t, Finder target) {
  final widget = t.widget(target);
  if (widget is ButtonStyleButton && widget.focusNode != null) {
    return widget.focusNode!;
  }
  if (widget is SuitePressable && widget.focusNode != null) {
    return widget.focusNode!;
  }
  final detectors = find.descendant(
    of: target,
    matching: find.byType(FocusableActionDetector),
  );
  expect(detectors, findsOneWidget);
  final focus = t.widget<FocusableActionDetector>(detectors).focusNode;
  expect(
    focus,
    isNotNull,
    reason: 'Use the public action detector owner, never Focus.of a native ListTile/InkWell.',
  );
  return focus!;
}

Future<void> _tabTo(WidgetTester t, Finder target, FocusNode node) async {
  await t.ensureVisible(target);
  await t.pump();
  for (var i = 0; i < 80 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
  }
  expect(
    FocusManager.instance.primaryFocus,
    same(node),
    reason: 'The actual Tab sequence must reach the public target without requestFocus or callback invocation.',
  );
}

StarBridgeActionButton _save(WidgetTester t) =>
    t.widget<StarBridgeActionButton>(
      find.byWidgetPredicate(
        (w) =>
            w is StarBridgeActionButton &&
            w.controlKey == const Key('member-role-save'),
      ),
    );

StarBridgeActionRow _choice(WidgetTester t) => t.widget<StarBridgeActionRow>(
  find.byWidgetPredicate(
    (w) =>
        w is StarBridgeActionRow &&
        w.controlKey == const Key('assign-option-custom_navigation'),
  ),
);

FocusNode _exitRowOwner(WidgetTester t, Finder target) {
  final tile = find.descendant(of: target, matching: find.byType(ListTile));
  expect(tile, findsOneWidget);
  final ancestors = find
      .ancestor(of: tile, matching: find.byType(FocusableActionDetector))
      .evaluate()
      .toSet();
  final owners = find
      .descendant(of: target, matching: find.byType(FocusableActionDetector))
      .evaluate()
      .where(ancestors.contains)
      .toList();
  expect(
    owners,
    hasLength(1),
    reason: 'Only the row detector contains the ListTile; avatar actions are independent descendants.',
  );
  final node = (owners.single.widget as FocusableActionDetector).focusNode;
  expect(node, isNotNull);
  return node!;
}

FocusNode _exitButtonOwner(WidgetTester t, Finder target) {
  final widget = t.widget(target);
  if (widget is ButtonStyleButton && widget.focusNode != null) {
    return widget.focusNode!;
  }
  final detectors = find.descendant(
    of: target,
    matching: find.byType(FocusableActionDetector),
  );
  expect(detectors, findsOneWidget);
  final node = t.widget<FocusableActionDetector>(detectors).focusNode;
  expect(node, isNotNull);
  return node!;
}

Future<void> _exitEnter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await settleCommunityImages(t);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'Standard real Tab Arrow menu role selection save confirmation and authoritative readback',
    (t) async {
      final port = Role();
      owner(port);
      try {
        await mount(t, workspace(port), InteractionSuite.standard, width: 800);
        final anchorKey = ValueKey('member-actions-$member');
        final anchor = find.byKey(anchorKey);
        final icon = t.widget<StarBridgeIconAction>(
          find.byWidgetPredicate(
            (w) => w is StarBridgeIconAction && w.controlKey == anchorKey,
          ),
        );
        expect(icon.focusNode, isNotNull);
        await _tabTo(t, anchor, icon.focusNode!);
        expect(port.writes, 0);
        expect(find.byType(CommunityMemberRoleDialog), findsNothing);

        // Open and navigate the actual menu with Arrow input. Do not call
        // MenuController.open or request the assignment row's focus directly.
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _frames(t, count: 2);
        final assignment = find.byKey(
          ValueKey<Object>('assign-member-$member'),
        );
        expect(assignment, findsOneWidget);
        final menuItem = t.widget<MenuItemButton>(assignment);
        expect(menuItem.focusNode, isNotNull);
        for (var i = 0; i < 4 && !menuItem.focusNode!.hasPrimaryFocus; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
          await t.pump();
        }
        expect(FocusManager.instance.primaryFocus, same(menuItem.focusNode));
        expect(port.writes, 0);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(t);
        final dialog = find.byType(CommunityMemberRoleDialog);
        expect(dialog, findsOneWidget);
        final route =
            ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute;
        expect(route.instant, isTrue);
        expect(port.reads, 1);
        expect(port.writes, 0);
        expect(port.calls, isEmpty);

        // The public port is still the confirmed value. Selection and save
        // readiness are observed on the real row and action, not private State.
        expect(port.currentRole, '');
        expect(_choice(t).semanticSelected, isFalse);
        expect(_save(t).onActivate, isNull);

        final option = find.byKey(const Key('assign-option-custom_navigation'));
        final optionFocus = _publicFocus(t, option);
        await _tabTo(t, option, optionFocus);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(t, count: 2);
        expect(
          port.currentRole,
          '',
          reason:
              'Keyboard selection is an unsaved choice, not a server write.',
        );
        expect(_choice(t).semanticSelected, isTrue);
        expect(
          _save(t).onActivate,
          isNotNull,
          reason:
              'The real save action must become enabled before pressing it.',
        );
        expect(port.writes, 0);
        expect(port.reads, 1);

        final save = find.byKey(const Key('member-role-save'));
        await _tabTo(t, save, _publicFocus(t, save));
        expect(_choice(t).semanticSelected, isTrue);
        expect(_save(t).onActivate, isNotNull);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(t, count: 2);
        final confirm = find.byKey(const Key('member-role-confirm-accept'));
        expect(
          confirm,
          findsOneWidget,
          reason: 'This is the original missing finder, after selection/save checkpoints and real input.',
        );
        expect(port.writes, 0);
        expect(_choice(t).semanticSelected, isTrue);
        expect(port.currentRole, '');
        final confirmRoute =
            ModalRoute.of(t.element(confirm))! as StarBridgeDialogRoute;
        expect(confirmRoute.instant, isTrue);
        await _tabTo(t, confirm, _publicFocus(t, confirm));
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(t, count: 6);

        // Preserve all original write, identity, input-source and readback
        // assertions rather than ending at the now-found confirmation.
        expect(port.currentRole, 'custom_navigation');
        expect(port.reads, 2);
        expect(port.writes, 1);
        final Write call = port.calls.single;
        expect(call.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(call.$2, edit);
        expect(call.$3, InteractionSource.keyboard);
        expect(port.confirmations, [false]);
        expect(find.byType(CommunityMemberRoleDialog), findsNothing);
        expect(find.byType(CommunityWorkspaceView), findsOneWidget);
        expect(
          captureStarBridgeActivationSource()(),
          InteractionSource.programmatic,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await _frames(t, count: 2);
        await t.runAsync(() async {
          await port.changes.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Standard actual Tab selects successor back and explicit exit without premature write',
    (t) async {
      final port = Exit(), directory = WorkspaceTestPort();
      owner(directory);
      try {
        await mount(
          t,
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-exit'),
              onActivate: (_) => showStarBridgeDialog<bool>(
                context,
                barrierDismissible: false,
                builder: (_) => CommunityOwnershipExitDialog(
                  port: port,
                  workspacePort: directory,
                  targetRef: target,
                ),
              ),
              child: const Text('Open exit'),
            ),
          ),
          InteractionSuite.standard,
        );
        final open = find.byKey(const Key('open-exit'));
        await _tabTo(t, open, _publicFocus(t, open));
        await _exitEnter(t);
        final route =
            ModalRoute.of(t.element(find.byType(CommunityOwnershipExitDialog)))!
                as StarBridgeDialogRoute;
        expect(route.instant, isTrue);
        final candidate = find.byKey(const Key('successor-action-$member'));
        expect(port.writes, 0);
        expect(find.byKey(const Key('ownership-exit-back')), findsNothing);
        await _tabTo(t, candidate, _exitRowOwner(t, candidate));
        await _exitEnter(t);
        expect(find.byKey(const Key('ownership-exit-back')), findsOneWidget);
        expect(find.byKey(const Key('ownership-exit-confirm')), findsOneWidget);
        expect(port.writes, 0);
        expect(port.reads, 1);
        final back = find.byKey(const Key('ownership-exit-back'));
        await _tabTo(t, back, _exitButtonOwner(t, back));
        await _exitEnter(t);
        expect(find.byKey(const Key('ownership-exit-back')), findsNothing);
        expect(port.writes, 0);
        await _tabTo(t, candidate, _exitRowOwner(t, candidate));
        await _exitEnter(t);
        expect(port.writes, 0);
        final confirm = find.byKey(const Key('ownership-exit-confirm'));
        await _tabTo(t, confirm, _exitButtonOwner(t, confirm));
        await _exitEnter(t);
        expect(port.writes, 1);
        expect(port.calls.single.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(port.calls.single.$2, edit);
        expect(port.calls.single.$3, InteractionSource.keyboard);
        expect(port.confirmations, [false]);
        expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
        expect(
          captureStarBridgeActivationSource()(),
          InteractionSource.programmatic,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await settleCommunityImages(t);
        await t.runAsync(() async {
          await port.changes.close();
          await directory.changes.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
