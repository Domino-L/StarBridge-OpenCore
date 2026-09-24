import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_avatar_editor.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_visitor_profile_port.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show app, loadFonts;

const visitorPayload = <String, Object?>{
  'schemaVersion': 1,
  'editable': false,
  'profile': {
    'isPublic': false,
    'visibility': 'friendsFleetAndOrganizations',
    'revision': 2,
    'identity': {'callSign': 'Visitor Pilot', 'gameHandle': 'Visitor_Handle'},
    'content': {
      'introduction': 'Authorized shared introduction',
      'modules': [],
    },
  },
};

class VisitorPort extends WorkspaceTestPort
    implements CommunityVisitorProfilePort, UserInteractionPort {
  VisitorPort() {
    reader = (target, query, offset) async {
      final payload = workspacePayload(target: target, query: query);
      ((payload['members'] as List).single as Map)['isSelf'] = false;
      return CommunityWorkspace.parse(payload);
    };
  }
  @override
  bool get visitorProfilesAvailable => true;
  int reads = 0;
  String? requestedTarget, requestedMember;
  bool denied = false;
  @override
  Future<void> close() async {}
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) =>
      readMemberPersonalProfile(target.contextRef!, target.reference);
  @override
  Future<FriendRow?> social(UserTarget target) async => null;
  @override
  Future<FriendCommandResult> execute(String action, String reference) async =>
      const FriendCommandResult('rejected');
  Completer<PersonalProfileSnapshot>? pending;
  @override
  Future<PersonalProfileSnapshot> readMemberPersonalProfile(
    String targetRef,
    String memberRef,
  ) async {
    reads++;
    requestedTarget = targetRef;
    requestedMember = memberRef;
    return pending?.future ??
        (denied
            ? const PersonalProfileSnapshot.unavailable(
                failureKey: 'profile.visitor.notVisible',
              )
            : parsePersonalProfileSnapshot(visitorPayload));
  }
}

void main() {
  setUpAll(loadFonts);
  test(
    'visitor bridge rejects an unexpectedly editable owner response',
    () async {
      final h = CommunityHarness(
        legacy: true,
        capabilities: ['communities.memberPersonalProfile'],
        responses: {
          'communities.memberPersonalProfile': {
            ...visitorPayload,
            'editable': true,
          },
        },
      );
      addTearDown(h.close);
      expect(
        (await h.adapter.readMemberPersonalProfile(
          'a' * 32,
          'b' * 32,
        )).availability,
        PersonalProfileAvailability.unavailable,
      );
    },
  );
  test(
    'visitor bridge only sends scoped refs and forces read-only response',
    () async {
      final h = CommunityHarness(
        legacy: true,
        capabilities: ['communities.memberPersonalProfile'],
        responses: {'communities.memberPersonalProfile': visitorPayload},
      );
      addTearDown(h.close);
      final profile = await h.adapter.readMemberPersonalProfile(
        'a' * 32,
        'b' * 32,
      );
      expect(profile.callSign, 'Visitor Pilot');
      expect(profile.allowEditing, isFalse);
      expect(profile.local, isNull);
      expect(h.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'memberRef': 'b' * 32,
      });
      expect(h.requests.where((r) => r.name.contains('Self')), isEmpty);
    },
  );
  for (final error in [
    'profile.visitor_not_visible',
    'communities.refreshRequired',
    'network.failure',
  ]) {
    test('visitor error $error never falls back to own content', () async {
      final h = CommunityHarness(
        legacy: true,
        capabilities: ['communities.memberPersonalProfile'],
        error: error,
      );
      addTearDown(h.close);
      final profile = await h.adapter.readMemberPersonalProfile(
        'a' * 32,
        'b' * 32,
      );
      expect(profile.availability, PersonalProfileAvailability.unavailable);
      expect(profile.callSign, isEmpty);
      expect(h.requests.length, 2);
      expect(profile.failureKey, isNot(contains('private upstream')));
    });
  }
  test('visitor late response after account change is discarded', () async {
    final h = CommunityHarness(
      legacy: true,
      capabilities: ['communities.memberPersonalProfile'],
      holdNames: {'communities.memberPersonalProfile'},
      responses: {'communities.memberPersonalProfile': visitorPayload},
    );
    addTearDown(h.close);
    final reading = h.adapter.readMemberPersonalProfile('a' * 32, 'b' * 32);
    await h.readArrived.future;
    await h.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await h.reply(
      h.requests.firstWhere(
        (r) => r.name == 'communities.memberPersonalProfile',
      ),
    );
    expect(
      (await reading).availability,
      PersonalProfileAvailability.unavailable,
    );
  });
  testWidgets(
    'member avatar opens that member as a read-only page, never a dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = VisitorPort();
      addTearDown(p.changes.close);
      final navigation = UserPageNavigation();
      navigation.open = (context, builder, title) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => Scaffold(body: builder(context)),
          ),
        );
      };
      await tester.pumpWidget(
        UserInteractionScope(
          navigation: navigation,
          port: p,
          messagePage: null,
          child: host(p, const Locale('zh', 'CN')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(UserAvatarMenu).first);
      await tester.pumpAndSettle();
      final menu = find.widgetWithText(MenuItemButton, '查看资料');
      expect(tester.widget<MenuItemButton>(menu).onPressed, isNotNull);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Visitor Pilot'), findsOneWidget);
      expect(find.text('Authorized shared introduction'), findsOneWidget);
      expect(p.requestedTarget, 'a' * 32);
      expect(p.requestedMember, 'b' * 32);
      expect(find.byKey(const Key('profile-edit')), findsNothing);
      expect(find.byKey(const Key('profile-visibility')), findsNothing);
      p.denied = true;
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('Visitor Pilot'), findsNothing);
      expect(find.textContaining('对方尚未公开'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [440.0, 1280.0]) {
    testWidgets(
      'visitor $width cannot inherit own avatar or survive invalidation',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final p = VisitorPort();
        addTearDown(p.changes.close);
        await tester.pumpWidget(
          app(
            AccountAvatarScope(
              port: null,
              imageData: 'owner-only-avatar',
              editable: true,
              child: UserProfilePage(
                port: p,
                target: UserTarget.community('a' * 32, 'b' * 32),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PersonalProfileAvatar>(find.byType(PersonalProfileAvatar))
              .imageData,
          isNull,
        );
        expect(
          tester.widget<UserAvatarMenu>(find.byType(UserAvatarMenu)).isSelf,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        p.changes.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Visitor Pilot'), findsNothing);
        expect(find.textContaining('成员资料已更新'), findsOneWidget);
        expect(p.reads, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
