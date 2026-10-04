import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/common/bridge_user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';

import '../../features/communities/bridge_communities_test.dart'
    show CommunityHarness;
import '../../features/communities/community_visitor_profile_test.dart'
    show visitorPayload;

class Port implements FriendsPort {
  Port({this.chatReference = 'private-chat'});
  final String? chatReference;
  final events = StreamController<void>.broadcast(sync: true);
  int reads = 0;
  bool closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) async {
    reads++;
    return FriendsReadResult(
      FriendsReadState.ready,
      snapshot: FriendsSnapshot(
        groups: {
          FriendsSection.friends: [
            FriendRow(
              '测试好友',
              'fixture',
              'friend',
              DateTime(2026),
              targetRef: 'private-authority-$reads',
              chatTargetRef: chatReference,
              conversationKey: 'stable',
              shared: {'presence': 'Offline'},
            ),
          ],
        },
        results: [],
      ),
    );
  }

  @override
  void cancelPending() {}
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

const channel = MethodChannel('starbridge/friends-primary');
const codec = StandardMethodCodec();
Future<Object?> fromNative(String method, Object args) async {
  final result = Completer<Object?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, args)),
        (reply) =>
            result.complete(reply == null ? null : codec.decodeEnvelope(reply)),
      );
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final chatReference in ['d' * 32, null]) {
    testWidgets(
      'native friend-window profile separates read and command references: $chatReference',
      (tester) async {
        final calls = <MethodCall>[], targets = <MenuProfileTarget>[];
        final port = Port(chatReference: chatReference);
        final host = CommunityHarness(
          legacy: true,
          capabilities: ['users.interaction'],
          responses: {'users.profile': visitorPayload},
        );
        final interaction = BridgeUserInteraction(host.session);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'show' ? true : null;
        });
        final binding = FriendsWindowBinding(
          create: (publish) => MenuFriendsSession(port, publish),
          openChat: (_, _) async {},
          openMessages: (_) async {},
          openProfile: (target) async {
            targets.add(target);
            final profile = await interaction.profile(
              UserTarget(target.source, target.reference, query: target.query),
            );
            expect(profile.callSign, 'Visitor Pilot');
          },
        );
        addTearDown(() async {
          binding.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          await interaction.close();
          await host.close();
        });
        Map action(String name) {
          final snapshot =
              calls.lastWhere((call) => call.method == 'snapshot').arguments
                  as Map;
          final view = jsonDecode(snapshot['view'] as String) as Map;
          expect(snapshot['view'], isNot(contains('private-authority')));
          if (chatReference != null) {
            expect(snapshot['view'], isNot(contains(chatReference)));
          }
          return {
            ...snapshot,
            'scope': view['scope'],
            'action': name,
            'key': (view['rows'] as List).first['key'],
            'value': '',
          };
        }

        expect(await binding.open(), true);
        await tester.pump();
        final originalAction = action('profile');
        expect(await fromNative('action', originalAction), true);
        expect(
          targets.single.source,
          chatReference == null ? 'friend' : 'conversation',
        );
        expect(
          targets.single.reference,
          chatReference ?? 'private-authority-1',
        );
        expect(await fromNative('action', action('refresh')), true);
        await tester.pump();
        expect(port.reads, 2);
        expect(targets.first.isCurrent(), false);
        expect(targets.first.isAccountCurrent(), true);
        expect(await fromNative('action', originalAction), false);
        expect(await fromNative('action', action('profile')), true);
        expect(targets.last.reference, chatReference ?? 'private-authority-2');
        expect(host.requests.where((r) => r.name == 'users.profile').length, 2);
        expect(
          host.requests.where((r) => r.name == 'friends.execute'),
          isEmpty,
        );
        port.events.add(null);
        await tester.pump();
        expect(targets.every((target) => !target.isAccountCurrent()), true);
        binding.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'singleton reopen, hidden lease, no authority over wire, account replay rejected',
    (tester) async {
      final calls = <MethodCall>[], chats = <String>[];
      final port = Port();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'show' ? true : null;
      });
      final binding = FriendsWindowBinding(
        create: (publish) => MenuFriendsSession(port, publish),
        openChat: (target, current) async {
          if (current()) chats.add(target.reference);
        },
        openMessages: (_) async {},
        openProfile: (_) async {},
      );
      Map snapshot() =>
          calls.lastWhere((c) => c.method == 'snapshot').arguments as Map;
      Map action(Map snapshot) {
        final view = jsonDecode(snapshot['view'] as String) as Map;
        return {
          ...snapshot,
          'scope': view['scope'],
          'action': 'chat',
          'key': (view['rows'] as List).first['key'],
          'value': '',
        };
      }

      expect(await binding.open(), true);
      await tester.pump();
      final first = snapshot();
      expect(first['view'], isNot(contains('private-authority')));
      expect(first['view'], isNot(contains('private-chat')));
      final request = action(first);
      expect(await fromNative('action', request), true);
      expect(chats, ['private-chat']);
      expect(await binding.open(), true);
      expect(port.reads, 1);
      expect(
        (calls.lastWhere((c) => c.method == 'show').arguments
            as Map)['opening'],
        first['opening'],
      );
      port.events.add(null);
      await tester.pump();
      expect(await fromNative('action', request), false);
      final second = snapshot();
      expect(
        jsonDecode(second['view'] as String)['scope'],
        isNot(request['scope']),
      );
      await fromNative('hidden', {'opening': second['opening']});
      final hiddenReads = port.reads;
      await tester.pump(const Duration(seconds: 30));
      expect(port.reads, hiddenReads);
      expect(await fromNative('action', action(second)), false);
      expect(await binding.open(), true);
      await tester.pump();
      expect(snapshot()['opening'], isNot(first['opening']));
      binding.dispose();
      await tester.pump();
      expect(port.closed, true);
      expect(calls.last.method, 'detach');
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('missing native runner fails safely without polling', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    final port = Port();
    final binding = FriendsWindowBinding(
      create: (publish) => MenuFriendsSession(port, publish),
      openChat: (_, _) async {},
      openMessages: (_) async {},
      openProfile: (_) async {},
    );
    expect(await binding.open(), false);
    final reads = port.reads;
    await tester.pump(const Duration(seconds: 30));
    expect(port.reads, reads);
    binding.dispose();
    await tester.pump();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
