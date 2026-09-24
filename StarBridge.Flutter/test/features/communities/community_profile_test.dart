import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_controller.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> profilePayload({
  int revision = 7,
  String description = 'Original',
  bool canEditProfile = true,
}) => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'editRef': 'b' * 32,
  'code': 'A',
  'name': 'Organization A',
  'profileRevision': revision,
  'hasLogo': true,
  'hasBanner': false,
  'access': {
    'canEditProfile': canEditProfile,
    'canEditLogo': true,
    'canEditBanner': false,
  },
  'profile': {
    for (final key in communityProfileTextLimits.keys) key: '',
    for (final key in communityProfileFlags) key: false,
    'description': description,
    'language': 'English',
    'timeZoneId': 'UTC',
    'joinPolicy': 'Open',
    'activityWindows': [
      {
        'days': ['fri'],
        'startTime': '22:00',
        'endTime': '02:00',
        'endsNextDay': true,
      },
    ],
    'activeSystemIds': ['pyro'],
    'externalContacts': [
      {'platform': 'Discord', 'value': 'private-contact'},
    ],
    'internalOnly': 'must-not-cross',
  },
};

void main() {
  test('automatic lease renewal preserves an unsaved profile draft', () async {
    final fake = ProfileFake();
    final model = CommunityProfileController(fake, 'a' * 32);
    await model.load();
    model.update('description', 'Keep my draft');
    fake.expiredEdits = true;
    await model.refreshLease();
    expect(fake.reads, 2);
    expect(fake.writes, 0);
    expect(model.fields['description'], 'Keep my draft');
    expect(model.canSave, isTrue);
    expect(model.invalidated, isFalse);
    model.dispose();
    await fake.events.close();
  });
  test('manual profile refresh reacquires a lease instead of reusing expired editRef', () async {
    final fake = ProfileFake();
    final model = CommunityProfileController(fake, 'a' * 32);
    await model.load();
    fake.expiredEdits = true;
    await model.load();
    expect(model.error, isNull);
    expect(model.invalidated, false);
    expect(fake.reads, 2);
    model.dispose();
    await fake.events.close();
  });
  test('profile projection is bounded, narrow and deeply immutable', () {
    final source = profilePayload();
    final parsed = CommunityEditingProfile.parse(source);
    expect(parsed.revision, 7);
    expect(parsed.fields.containsKey('internalOnly'), isFalse);
    expect(
      () => parsed.fields['description'] = 'Changed',
      throwsUnsupportedError,
    );
    expect(
      () => (parsed.fields['externalContacts'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ((parsed.fields['activityWindows'] as List).first as Map)['days'] =
          [],
      throwsUnsupportedError,
    );
    expect(
      () =>
          (((parsed.fields['activityWindows'] as List).first as Map)['days']
                  as List)
              .clear(),
      throwsUnsupportedError,
    );
    (source['profile'] as Map)['description'] = 'Source mutation';
    expect(parsed.fields['description'], 'Original');
  });
  for (final mutate in <void Function(Map<String, Object?>)>[
    (v) => v['schemaVersion'] = 2,
    (v) => v['editRef'] = 'raw-account',
    (v) => v['profileRevision'] = -1,
    (v) => v['hasLogo'] = 'true',
    (v) => (v['profile'] as Map).remove('language'),
    (v) => (v['profile'] as Map)['description'] = 'x' * 8193,
    (v) => v['access'] = {
      'canEditProfile': false,
      'canEditLogo': false,
      'canEditBanner': false,
    },
  ]) {
    test('invalid editor wire cannot become a usable draft: $mutate', () {
      final source = profilePayload();
      mutate(source);
      expect(
        () => CommunityEditingProfile.parse(source),
        throwsFormatException,
      );
    });
  }
  test(
    'profile requires dedicated capability and explicit account context',
    () async {
      final absent = CommunityHarness();
      addTearDown(absent.close);
      await expectLater(
        absent.adapter.readProfile(targetRef: 'a' * 32),
        throwsA(isA<CommunityFailure>()),
      );
      expect(absent.requests, isEmpty);
      final host = CommunityHarness(
        capabilities: ['communities.profile'],
        responses: {'communities.profile': profilePayload()},
      );
      addTearDown(host.close);
      await host.adapter.readProfile(targetRef: 'a' * 32);
      expect(host.requests.last.name, 'communities.profile');
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
      });
      await host.adapter.readProfile(editRef: 'b' * 32);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'editRef': 'b' * 32,
      });
    },
  );
  test(
    'save bridge transmits intent, edit reference and changed fields only',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.profile'],
        responses: {
          'communities.saveProfile': {
            'schemaVersion': 1,
            'status': 'accepted',
            'profileRevision': 8,
          },
        },
      );
      addTearDown(host.close);
      final saved = await host.adapter.saveProfile('c' * 32, 'b' * 32, {
        'description': 'Changed',
      });
      expect(saved.status, 'accepted');
      expect(saved.revision, 8);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'requestId': 'c' * 32,
        'editRef': 'b' * 32,
        'changes': {'description': 'Changed'},
      });
    },
  );
  test('malformed save acknowledgement stays unknown', () async {
    final host = CommunityHarness(
      capabilities: ['communities.profile'],
      responses: {
        'communities.saveProfile': {'schemaVersion': 1, 'status': 'accepted'},
      },
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.saveProfile('c' * 32, 'b' * 32, {
        'description': 'Changed',
      })).status,
      'unknown',
    );
  });
  test(
    'draft update preserves other values and reverting a field clears dirty',
    () async {
      final fake = ProfileFake();
      final controller = CommunityProfileController(fake, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(fake.close);
      await controller.load();
      expect(controller.update('description', 'Changed'), isTrue);
      expect(controller.fields['language'], 'English');
      expect(controller.changes, {'description': 'Changed'});
      expect(controller.update('roleGroups', []), isFalse);
      expect(controller.update('code', 'B'), isFalse);
      controller.update('description', 'Original');
      expect(controller.dirty, isFalse);
      final days = ['mon'];
      controller.update('activityWindows', [
        {
          'days': days,
          'startTime': '10:00',
          'endTime': '12:00',
          'endsNextDay': false,
        },
      ]);
      days.add('tue');
      expect(
        ((controller.changes['activityWindows'] as List).first as Map)['days'],
        ['mon'],
      );
      controller.discard();
      expect(controller.dirty, isFalse);
    },
  );
  test(
    'successful save refreshes authoritative profile and becomes clean',
    () async {
      final fake = ProfileFake();
      final controller = CommunityProfileController(fake, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(fake.close);
      await controller.load();
      controller.update('description', 'Changed');
      await controller.save();
      expect(fake.writes, 1);
      expect(fake.reads, 2);
      expect(fake.sentChanges, {'description': 'Changed'});
      expect(fake.requestId, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(controller.fields['description'], 'Server normalized');
      expect(controller.profile!.revision, 8);
      expect(controller.dirty, isFalse);
      expect(controller.error, isNull);
    },
  );
  for (final result in [
    const CommunityProfileOutcome('unknown', error: 'outcomeUnknown'),
    const CommunityProfileOutcome('rejected', error: 'conflict'),
  ]) {
    test(
      '${result.status}/${result.error} retains draft and cannot auto-resend',
      () async {
        final fake = ProfileFake()..result = result;
        final controller = CommunityProfileController(fake, 'a' * 32);
        addTearDown(controller.dispose);
        addTearDown(fake.close);
        await controller.load();
        controller.update('description', 'Keep me');
        await controller.save();
        await controller.save();
        expect(fake.writes, 1);
        expect(controller.dirty, isTrue);
        expect(controller.fields['description'], 'Keep me');
        expect(controller.needsRefresh, isTrue);
        await controller.load();
        expect(fake.reads, 1);
        await controller.load(discardChanges: true);
        expect(fake.reads, 2);
        expect(controller.dirty, isFalse);
        expect(controller.needsRefresh, isFalse);
      },
    );
  }
  test('accepted save with failed refresh is not re-submittable', () async {
    final fake = ProfileFake()..failRefresh = true;
    final controller = CommunityProfileController(fake, 'a' * 32);
    addTearDown(controller.dispose);
    addTearDown(fake.close);
    await controller.load();
    controller.update('description', 'Changed');
    await controller.save();
    expect(controller.error, 'refreshAfterSave');
    expect(controller.dirty, isTrue);
    expect(controller.canSave, isFalse);
    await controller.save();
    expect(fake.writes, 1);
    fake.failRefresh = false;
    await controller.load(discardChanges: true);
    expect(controller.dirty, isFalse);
    expect(controller.profile!.revision, 8);
  });
  test(
    'insufficient permission blocks editing, account invalidation erases draft',
    () async {
      final fake = ProfileFake()..canEditProfile = false;
      final controller = CommunityProfileController(fake, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(fake.close);
      await controller.load();
      expect(controller.update('description', 'Forbidden'), isFalse);
      expect(controller.update('clearLogoImage', true), isTrue);
      fake.events.add(null);
      expect(controller.profile, isNull);
      expect(controller.changes, isEmpty);
      expect(controller.invalidated, isTrue);
      await controller.save();
      expect(fake.writes, 0);
    },
  );
  test(
    'late load after account change cannot restore private profile',
    () async {
      final fake = ProfileFake()
        ..pendingRead = Completer<CommunityEditingProfile>();
      final controller = CommunityProfileController(fake, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(fake.close);
      final pending = controller.load();
      fake.events.add(null);
      fake.pendingRead!.complete(
        CommunityEditingProfile.parse(profilePayload()),
      );
      await pending;
      expect(controller.profile, isNull);
      expect(controller.fields, isEmpty);
    },
  );
  test(
    'late save after account change cannot restore profile or refresh',
    () async {
      final fake = ProfileFake()
        ..pendingSave = Completer<CommunityProfileOutcome>();
      final controller = CommunityProfileController(fake, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(fake.close);
      await controller.load();
      controller.update('description', 'Private draft');
      final pending = controller.save();
      fake.events.add(null);
      fake.pendingSave!.complete(
        const CommunityProfileOutcome('accepted', revision: 8),
      );
      await pending;
      expect(controller.profile, isNull);
      expect(controller.changes, isEmpty);
      expect(fake.reads, 1);
    },
  );
}

final class ProfileFake implements CommunityProfilePort {
  final events = StreamController<void>.broadcast(sync: true);
  int reads = 0, writes = 0;
  bool failRefresh = false, canEditProfile = true, expiredEdits = false;
  String? requestId;
  Map<String, Object?>? sentChanges;
  CommunityProfileOutcome result = const CommunityProfileOutcome(
    'accepted',
    revision: 8,
  );
  Completer<CommunityEditingProfile>? pendingRead;
  Completer<CommunityProfileOutcome>? pendingSave;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) async {
    reads++;
    if (expiredEdits && editRef != null) {
      throw const CommunityFailure('refreshRequired');
    }
    if (pendingRead != null) return pendingRead!.future;
    if (reads > 1 && failRefresh) throw const CommunityFailure('unavailable');
    return CommunityEditingProfile.parse(
      profilePayload(
        revision: writes > 0 ? 8 : 7,
        description: writes > 0 ? 'Server normalized' : 'Original',
        canEditProfile: canEditProfile,
      ),
    );
  }

  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  ) async {
    writes++;
    this.requestId = requestId;
    sentChanges = changes;
    return pendingSave?.future ?? result;
  }

  Future<void> close() => events.close();
}
