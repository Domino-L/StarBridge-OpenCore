import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3ap_flows_test.dart'
    show Avatar, avatar, openAvatar, actorTarget;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

class ReadAvatar extends Avatar {
  final pendingReads = <Completer<FriendRow?>>[];
  @override
  Future<FriendRow?> social(UserTarget target) {
    targets.add(target);
    final pending = Completer<FriendRow?>();
    pendingReads.add(pending);
    return pending.future;
  }

  Future<void> finish() async {
    for (final pending in pendingReads) {
      if (!pending.isCompleted) pending.complete(null);
    }
    if (commandReply case final pending? when !pending.isCompleted) {
      pending.complete(const FriendCommandResult('accepted'));
    }
    await changes.close();
  }
}

class AvatarProbe {
  AvatarProbe(this.suite);
  InteractionSuite suite;
  final first = ReadAvatar(), replacement = ReadAvatar();
  late ReadAvatar? port = first;
  bool reduce = false, light = false, shown = true, self = false, social = true;
  UserTarget? target = actorTarget;
  int profiles = 0;
  late StateSetter update;
  final navigation = UserPageNavigation();
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        UserInteractionScope(
          port: port,
          navigation: navigation,
          messagePage: null,
          child: Align(
            alignment: Alignment.topLeft,
            child: shown
                ? UserAvatarMenu(
                    name: 'Original peer',
                    target: target,
                    isSelf: self,
                    includeSocialActions: social,
                    onViewProfile: () => profiles++,
                    child: const SizedBox(width: 48, height: 48),
                  )
                : const SizedBox(),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await first.finish();
    await replacement.finish();
    await t.pump();
  }
}

Future<void> avatarFrames(WidgetTester t, {bool settle = false}) async {
  await t.pump();
  await t.pump();
  if (settle) {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> actualOpenAvatar(WidgetTester t, String input) async {
  final target = find.byKey(const Key('user-avatar-menu-anchor'));
  expect(target, findsOneWidget);
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.flagsCollection.isButton &&
          d.label == '头像菜单' &&
          d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final row = t.widget<StarBridgeActionRow>(
      find.ancestor(of: target, matching: find.byType(StarBridgeActionRow)),
    );
    final focus = row.focusNode!;
    FocusScope.of(t.element(target)).unfocus();
    await avatarFrames(t);
    for (var i = 0; !focus.hasPrimaryFocus && i < 20; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await avatarFrames(t);
    }
    expect(
      focus.hasPrimaryFocus,
      isTrue,
      reason: '$focus\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final pointer = await t.startGesture(
      t.getCenter(target),
      kind: ui.PointerDeviceKind.touch,
    );
    await pointer.up();
  }
  await avatarFrames(t);
}

Future<void> closeAvatar(WidgetTester t) async {
  final controller = t
      .widget<RawMenuAnchor>(find.byType(RawMenuAnchor))
      .controller;
  controller.close();
  await avatarFrames(t, settle: true);
  expect(controller.isOpen, isFalse);
}

void expectAvatarWaiting(
  WidgetTester t,
  InteractionSource source, {
  required InteractionSuite suite,
  bool reduce = false,
}) {
  final finder = find.byType(SocialReadActivity);
  expect(finder, findsOneWidget);
  final waiting = t.widget<SocialReadActivity>(finder);
  expect(waiting.source, source);
  expect(waiting.opening, isFalse);
  expect(waiting.height, 4);
  expect(
    t.element(finder).findAncestorWidgetOfExactType<Padding>()!.padding,
    const EdgeInsets.only(bottom: 8),
  );
  final indicator = t.widget<LinearProgressIndicator>(
    find.descendant(of: finder, matching: find.byType(LinearProgressIndicator)),
  );
  final animated =
      source == InteractionSource.pointer &&
      !reduce &&
      (suite == InteractionSuite.standard || suite == InteractionSuite.glow);
  expect(indicator.value, animated ? null : .5);
  expect(indicator.minHeight, 4);
}

Future<void> readerAvatarAction(WidgetTester t, String label) async {
  final nodes = exposedNodes(t).where((n) {
    final d = n.getSemanticsData();
    return d.flagsCollection.isButton &&
        d.label == label &&
        d.hasAction(ui.SemanticsAction.tap);
  }).toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    ui.SemanticsAction.tap,
  );
  await avatarFrames(t);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3fn reader menu opening carries actual source to social wait', (
    t,
  ) async {
    size(t, const Size(900, 700));
    final semantics = t.ensureSemantics();
    final port = Avatar()..held = Completer<FriendRow?>();
    try {
      await t.pumpWidget(scopedApp(avatar(port), InteractionSuite.scan));
      await t.pump();
      await openAvatar(t, 'reader', settle: false);
      expect(port.targets, hasLength(1));
      final waiting = find.byType(SocialReadActivity);
      expect(waiting, findsOneWidget);
      final indicator = t.widget<SocialReadActivity>(waiting);
      expect(indicator.source, InteractionSource.keyboard);
      expect(indicator.opening, isFalse);
      expect(port.commands, isEmpty);
    } finally {
      await t.pumpWidget(const SizedBox());
      port.held!.complete(null);
      await t.pump();
      await port.changes.close();
      semantics.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fn $suite $input real open frozen phase and busy no extra read',
        (t) async {
          size(t, const Size(900, 700));
          final semantics = t.ensureSemantics();
          final p = AvatarProbe(suite);
          try {
            await t.pumpWidget(p.app());
            await avatarFrames(t);
            await actualOpenAvatar(t, input);
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(p.first.targets, [actorTarget]);
            expectAvatarWaiting(t, source, suite: suite);
            final oldKey = t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .key;
            p.update(() {
              p.reduce = true;
              p.light = true;
              p.suite = suite == InteractionSuite.rail
                  ? InteractionSuite.glow
                  : InteractionSuite.rail;
            });
            await avatarFrames(t);
            expectAvatarWaiting(t, source, suite: p.suite, reduce: true);
            expect(
              t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).key,
              oldKey,
            );
            expect(p.first.targets.length, 1);
            await closeAvatar(t);
            expect(
              p.first.pendingReads.single.isCompleted,
              isFalse,
              reason: 'Ordinary close never cancels the owner read',
            );
            p.update(() {
              p.reduce = false;
              p.suite = suite;
            });
            await avatarFrames(t);
            final nextInput = input == 'pointer' ? 'reader' : 'pointer';
            final nextSource = nextInput == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            await actualOpenAvatar(t, nextInput);
            expect(p.first.targets.length, 2);
            expectAvatarWaiting(t, nextSource, suite: suite);
            expect(
              t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).key,
              isNot(oldKey),
            );
            p.first.pendingReads.first.complete(p.first.row);
            await avatarFrames(t);
            expectAvatarWaiting(t, nextSource, suite: suite);
            expect(
              find.text('添加好友'),
              findsNothing,
              reason: 'First-phase result may not finish the newer read',
            );
            p.first.pendingReads.last.complete(p.first.row);
            await avatarFrames(t, settle: true);
            expect(find.byType(SocialReadActivity), findsNothing);
            p.first.commandReply = Completer<FriendCommandResult>();
            await readerAvatarAction(t, '添加好友');
            expect(p.first.commands, [
              ('send', 'c' * 32, InteractionSource.keyboard),
            ]);
            await avatarFrames(t, settle: true);
            await actualOpenAvatar(t, input);
            expect(
              p.first.targets.length,
              2,
              reason: 'Busy command rejects new social reads',
            );
            expect(find.byType(SocialReadActivity), findsNothing);
            expect(
              exposedNodes(t).where(
                (n) =>
                    n.getSemanticsData().label == '添加好友' &&
                    n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              ),
              isEmpty,
            );
            expect(p.first.commands.length, 1);
            p.first.commandReply!.complete(
              const FriendCommandResult('accepted'),
            );
            await avatarFrames(t);
            expect(p.first.commands.length, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.finish(t);
            semantics.dispose();
          }
        },
      );
    }

    for (final change in ['invalidation', 'target', 'port', 'unmount']) {
      testWidgets('3fn $suite stale $change never repaints or reopens', (
        t,
      ) async {
        size(t, const Size(900, 700));
        final semantics = t.ensureSemantics();
        final p = AvatarProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await avatarFrames(t);
          await actualOpenAvatar(t, 'reader');
          final pending = p.first.pendingReads.single;
          if (change == 'invalidation') {
            p.first.changes.add(null);
          } else {
            p.update(() {
              if (change == 'target') {
                p.target = const UserTarget(
                  'friend',
                  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
                );
              }
              if (change == 'port') p.port = p.replacement;
              if (change == 'unmount') p.shown = false;
            });
          }
          await avatarFrames(t, settle: true);
          pending.complete(p.first.row);
          await avatarFrames(t, settle: true);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(find.text('添加好友'), findsNothing);
          expect(p.profiles, 0);
          expect(p.first.commands, isEmpty);
          if (change != 'unmount') {
            await actualOpenAvatar(t, 'pointer');
            final active = change == 'port' ? p.replacement : p.first;
            expect(active.pendingReads.length, change == 'port' ? 1 : 2);
            expect(active.targets.last, same(p.target));
            expectAvatarWaiting(t, InteractionSource.pointer, suite: suite);
          }
          expect(t.takeException(), isNull);
        } finally {
          await p.finish(t);
          semantics.dispose();
        }
      });
    }

    testWidgets(
      '3fn $suite closed late read stays closed and reopen reads once',
      (t) async {
        size(t, const Size(900, 700));
        final semantics = t.ensureSemantics();
        final p = AvatarProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await avatarFrames(t);
          await actualOpenAvatar(t, 'pointer');
          await closeAvatar(t);
          p.first.pendingReads.single.complete(p.first.row);
          await avatarFrames(t, settle: true);
          expect(find.text('添加好友'), findsNothing);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(p.first.targets.length, 1);
          await actualOpenAvatar(t, 'keyboard');
          expect(p.first.targets.length, 2);
          expectAvatarWaiting(t, InteractionSource.keyboard, suite: suite);
          p.first.pendingReads.last.completeError(StateError('Read refused'));
          await avatarFrames(t, settle: true);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(find.text('添加好友'), findsNothing);
          await readerAvatarAction(t, '查看资料');
          expect(
            p.profiles,
            1,
            reason: 'Failed social read retains profile access',
          );
          expect(p.first.commands, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await p.finish(t);
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '3fn $suite self no-port no-target and excluded social admit no reads',
      (t) async {
        size(t, const Size(900, 700));
        final semantics = t.ensureSemantics();
        final p = AvatarProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await avatarFrames(t);
          for (final gate in ['self', 'no-port', 'no-target', 'no-social']) {
            p.update(() {
              p.self = gate == 'self';
              p.port = gate == 'no-port' ? null : p.first;
              p.target = gate == 'no-target' ? null : actorTarget;
              p.social = gate != 'no-social';
            });
            await avatarFrames(t);
            await actualOpenAvatar(t, 'reader');
            expect(p.first.targets, isEmpty, reason: gate);
            expect(find.byType(SocialReadActivity), findsNothing);
            expect(find.text('添加好友'), findsNothing);
            await closeAvatar(t);
          }
          expect(p.first.commands, isEmpty);
          expect(p.profiles, 0);
          expect(t.takeException(), isNull);
        } finally {
          await p.finish(t);
          semantics.dispose();
        }
      },
    );
  }
}
