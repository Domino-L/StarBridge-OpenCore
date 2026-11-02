import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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

class DelayedAvatarVisitorPort extends VisitorPort {
  final avatarRead = Completer<FriendRow?>();
  int socialReads = 0;
  @override
  Future<FriendRow?> social(UserTarget target) {
    socialReads++;
    return avatarRead.future;
  }
}

void main() {
  setUpAll(loadFonts);
  const wirePath = String.fromEnvironment('STARBRIDGE_VISITOR_BRIDGE_INPUT');
  test(
    'Java runtime to Host bridge fixture reaches Flutter read-only projection',
    () async {
      final file = File(wirePath);
      expect(file.isAbsolute, isTrue);
      expect(file.lengthSync(), lessThanOrEqualTo(64 * 1024));
      final payload = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, Object?>();
      final snapshot = parsePersonalProfileSnapshot(payload);
      final projection = PersonalProfileProjection.fromSnapshot(snapshot);
      expect(snapshot.availability, PersonalProfileAvailability.available);
      expect(snapshot.callSign, 'Synthetic Visitor');
      expect(snapshot.gameHandle, '');
      final identity = (payload['profile'] as Map)['identity'] as Map;
      expect(projection.avatarImageData, identity['avatarAssetId']);
      expect(projection.avatarImageData, startsWith('data:image/png;base64,'));
      final codec = await ui.instantiateImageCodec(
        base64Decode(projection.avatarImageData!.split(',').last),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 1);
          expect(frame.image.height, 1);
          final pixels = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixels!.buffer.asUint8List(), [0x34, 0x56, 0x78, 0xff]);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      expect(projection.canEdit, isFalse);
      expect(snapshot.presentation, isNull);
      expect(projection.moduleLayout, hasLength(64));
      for (var index = 0; index < 64; index++) {
        final module = projection.moduleLayout[index];
        expect(module.moduleId, 'favorite-ships-${index + 1}');
        expect(module.isVisible, isFalse);
        expect(module.favoriteShipIds, [
          (index + 1).toRadixString(16).padLeft(32, '0'),
        ]);
      }
    },
    skip: wirePath.isEmpty
        ? 'Requires the synthetic Java -> Host fixture path'
        : false,
  );
  test('authorized visitor may redact Handle without losing the page', () {
    final profile = Map<String, Object?>.from(
      visitorPayload['profile']! as Map,
    );
    profile['identity'] = {'callSign': 'Visitor Pilot', 'gameHandle': ''};
    final result = parsePersonalProfileSnapshot({
      ...visitorPayload,
      'profile': profile,
    });
    expect(result.gameHandle, '');
    expect(result.allowEditing, isFalse);
    expect(result.availability, PersonalProfileAvailability.available);
  });
  test('read-only visitor retains 64 modules without owner edit metadata', () {
    final profile = Map<String, Object?>.from(
      visitorPayload['profile']! as Map,
    );
    profile['identity'] = {'callSign': 'Visitor Pilot', 'gameHandle': ''};
    profile['content'] = {
      'introduction': 'Shared layout',
      'modules': [
        for (var index = 0; index < 64; index++)
          {
            'id': 'favorite-ships-${index + 1}',
            'span': 1,
            'order': index,
            'position': -1,
            'isVisible': false,
            'favoriteShipIds': [(index + 1).toRadixString(16).padLeft(32, '0')],
          },
      ],
    };
    final result = parsePersonalProfileSnapshot({
      ...visitorPayload,
      'profile': profile,
    });
    final projection = PersonalProfileProjection.fromSnapshot(result);
    expect(projection.moduleLayout, hasLength(64));
    expect(projection.moduleLayout.last.moduleId, 'favorite-ships-64');
    expect(projection.moduleLayout.last.favoriteShipIds, [
      '00000000000000000000000000000040',
    ]);
    expect(
      projection.moduleLayout.every((module) => !module.isVisible),
      isTrue,
    );
    expect(result.presentation, isNull);
    expect(projection.canEdit, isFalse);
    expect(result.gameHandle, '');
  });
  test(
    'visitor Handle redaction does not accept missing or malformed identity',
    () {
      for (final handle in [null, 42, ' ']) {
        final profile = Map<String, Object?>.from(
          visitorPayload['profile']! as Map,
        );
        profile['identity'] = {
          'callSign': 'Visitor Pilot',
          'gameHandle': handle,
        };
        expect(
          () => parsePersonalProfileSnapshot({
            ...visitorPayload,
            'profile': profile,
          }),
          throwsA(isA<BridgeFormatException>()),
        );
      }
      final profile = Map<String, Object?>.from(
        visitorPayload['profile']! as Map,
      );
      profile['identity'] = {'callSign': 'Owner Pilot', 'gameHandle': ''};
      expect(
        () => parsePersonalProfileSnapshot({
          ...visitorPayload,
          'editable': true,
          'profile': profile,
        }),
        throwsA(isA<BridgeFormatException>()),
      );
    },
  );
  testWidgets('fresh visitor profile avatar wins over the entry thumbnail', (
    tester,
  ) async {
    final p = VisitorPort();
    addTearDown(p.changes.close);
    const currentAvatar =
        'data:image/png;base64,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final profile = Map<String, Object?>.from(
      visitorPayload['profile']! as Map,
    );
    profile['identity'] = {
      'callSign': 'Visitor Pilot',
      'gameHandle': 'Visitor_Handle',
      'avatarAssetId': currentAvatar,
    };
    p.pending = Completer<PersonalProfileSnapshot>()
      ..complete(
        parsePersonalProfileSnapshot({...visitorPayload, 'profile': profile}),
      );
    await tester.pumpWidget(
      app(
        UserProfilePage(
          port: p,
          target: UserTarget.community('a' * 32, 'b' * 32),
          avatarImageData: 'stale-entry-avatar',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PersonalProfileAvatar>(find.byType(PersonalProfileAvatar))
          .imageData,
      currentAvatar,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'visitor without an entry photo loads its authorized avatar without blocking profile content',
    (tester) async {
      final p = DelayedAvatarVisitorPort();
      addTearDown(p.changes.close);
      await tester.pumpWidget(
        app(
          UserProfilePage(
            port: p,
            target: UserTarget.community('a' * 32, 'b' * 32),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Visitor Pilot'), findsWidgets);
      expect(p.socialReads, 1);
      p.avatarRead.complete(
        FriendRow(
          'Visitor Pilot',
          'Visitor_Handle',
          'friend',
          DateTime.utc(2026),
          avatar: 'authorized-avatar-fixture',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PersonalProfileAvatar>(find.byType(PersonalProfileAvatar))
            .imageData,
        'authorized-avatar-fixture',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final failureKey in [
    'profile.visitor.notVisible',
    'profile.error.unavailable',
  ]) {
    testWidgets(
      'visitor refresh clears stale content and avatar on $failureKey',
      (tester) async {
        final p = VisitorPort();
        addTearDown(p.changes.close);
        await tester.pumpWidget(
          app(
            UserProfilePage(
              port: p,
              target: UserTarget.community('a' * 32, 'b' * 32),
              avatarImageData: 'entry-avatar',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Authorized shared introduction'), findsOneWidget);
        expect(find.byType(PersonalProfileAvatar), findsOneWidget);

        p.pending = Completer<PersonalProfileSnapshot>();
        await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
        await tester.pump();
        expect(find.text('Authorized shared introduction'), findsNothing);
        expect(find.byType(PersonalProfileAvatar), findsNothing);
        p.pending!.complete(
          PersonalProfileSnapshot.unavailable(failureKey: failureKey),
        );
        await tester.pumpAndSettle();
        expect(find.text('Visitor Pilot'), findsNothing);
        expect(find.byType(PersonalProfileAvatar), findsNothing);

        p.pending = null;
        await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
        await tester.pumpAndSettle();
        expect(find.text('Authorized shared introduction'), findsOneWidget);
        expect(p.reads, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'late refreshed visitor profile cannot return after account invalidation',
    (tester) async {
      final p = VisitorPort();
      addTearDown(p.changes.close);
      await tester.pumpWidget(
        app(
          UserProfilePage(
            port: p,
            target: UserTarget.community('a' * 32, 'b' * 32),
            avatarImageData: 'retired-entry-avatar',
          ),
        ),
      );
      await tester.pumpAndSettle();
      p.pending = Completer<PersonalProfileSnapshot>();
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pump();
      p.changes.add(null);
      await tester.pump();
      p.pending!.complete(parsePersonalProfileSnapshot(visitorPayload));
      await tester.pumpAndSettle();
      expect(find.text('Visitor Pilot'), findsNothing);
      expect(find.text('Authorized shared introduction'), findsNothing);
      expect(find.byType(PersonalProfileAvatar), findsNothing);
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pumpAndSettle();
      expect(p.reads, 2);
      expect(find.text('Visitor Pilot'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late visitor avatar cannot return after account invalidation', (
    tester,
  ) async {
    final p = DelayedAvatarVisitorPort();
    addTearDown(p.changes.close);
    await tester.pumpWidget(
      app(
        UserProfilePage(
          port: p,
          target: UserTarget.community('a' * 32, 'b' * 32),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(p.socialReads, 1);
    p.changes.add(null);
    await tester.pumpAndSettle();
    p.avatarRead.complete(
      FriendRow(
        'Visitor Pilot',
        'Visitor_Handle',
        'friend',
        DateTime.utc(2026),
        avatar: 'retired-avatar-fixture',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PersonalProfileAvatar), findsNothing);
    expect(find.text('Visitor Pilot'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
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
