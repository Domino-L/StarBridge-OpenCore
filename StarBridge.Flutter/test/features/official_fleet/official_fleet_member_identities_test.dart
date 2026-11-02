import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_views.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_section.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_read_failure.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/shared/embedded_avatar.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;

const _image =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
final _reference = 'a' * 64;
const _query = OfficialFleetMemberDirectoryQuery(sourceRef: 'officialFleet:7');

Map<String, Object?> _row(String? state) => {
  'memberRef': _reference,
  'callsign': state == 'starBridge' ? 'StarBridge pilot' : 'SCM pilot',
  'avatarUrl': null,
  'officialRankName': 'Member',
  'officialRankValue': null,
  'presence': 'unknown',
  'starBridgeConnected': state == 'starBridge' ? true : null,
  'identityState': ?state,
  if (state == 'starBridge') ...{
    'avatarImageData': _image,
    'profileTargetRef': _reference,
  },
};

OfficialFleetMemberDirectorySnapshot _snapshot(
  Map<String, Object?> row, [
  OfficialFleetMemberDirectoryQuery query = _query,
]) => parseOfficialFleetMembers({
  'schemaVersion': 1,
  'sourceRef': query.sourceRef,
  'search': query.search,
  'filter': 'all',
  'pageNumber': query.pageNumber,
  'pageSize': query.pageSize,
  'totalCount': 1,
  'totalPages': 1,
  'coverage': 'scmRegisteredMembers',
  'onlineCount': null,
  'inGameCount': null,
  'members': [row],
}, query);

void main() {
  setUpAll(loadFonts);
  test(
    'visible linkage, unlinked SCM and restricted identities remain distinct',
    () {
      final linked = _snapshot(_row('starBridge')).members.single;
      expect(linked.identityState, OfficialFleetMemberIdentityState.starBridge);
      expect(linked.callsign, 'StarBridge pilot');
      expect(linked.avatarImageData, _image);
      expect(linked.avatarUrl, isNull);
      expect(linked.profileTargetRef, _reference);
      expect(linked.starBridgeConnected, isTrue);
      expect(linked.presence, OfficialFleetMemberPresence.unknown);
      for (final state in [null, 'scm', 'restricted']) {
        final member = _snapshot(_row(state)).members.single;
        expect(member.profileTargetRef, isNull);
        expect(member.avatarImageData, isNull);
        expect(member.starBridgeConnected, isNull);
        expect(member.callsign, state == 'restricted' ? '' : 'SCM pilot');
        expect(member.identityState?.name, state);
      }
    },
  );

  for (final patch in <Map<String, Object?>>[
    {'starBridgeConnected': null},
    {'starBridgeConnected': 'true'},
    {'profileTargetRef': null},
    {'profileTargetRef': 'b' * 64},
    {'profileTargetRef': 'a' * 32},
    {'avatarUrl': 'https://example.invalid/avatar.png'},
    {'avatarImageData': ''},
    {'avatarImageData': 'data:image/png;base64,invalid'},
    {'avatarImageData': 'data:image/svg+xml;base64,PHN2Zy8+'},
    {'avatarImageData': 'x' * 4097},
    {'identityState': null},
    {'identityState': 'unknown'},
  ]) {
    test(
      'linked identity rejects conflicting or malformed fields ${patch.map((key, value) => MapEntry(key, value is String && value.length > 200 ? '${value.length} characters' : value))}',
      () {
        expect(
          () => _snapshot({..._row('starBridge'), ...patch}),
          throwsA(isA<BridgeFormatException>()),
        );
      },
    );
  }
  for (final state in [null, 'scm', 'restricted']) {
    for (final patch in <Map<String, Object?>>[
      {'starBridgeConnected': true},
      {'starBridgeConnected': false},
      {'profileTargetRef': _reference},
      {'avatarImageData': _image},
    ]) {
      test('$state cannot claim linked identity with $patch', () {
        expect(
          () => _snapshot({..._row(state), ...patch}),
          throwsA(isA<BridgeFormatException>()),
        );
      });
    }
  }
  test('restricted identity rejects SCM media and visible profile may omit its avatar', () {
    expect(
      () => _snapshot({
        ..._row('restricted'),
        'avatarUrl': 'https://example.invalid/photo',
      }),
      throwsA(isA<BridgeFormatException>()),
    );
    expect(
      _snapshot({..._row('starBridge'), 'avatarImageData': null})
          .members
          .single
          .profileTargetRef,
      _reference,
    );
  });

  for (final wide in [false, true]) {
    testWidgets(
      'linked ${wide ? 'wide' : 'compact'} row reuses exact profile target and retires anonymous data',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget view(String state, {bool allowed = true}) => app(
          Center(
            child: SizedBox(
              width: 1250,
              child: OfficialFleetMemberRow(
                member: _snapshot(_row(state)).members.single,
                wide: wide,
                onOpen: () {},
                sourceRef: _query.sourceRef,
                allowProfile: allowed,
              ),
            ),
          ),
        );
        await tester.pumpWidget(view('starBridge'));
        await tester.pumpAndSettle();
        final menu = tester.widget<UserAvatarMenu>(find.byType(UserAvatarMenu));
        expect(menu.target?.payload, {
          'source': 'officialFleet',
          'reference': _reference,
          'contextRef': _query.sourceRef,
          'query': '',
        });
        expect(menu.includeSocialActions, isFalse);
        expect(menu.avatarImageData, _image);
        expect(find.byType(EmbeddedAvatar), findsOneWidget);
        expect(find.byType(RemoteImage), findsNothing);
        await tester.pumpWidget(view('starBridge', allowed: false));
        expect(find.byType(UserAvatarMenu), findsNothing);
        await tester.pumpWidget(view('restricted'));
        await tester.pumpAndSettle();
        expect(find.text('资料受限的成员'), findsOneWidget);
        expect(find.text('SCM pilot'), findsNothing);
        expect(find.text('StarBridge pilot'), findsNothing);
        expect(find.byType(EmbeddedAvatar), findsNothing);
        expect(find.byType(RemoteImage), findsNothing);
        expect(find.byType(UserAvatarMenu), findsNothing);
        await tester.pumpWidget(view('scm'));
        expect(find.text('SCM pilot'), findsOneWidget);
        // RSI avatars never follow redirects off the validated host.
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 1250,
                child: OfficialFleetMemberRow(
                  member: _snapshot({
                    ..._row('scm'),
                    'avatarUrl':
                        'https://robertsspaceindustries.com/media/avatar.jpg',
                  }).members.single,
                  wide: wide,
                  onOpen: () {},
                  sourceRef: _query.sourceRef,
                ),
              ),
            ),
          ),
        );
        expect(
          tester.widget<RemoteImage>(find.byType(RemoteImage)).followRedirects,
          isFalse,
        );
        expect(find.byType(UserAvatarMenu), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final tapTarget in ['name', 'avatar']) {
    testWidgets(
      'member $tapTarget opens the existing read-only profile without social discovery',
      (tester) async {
        final port = _ProfilePort();
        addTearDown(port.events.close);
        Widget? opened;
        final navigation = UserPageNavigation()
          ..open = (context, builder, _) async {
            opened = builder(context);
          };
        await tester.pumpWidget(
          app(
            UserInteractionScope(
              navigation: navigation,
              port: port,
              messagePage: null,
              child: SizedBox(
                width: 320,
                child: OfficialFleetMemberRow(
                  member: _snapshot(_row('starBridge')).members.single,
                  wide: false,
                  onOpen: () => fail('The complete row must not be clickable'),
                  sourceRef: _query.sourceRef,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          tapTarget == 'name'
              ? find.text('StarBridge pilot')
              : find.byType(EmbeddedAvatar),
        );
        await tester.pumpAndSettle();
        expect(port.socialCalls, 0);
        await tester.tap(find.text('查看资料'));
        await tester.pumpAndSettle();
        expect(opened, isA<UserProfilePage>());
        final profile = opened! as UserProfilePage;
        expect(profile.target.payload, {
          'source': 'officialFleet',
          'reference': _reference,
          'contextRef': _query.sourceRef,
          'query': '',
        });
        expect(profile.avatarImageData, _image);
        expect(port.writes, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('restricted label exists in all product locales', () {
    expect(
      AppStrings.resolve(const Locale('zh', 'CN'))
          .text('officialFleet.members.identity.restricted'),
      '资料受限的成员',
    );
    expect(
      AppStrings.resolve(const Locale('zh', 'TW'))
          .text('officialFleet.members.identity.restricted'),
      '資料受限的成員',
    );
    expect(
      AppStrings.resolve(const Locale('en', 'US'))
          .text('officialFleet.members.identity.restricted'),
      'Member with a restricted profile',
    );
  });

  test('identity lookup failure cannot acquire stale-display semantics', () {
    for (final retryable in [false, true]) {
      final error = BridgeRemoteException(
        'official_fleet.identity_unavailable',
        retryable: retryable,
      );
      expect(fleetReadIsTransient(error), isFalse);
      expect(
        fleetReadFailureKey(error, members: true),
        'officialFleet.members.error.unavailable',
      );
    }
  });

  for (final state in ['starBridge', 'scm', 'restricted']) {
    test(
      '$state identity page is removed after an uncertain refresh',
      () async {
        final port = _MembersPort(state);
        final module = createOfficialFleetMembersModule(port);
        addTearDown(module.dispose);
        await module.open(_query.sourceRef);
        module.selectMember(_reference);
        port.failTransient = true;
        await module.refresh();
        expect(
          module.projection.value.availability,
          OfficialFleetMemberDirectoryAvailability.unavailable,
        );
        expect(module.projection.value.members, isEmpty);
        expect(module.selectedMemberRef.value, isNull);
      },
    );
  }
  testWidgets(
    'refreshing section disables the previously authorized profile target',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _MembersPort('starBridge');
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      await module.open(_query.sourceRef);
      await tester.pumpWidget(
        app(
          OfficialFleetMembersSection(
            sourceRef: _query.sourceRef,
            module: module,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<UserAvatarMenu>(find.byType(UserAvatarMenu)).target,
        isNotNull,
      );
      port.hold = true;
      final refresh = module.refresh();
      await tester.pump();
      expect(find.byType(UserAvatarMenu), findsNothing);
      port.pending.single.$2.complete(
        OfficialFleetMemberDirectorySnapshot.unavailable(
          query: port.pending.single.$1,
          failureKey: 'officialFleet.members.error.unavailable',
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatarMenu), findsNothing);
      await tester.pumpWidget(const SizedBox());
      // The failed read left its bounded retry waiting.
      module.dispose();
    },
  );
  test('retired viewer and source reject a late linked result', () async {
    final port = _MembersPort('starBridge');
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    await module.open(_query.sourceRef);
    port.hold = true;
    final old = module.refresh();
    module.reset();
    port.hold = false;
    await module.open('officialFleet:8');
    final before = module.projection.value;
    port.pending.single.$2.complete(
      _snapshot(_row('starBridge'), port.pending.single.$1),
    );
    await old;
    expect(module.projection.value, same(before));
    expect(module.projection.value.query?.sourceRef, 'officialFleet:8');
    expect(module.selectedMemberRef.value, isNull);
  });
}

final class _MembersPort implements OfficialFleetMembersPort {
  _MembersPort(this.state);
  final String state;
  bool? failTransient;
  bool hold = false;
  final pending =
      <
        (
          OfficialFleetMemberDirectoryQuery,
          Completer<OfficialFleetMemberDirectorySnapshot>,
        )
      >[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    if (hold) {
      final result = Completer<OfficialFleetMemberDirectorySnapshot>();
      pending.add((query, result));
      return result.future;
    }
    if (failTransient != null) {
      return OfficialFleetMemberDirectorySnapshot.unavailable(
        query: query,
        failureKey: 'officialFleet.members.error.unavailable',
        transientFailure: failTransient!,
      );
    }
    return _snapshot(_row(state), query);
  }

  @override
  Future<void> close() async {}
}

final class _ProfilePort implements UserInteractionPort {
  final events = StreamController<void>.broadcast();
  int socialCalls = 0, writes = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) async =>
      const PersonalProfileSnapshot.unavailable();
  @override
  Future<FriendRow?> social(UserTarget target) async {
    socialCalls++;
    return null;
  }

  @override
  Future<FriendCommandResult> execute(String action, String reference) async {
    writes++;
    return const FriendCommandResult('rejected');
  }

  @override
  Future<void> close() async {}
}
