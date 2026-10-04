import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/bridge_user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_avatar.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import '../communities/community_visitor_profile_test.dart' show visitorPayload;
import 'social_layout_test.dart' show app, size;

class DirectoryPort implements FriendsPort, FriendsCommandPort {
  DirectoryPort(this.chatReference);
  final String? chatReference;
  int reads = 0, writes = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get commandsAvailable => true;
  @override
  Future<FriendsReadResult> read({String? query}) async {
    reads++;
    return FriendsReadResult(
      FriendsReadState.ready,
      snapshot: FriendsSnapshot(
        groups: {
          FriendsSection.friends: [
            FriendRow(
              'Peer',
              'Peer_Handle',
              'friend',
              DateTime.utc(2026),
              targetRef: reads.toRadixString(16).padLeft(32, '0'),
              chatTargetRef: chatReference,
              actions: const ['remove', 'block'],
            ),
          ],
        },
        results: const [],
      ),
    );
  }

  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async {
    writes++;
    return const FriendCommandResult('accepted');
  }

  @override
  void cancelPending() {}
  @override
  Future<void> close() async {}
}

void main() {
  for (final chatReference in ['d' * 32, null]) {
    testWidgets(
      chatReference == null
          ? 'friend profile retains bounded fallback when no independent read target exists'
          : 'friend avatar reads profile through independent target across command refreshes',
      (tester) async {
        size(tester, const Size(1280, 800));
        final directory = DirectoryPort(chatReference);
        final module = FriendsModule(directory);
        final host = CommunityHarness(
          legacy: true,
          capabilities: ['users.interaction'],
          responses: {'users.profile': visitorPayload},
        );
        final interaction = BridgeUserInteraction(host.session);
        addTearDown(() async {
          module.dispose();
          await interaction.close();
          await host.close();
        });
        final navigation = UserPageNavigation()
          ..open = (context, builder, title) async {
            await Navigator.of(context)
                .push<void>(MaterialPageRoute(builder: builder));
          };
        await tester.pumpWidget(
          app(
            UserInteractionScope(
              navigation: navigation,
              port: interaction,
              messagePage: null,
              child: FriendsPage(createPort: () => directory, module: module),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initialCommand = module.rows.single.targetRef;
        for (var refresh = 0; refresh < 3; refresh++) {
          await module.refresh();
          await tester.pumpAndSettle();
        }
        expect(module.rows.single.targetRef, isNot(initialCommand));
        await tester.tap(find.byType(ChatAvatar).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, '查看资料'));
        await tester.pumpAndSettle();
        expect(find.byType(UserProfilePage), findsOneWidget);
        expect(find.text('Visitor Pilot'), findsWidgets);
        final request = host.requests.singleWhere(
          (request) => request.name == 'users.profile',
        );
        expect(request.payload, {
          'schemaVersion': 1,
          'source': chatReference == null ? 'friend' : 'conversation',
          'reference': chatReference ?? module.rows.single.targetRef,
          'query': 'Peer_Handle',
        });
        expect(directory.writes, 0);
        expect(
          host.requests.where((request) => request.name == 'friends.execute'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
