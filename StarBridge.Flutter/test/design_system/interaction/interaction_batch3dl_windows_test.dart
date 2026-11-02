import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/app/social_windows/window_opening_source.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_read_source_argument.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';

import '../../app/social_windows/social_window_test.dart' show native, Port;
import '../../app/friends_window/friends_window_binding_test.dart' as friends;
import '../../app/friends_window/friends_window_app_test.dart' as roster;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3dl_test.dart' show waitData;
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;

void main() {
  setUpAll(loadFonts);
  for (final kind in ['friends', 'messages', 'notifications']) {
    for (final source in InteractionSource.values) {
      testWidgets(
        '$kind $source opening is frozen across preference pulse and recaptured after hide',
        (t) async {
          final channel = MethodChannel('starbridge/$kind-primary');
          final calls = <MethodCall>[];
          final messenger = t.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return c.method == 'show' ? true : null;
          });
          final preferences = InMemoryAppPreferences(),
              inbox = NotificationInboxController(null),
              port = Port();
          final friendPort = friends.Port();
          final friend = kind == 'friends'
              ? FriendsWindowBinding(
                  preferences: preferences,
                  create: (publish) => MenuFriendsSession(friendPort, publish),
                  openChat: (_, _) async {},
                  openMessages: (_) async {},
                  openProfile: (_) async {},
                )
              : null;
          final social = friend == null
              ? SocialWindowBinding(
                  kind: kind,
                  preferences: preferences,
                  messages: port,
                  inbox: inbox,
                  navigate: (_) async {},
                )
              : null;
          Future<bool> open() => friend?.open() ?? social!.open();
          Map latest() =>
              calls
                      .lastWhere(
                        (c) => c.method == 'show' || c.method == 'snapshot',
                      )
                      .arguments
                  as Map;
          await runStarBridgeActivation<bool>(source, open);
          await t.pump();
          expect(latest()['openingSource'], source.name);
          final opening = latest()['opening'],
              scope = (jsonDecode(latest()['view'] as String) as Map)['scope'];
          await preferences.setInteractionStyle(InteractionStyle.scan);
          await preferences.setMotionPreference(MotionPreference.reduce);
          await t.pump();
          expect(latest()['openingSource'], source.name);
          expect(latest()['opening'], opening);
          expect(
            (jsonDecode(latest()['view'] as String) as Map)['scope'],
            scope,
          );
          expect((latest()['presentation'] as Map)['reduceMotion'], isTrue);
          await native(channel.name, 'hidden', {'opening': opening});
          await runStarBridgeActivation<bool>(InteractionSource.keyboard, open);
          await t.pump();
          expect(latest()['openingSource'], 'keyboard');
          expect(latest()['opening'], (opening as int) + 1);
          friend?.dispose();
          social?.dispose();
          await t.pump();
          final count = calls.length;
          await preferences.setInteractionStyle(InteractionStyle.glow);
          await t.pump();
          expect(calls.length, count);
          preferences.dispose();
          inbox.dispose();
          await port.close();
          messenger.setMockMethodCallHandler(channel, null);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source actual friend-row outbound annotation survives auxiliary callback',
        (t) async {
          size(t, const Size(392, 750));
          const channel = MethodChannel('starbridge/friends-surface');
          final messenger = t.binding.defaultBinaryMessenger;
          final calls = <MethodCall>[], pending = Completer<bool>();
          messenger.setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            if (c.method == 'ready') {
              return {
                ...roster.snapshot(),
                'presentation': {'interactionStyle': suite.name},
              };
            }
            if (c.method == 'action') return pending.future;
            return true;
          });
          final semantics = t.ensureSemantics();
          await t.pumpWidget(const FriendsWindowApp());
          await t.pumpAndSettle();
          final target = find.byKey(const Key('friend-open-f1'));
          if (source == 'pointer') {
            await t.tap(target);
          } else if (source == 'keyboard') {
            final pressable = find.descendant(
              of: target,
              matching: find.byType(SuitePressable),
            );
            final focus = pressable.evaluate().isNotEmpty
                ? t.widget<SuitePressable>(pressable).focusNode!
                : t
                      .widget<FocusableActionDetector>(
                        find
                            .descendant(
                              of: target,
                              matching: find.byType(FocusableActionDetector),
                            )
                            .first,
                      )
                      .focusNode!;
            focus.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            final node = exposedNodes(t).singleWhere(
              (n) =>
                  n.getSemanticsData().label.startsWith('北辰 · 打开聊天') &&
                  n.getSemanticsData().hasAction(SemanticsAction.tap),
            );
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              node.id,
              SemanticsAction.tap,
            );
          }
          await visibleFrames(t);
          final sent = calls.where((c) => c.method == 'action').toList();
          expect(sent, hasLength(1));
          final args = sent.single.arguments as Map;
          expect(args['action'], 'chat');
          expect(args['key'], 'f1');
          expect(args['scope'], 'friends1');
          expect(
            args['motionSource'],
            source == 'pointer' ? 'pointer' : 'keyboard',
          );
          pending.complete(false);
          await t.pumpAndSettle();
          await remove(t);
          semantics.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          expect(t.takeException(), isNull);
        },
      );
    }
    for (final kind in ['messages', 'notifications']) {
      for (final source in ['pointer', 'keyboard']) {
        testWidgets(
          '$suite $kind $source actual auxiliary read follows live preferences and ignores stale snapshot',
          (t) async {
            size(t, const Size(1100, 850));
            final channel = MethodChannel('starbridge/$kind-surface');
            final messenger = t.binding.defaultBinaryMessenger;
            final result = Completer<Object?>();
            final calls = <MethodCall>[];
            Map<String, Object?> snapshot({
              int revision = 1,
              int opening = 1,
              bool reduced = false,
              String? overrideSource,
            }) => {
              'opening': opening,
              'revision': revision,
              'openingSource': overrideSource ?? source,
              'presentation': {
                'interactionStyle': suite.name,
                'reduceMotion': reduced,
                'appearanceMode': reduced ? 'light' : 'dark',
              },
              'view': jsonEncode({'scope': 'same-owner', 'targetVersion': 0}),
            };
            messenger.setMockMethodCallHandler(channel, (c) async {
              calls.add(c);
              if (c.method == 'ready') return snapshot();
              if (c.method == 'rpc') {
                final op = (c.arguments as Map)['op'];
                if (op == 'refresh' || op == 'directory') return result.future;
              }
              return null;
            });
            await t.pumpWidget(SocialWindowApp(kind: kind));
            await t.pump();
            await t.pump();
            await native(channel.name, 'viewportActive', true);
            await visibleFrames(t);
            expect(find.byType(SocialReadActivity), findsOneWidget);
            expect(waitData(t).reduceMotion, source == 'keyboard');
            final owner = kind == 'messages'
                ? t
                      .widget<DirectMessagesPage>(
                        find.byType(DirectMessagesPage),
                      )
                      .sharedModule
                : null;
            await native(
              channel.name,
              'snapshot',
              snapshot(revision: 2, reduced: true, overrideSource: 'pointer'),
            );
            await visibleFrames(t);
            expect(waitData(t).reduceMotion, isTrue);
            expect(waitData(t).suite, suite);
            // Palette interpolation is an existing MaterialApp behavior, not
            // the read marker's loop. Step real frames so its implicit children
            // can finish; a remaining read loop would time out this bound.
            await t.pumpAndSettle(
              const Duration(milliseconds: 50),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 2),
            );
            expect(t.hasRunningAnimations, isFalse);
            await native(channel.name, 'snapshot', snapshot(revision: 1));
            await visibleFrames(t);
            expect(waitData(t).reduceMotion, isTrue);
            await native(
              channel.name,
              'snapshot',
              snapshot(revision: 3, reduced: false, overrideSource: 'pointer'),
            );
            await visibleFrames(t);
            expect(waitData(t).reduceMotion, source == 'keyboard');
            if (owner != null) {
              expect(
                t
                    .widget<DirectMessagesPage>(find.byType(DirectMessagesPage))
                    .sharedModule,
                same(owner),
              );
            }
            expect(
              calls.where(
                (c) =>
                    c.method == 'rpc' &&
                    const {
                      'send',
                      'markRead',
                    }.contains((c.arguments as Map)['op']),
              ),
              isEmpty,
            );
            await remove(t);
            result.complete(
              kind == 'messages'
                  ? <Object?>[]
                  : {'items': <Object?>[], 'ready': true},
            );
            await t.pump();
            await t.pump();
            messenger.setMockMethodCallHandler(channel, null);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }

  test('opening annotation falls back static safely and uses existing validated menu origin', () async {
    for (final raw in [
      null,
      true,
      1,
      '',
      'unknown',
      {'keyboard': true},
    ]) {
      expect(decodeWindowOpeningSource(raw), InteractionSource.programmatic);
    }
    expect(
      withMenuReadOrigin('keyboard', captureWindowOpeningSource),
      InteractionSource.keyboard,
    );
    await runStarBridgeActivation<void>(InteractionSource.pointer, () {
      expect(
        withMenuReadOrigin('keyboard', captureWindowOpeningSource),
        InteractionSource.pointer,
      );
      for (final action in ['chat', 'messages', 'profile']) {
        final argument =
            menuReadSourceArgument('friendsAction', {'action': action}) as Map;
        expect(argument['motionSource'], 'pointer');
      }
      final original = {'action': 'remove'};
      expect(menuReadSourceArgument('friendsAction', original), same(original));
    });
    expect(captureWindowOpeningSource(), InteractionSource.programmatic);
  });
}
