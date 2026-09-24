import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profiles_session.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';

const fixtureProfile = PersonalProfileSnapshot.available(
  allowEditing: false,
  callSign: 'Fixture pilot',
  gameHandle: 'Fixture-Pilot',
  about: 'Synthetic profile',
  avatarStyle: 0,
  wallpaperId: 'none',
  visibility: PersonalProfileVisibility.friendsOnly,
  presenceIntent: PersonalProfilePresenceIntent.none,
  affiliations: [
    PersonalProfileAffiliationSummary(
      kind: PersonalProfileAffiliationKind.featuredCommunity,
      name: 'Fixture community',
      code: 'FIXTURE',
      positionLabelKey: 'profile.affiliation.position.fleetMember',
      logoUrl: 'https://invalid.example/private-image',
    ),
  ],
  availabilityWindows: [
    PersonalProfileAvailabilityWindow(
      dayGroup: PersonalProfileDayGroup.weekend,
      startTime: '08:00',
      endTime: '22:00',
    ),
  ],
  timeZoneLabel: 'UTC+00:00',
  gameplayMinutes: 42,
  activityRhythm: PersonalProfileActivityRhythm.casual,
  roles: [
    PersonalProfileTagValue(
      labelKey: 'profile.role.pilot',
      category: PersonalProfileTagCategory.ship,
    ),
  ],
  participationInterests: [],
  supportCapabilities: [],
  shipWishlist: [],
  favoriteShips: [
    PersonalProfileShipSummary(
      identity: PersonalProfileShipIdentity(
        runtimeId: 'fixture-ship',
        englishName: 'Fixture ship',
        simplifiedChineseName: '测试船',
        traditionalChineseName: '測試船',
      ),
      manufacturer: 'Fixture yard',
      imageAsset: '',
      roleKey: 'profile.shipRole.expedition',
      crewLabel: '1',
      sizeKey: 'profile.shipSize.small',
      valueLabel: r'$250',
      formerlyOwned: true,
    ),
  ],
  hangarSummary: PersonalProfileHangarSummary.empty(),
  moduleLayout: [
    PersonalProfileModuleLayoutItem(
      moduleId: PersonalProfileModuleIds.hangarSummary,
      size: PersonalProfileModuleSize.one,
      isVisible: true,
      position: 0,
    ),
  ],
);

class ProfilePort implements UserInteractionPort {
  final changes = StreamController<void>.broadcast();
  final pending = Completer<PersonalProfileSnapshot>();
  bool closed = false;
  int reads = 0;
  UserTarget? lastTarget;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) {
    lastTarget = target;
    reads++;
    return pending.future;
  }

  @override
  Future<FriendRow?> social(UserTarget target) =>
      throw StateError('No social read authorized');
  @override
  Future<FriendCommandResult> execute(String action, String reference) =>
      throw StateError('No write authorized');
  @override
  Future<void> close() async {
    closed = true;
    await changes.close();
  }
}

class OwnProfilePort implements PersonalProfilePort {
  final events = StreamController<void>.broadcast();
  final pending = Completer<PersonalProfileSnapshot>();
  bool closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<PersonalProfileSnapshot> read() => pending.future;
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) =>
      throw StateError('No writes');
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

void main() {
  testWidgets('periodic refresh keeps the visible profile mounted', (
    tester,
  ) async {
    final ports = <ProfilePort>[], views = <Map<String, Object?>>[];
    final session = MenuProfilesSession(() {
      final port = ProfilePort();
      ports.add(port);
      return port;
    }, views.add);
    addTearDown(session.dispose);
    session.open(
      'steady',
      MenuProfileTarget(
        source: 'friend',
        reference: 'fixture',
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await tester.pump();
    ports.single.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.last['state'], 'ready');
    final initial = views.length;
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(ports.length, 2);
    expect(
      views.last['state'],
      'ready',
      reason: 'background refresh must not replace the profile with loading',
    );
    ports.last.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.skip(initial).every((view) => view['state'] == 'ready'), true);
    session.dispose();
    await tester.pump();
  });
  testWidgets('chat author renews its expiring reference before profile read', (
    tester,
  ) async {
    final port = ProfilePort(), views = <Map<String, Object?>>[];
    final grant = Completer<String>();
    final session = MenuProfilesSession(() => port, views.add);
    session.open(
      'p1',
      MenuProfileTarget(
        source: 'community',
        reference: 'expired-author',
        query: 'fixture',
        contextRef: 'private-community',
        refreshReference: () => grant.future,
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await tester.pump();
    expect(port.reads, 0);
    grant.complete('renewed-author');
    await tester.pump();
    expect(port.lastTarget!.reference, 'renewed-author');
    expect(port.lastTarget!.contextRef, 'private-community');
    port.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.last['state'], 'ready');
    expect(jsonEncode(views), isNot(contains('renewed-author')));
    session.dispose();
    await tester.pump();
  });
  testWidgets('closing during author renewal never starts a profile request', (
    tester,
  ) async {
    final port = ProfilePort(), views = <Map<String, Object?>>[];
    final grant = Completer<String>();
    final session = MenuProfilesSession(() => port, views.add);
    session.open(
      'p1',
      MenuProfileTarget(
        source: 'community',
        reference: 'old',
        query: '',
        refreshReference: () => grant.future,
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await tester.pump();
    session.closeWindow('p1');
    grant.complete('renewed');
    await tester.pump();
    expect(port.reads, 0);
    expect(port.closed, true);
    session.dispose();
    await tester.pump();
  });
  testWidgets(
    'self uses the owner read port and never exports editing authority',
    (tester) async {
      final own = OwnProfilePort(), views = <Map<String, Object?>>[];
      final session = MenuProfilesSession(
        () => throw StateError('Not a visitor'),
        views.add,
        createOwnPort: () => own,
      );
      session.open(
        'p1',
        MenuProfileTarget(
          source: 'self',
          reference: '',
          query: '',
          isCurrent: () => true,
          isAccountCurrent: () => true,
        ),
      );
      await tester.pump();
      final fixture = await InMemoryPersonalProfileAdapter.forReview(
        signedIn: true,
      ).read();
      expect(fixture.allowEditing, true);
      own.pending.complete(fixture);
      await tester.pump();
      final rendered = MenuProfileView.parse(views.last).snapshot!;
      expect(rendered.callSign, fixture.callSign);
      expect(rendered.allowEditing, false);
      expect(rendered.local, isNull);
      own.events.add(null);
      await tester.pump();
      expect(views.last['state'], 'revoked');
      expect(own.closed, true);
      session.dispose();
      await tester.pump();
    },
  );
  testWidgets('self read result is discarded after account replacement', (
    tester,
  ) async {
    final own = OwnProfilePort(), views = <Map<String, Object?>>[];
    var current = true;
    final session = MenuProfilesSession(
      () => throw StateError('Not a visitor'),
      views.add,
      createOwnPort: () => own,
    );
    session.open(
      'p1',
      MenuProfileTarget(
        source: 'self',
        reference: '',
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => current,
      ),
    );
    await tester.pump();
    current = false;
    own.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.last['state'], 'revoked');
    expect(views.any((v) => v['state'] == 'ready'), false);
    session.dispose();
    await tester.pump();
  });
  testWidgets(
    'community profile preserves primary-only member and context references',
    (tester) async {
      final port = ProfilePort(), views = <Map<String, Object?>>[];
      final session = MenuProfilesSession(() => port, views.add);
      session.open(
        'p1',
        MenuProfileTarget(
          source: 'community',
          reference: 'private-member',
          contextRef: 'private-community',
          query: 'Pilot',
          isCurrent: () => true,
          isAccountCurrent: () => true,
        ),
      );
      await tester.pump();
      expect(port.lastTarget!.contextRef, 'private-community');
      expect(port.lastTarget!.reference, 'private-member');
      port.pending.complete(fixtureProfile);
      await tester.pump();
      expect(views.last['state'], 'ready');
      expect(jsonEncode(views), isNot(contains('private-community')));
      expect(jsonEncode(views), isNot(contains('private-member')));
      session.dispose();
      await tester.pump();
    },
  );
  test('display codec preserves visitor fields and removes authority and external URLs', () {
    final encoded = MenuProfileView.encode(fixtureProfile);
    final restored = MenuProfileView.parse(jsonDecode(jsonEncode(encoded)))
        .snapshot!;
    expect(restored.allowEditing, false);
    expect(restored.local, isNull);
    expect(restored.callSign, fixtureProfile.callSign);
    expect(restored.favoriteShips.single.formerlyOwned, true);
    expect(restored.favoriteShips.single.valueLabel, r'$250');
    expect(restored.moduleLayout.single.size, PersonalProfileModuleSize.one);
    expect(restored.availabilityWindows.single.days, [6, 0]);
    expect(
      restored.roles.single.labelKey,
      fixtureProfile.roles.single.labelKey,
    );
    expect(jsonEncode(encoded), isNot(contains('https://')));
    expect(restored.affiliations.single.logoUrl, isNull);
    expect(MenuProfileView.asset('../secret'), '');
    expect(MenuProfileView.asset('file:///secret'), '');
    expect(MenuProfileView.asset('assets/../../secret'), '');
    expect(
      MenuProfileView.inlineImage('https://invalid.example/avatar'),
      isNull,
    );
    expect(
      MenuProfileView.parse({
        ...encoded,
        'ships': List.filled(65, encoded['ships']),
      }).state,
      'unavailable',
    );
    expect(
      MenuProfileView.parse({...encoded, 'minutes': -1}).state,
      'unavailable',
    );
    expect(
      MenuProfileView.encode(
        const PersonalProfileSnapshot.unavailable(
          failureKey: 'profile.visitor.notVisible',
        ),
      )['state'],
      'notVisible',
    );
  });

  testWidgets(
    'independent reads survive source close, reject duplicates and cap windows',
    (tester) async {
      final ports = <ProfilePort>[], views = <Map<String, Object?>>[];
      var sourceCurrent = true;
      final target = MenuProfileTarget(
        source: 'friend',
        reference: 'private-ref',
        query: '',
        isCurrent: () => sourceCurrent,
        isAccountCurrent: () => true,
      );
      final session = MenuProfilesSession(() {
        final p = ProfilePort();
        ports.add(p);
        return p;
      }, views.add);
      addTearDown(session.dispose);
      for (var i = 1; i <= 5; i++) {
        session.open('p$i', target);
      }
      session.open('p1', target);
      await tester.pump();
      expect(ports.length, 4);
      expect(
        views.any((v) => v['window'] == 'p5' && v['state'] == 'unavailable'),
        true,
      );
      sourceCurrent = false;
      ports.first.pending.complete(fixtureProfile);
      await tester.pump();
      expect(views.last['state'], 'ready');
      session.refresh('p1');
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(ports.first.closed, true);
      expect(ports.length, 5);
      session.closeWindow('p2');
      await tester.pump();
      expect(ports[1].closed, true);
      final before = views.length;
      ports[1].pending.complete(fixtureProfile);
      await tester.pump();
      expect(views.length, before);
      session.hide();
      await tester.pump();
      expect(ports.every((p) => p.closed), true);
      for (final p in ports) {
        if (!p.pending.isCompleted) p.pending.complete(fixtureProfile);
      }
      await tester.pump();
      expect(views.length, before);
    },
  );

  testWidgets(
    'identity invalidation clears an available window and rejects late reads',
    (tester) async {
      final ports = <ProfilePort>[], views = <Map<String, Object?>>[];
      final target = MenuProfileTarget(
        source: 'friend',
        reference: 'private-ref',
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => true,
      );
      final session = MenuProfilesSession(() {
        final p = ProfilePort();
        ports.add(p);
        return p;
      }, views.add);
      addTearDown(session.dispose);
      session.open('p1', target);
      session.open('p2', target);
      await tester.pump();
      ports.first.pending.complete(fixtureProfile);
      await tester.pump();
      for (final p in ports) {
        p.changes.add(null);
      }
      await tester.pump();
      expect(views.where((v) => v['state'] == 'revoked').length, 2);
      expect(ports.every((p) => p.closed), true);
      final before = views.length;
      ports[1].pending.complete(fixtureProfile);
      await tester.pump();
      session.refresh('p1');
      expect(views.length, before);
    },
  );

  testWidgets('timed out read is canceled and retry gets a fresh port', (
    tester,
  ) async {
    final ports = <ProfilePort>[], views = <Map<String, Object?>>[];
    final session = MenuProfilesSession(() {
      final p = ProfilePort();
      ports.add(p);
      return p;
    }, views.add);
    addTearDown(session.dispose);
    session.open(
      'p1',
      MenuProfileTarget(
        source: 'friend',
        reference: 'private-ref',
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(ports.first.closed, true);
    expect(views.last['state'], 'unavailable');
    session.refresh('p1');
    await tester.pump();
    expect(ports.length, 2);
    ports.last.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.last['state'], 'ready');
    ports.first.pending.complete(fixtureProfile);
    await tester.pump();
    expect(views.where((v) => v['state'] == 'ready').length, 1);
    session.dispose();
    await tester.pump();
  });
}
