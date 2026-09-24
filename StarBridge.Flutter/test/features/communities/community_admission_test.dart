import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_admission_controller.dart';
import 'package:starbridge_flutter/features/communities/community_invite_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

class AdmissionInvites implements CommunityInvitePort {
  final events = StreamController<void>.broadcast(sync: true);
  final calls = <String>[];
  int previews = 0;
  CommunityInviteOutcome result = const CommunityInviteOutcome('accepted');
  Completer<CommunityInvitePreview>? holdPreview;
  Completer<CommunityInviteOutcome>? holdAccept;
  DateTime? expiry;
  bool already = false;
  bool conflict = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<CommunityInvitePreview> previewInvite(String code) async {
    previews++;
    if (code == 'bad') throw const CommunityFailure('inviteInvalid');
    return holdPreview == null ? value : holdPreview!.future;
  }

  CommunityInvitePreview get value => CommunityInvitePreview(
    previewRef: '1234567890abcdef1234567890abcdef',
    name: '组织 B',
    code: 'B',
    commander: 'Owner',
    memberCount: 10,
    joinPolicy: 'Open',
    expiresAt: expiry,
    remainingUses: 2,
    alreadyMember: already,
    membershipConflict: conflict,
  );
  @override
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  ) async {
    expect(requestId, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(previewRef, value.previewRef);
    calls.add('accept');
    return holdAccept == null ? result : holdAccept!.future;
  }
}

class AdmissionPrivacy implements LocalPrivacyPort {
  AdmissionPrivacy(this.calls);
  final List<String> calls;
  final events = StreamController<void>.broadcast(sync: true);
  LocalPrivacySnapshot snapshot = const LocalPrivacySnapshot(revision: 0);
  Completer<LocalPrivacySnapshot>? holdRead, holdSave;
  bool failSave = false, mismatchSave = false, closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<LocalPrivacySnapshot> read() async {
    calls.add('read');
    return holdRead == null ? snapshot : holdRead!.future;
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    calls.add('save');
    if (failSave) throw StateError('save failed');
    if (holdSave != null) return holdSave!.future;
    if (mismatchSave) return snapshot;
    return snapshot = LocalPrivacySnapshot(
      revision: snapshot.revision + 1,
      settings: settings,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late AdmissionInvites invites;
  late AdmissionPrivacy privacy;
  late CommunityAdmissionController model;
  var now = DateTime.utc(2026, 9, 7);
  setUp(() {
    now = DateTime.utc(2026, 9, 7);
    invites = AdmissionInvites();
    privacy = AdmissionPrivacy(invites.calls);
    model = CommunityAdmissionController(invites, privacy, now: () => now);
  });
  tearDown(() async {
    model.dispose();
    await invites.events.close();
    await privacy.events.close();
  });
  Future<void> review() async {
    await model.verify('code');
    await model.reviewSharing();
  }

  test('S2 membership conflict retains preview without reading or saving sharing or joining', () async {
    invites.conflict = true;
    await model.verify('code');
    expect(model.preview!.membershipConflict, isTrue);
    await model.reviewSharing();
    model.acknowledge(true);
    await model.join();
    expect(model.canJoin, isFalse);
    expect(model.sharing, isFalse);
    expect(invites.calls, isEmpty);
  });

  test(
    'preview and defaults are not consent; save confirms before one join',
    () async {
      await model.verify('code');
      expect(invites.calls, isEmpty);
      await model.join();
      await model.reviewSharing();
      await model.join();
      expect(invites.calls, ['read']);
      model.acknowledge(true);
      await model.join();
      await model.join();
      expect(invites.calls, ['read', 'save', 'accept']);
      expect(model.outcome?.status, 'accepted');
    },
  );
  test(
    'editing clears acknowledgement; room axis and groups stay untouched',
    () async {
      privacy.snapshot = LocalPrivacySnapshot(
        revision: 2,
        settings: LocalPrivacySettings(
          publicationEnabled: true,
          fleetFields: 7,
          fleetAdministratorsCanView: true,
          fleetAllMembersCanView: false,
          fleetVisibilityGroupIds: ['group-a'],
          roomFields: 5,
          roomAllMembersCanView: false,
        ),
      );
      await review();
      model.acknowledge(true);
      model.edit(LocalPrivacySettings.editorDefaults.copyWith(fleetFields: 8));
      expect(model.canJoin, isFalse);
      expect(model.draft!.roomFields, 5);
      expect(model.draft!.roomAllMembersCanView, isFalse);
      expect(model.draft!.fleetVisibilityGroupIds, ['group-a']);
      model.acknowledge(true);
      await model.join();
      expect(privacy.snapshot.settings!.fleetFields, 8);
    },
  );
  test('unchanged saved choices do not produce a redundant write', () async {
    privacy.snapshot = LocalPrivacySnapshot(
      revision: 3,
      settings: LocalPrivacySettings.editorDefaults,
    );
    await review();
    model.acknowledge(true);
    await model.join();
    expect(invites.calls, ['read', 'accept']);
  });
  for (final mismatch in [false, true]) {
    test(
      'unconfirmed privacy save blocks admission (mismatch=$mismatch)',
      () async {
        privacy.failSave = !mismatch;
        privacy.mismatchSave = mismatch;
        await review();
        model.acknowledge(true);
        await model.join();
        expect(model.error, 'privacySaveFailed');
        expect(invites.calls, ['read', 'save']);
        expect(model.draft, isNotNull);
      },
    );
  }
  test(
    'save conflict reload preserves choices but uses latest unrelated settings',
    () async {
      await review();
      model.edit(model.draft!.copyWith(fleetFields: 3));
      privacy.failSave = true;
      model.acknowledge(true);
      await model.join();
      privacy.snapshot = LocalPrivacySnapshot(
        revision: 5,
        settings: LocalPrivacySettings.editorDefaults.copyWith(roomFields: 2),
      );
      privacy.failSave = false;
      await model.reviewSharing();
      expect(model.draft!.fleetFields, 3);
      expect(model.draft!.roomFields, 2);
      expect(model.canJoin, isFalse);
      model.acknowledge(true);
      await model.join();
      expect(model.outcome?.status, 'accepted');
    },
  );
  test('changed invite clears old preview and unsaved choices', () async {
    await review();
    model.acknowledge(true);
    model.clearPreview();
    await model.join();
    expect(model.preview, isNull);
    expect(model.draft, isNull);
    expect(invites.calls, ['read']);
    await model.verify('bad');
    expect(model.error, 'inviteInvalid');
  });
  test('already a member never saves settings or joins', () async {
    invites.already = true;
    await review();
    model.acknowledge(true);
    await model.join();
    expect(invites.calls, ['read']);
  });
  test('expiry at boundary disables joining', () async {
    invites.expiry = now;
    await review();
    expect(model.expired, isTrue);
    expect(invites.calls, isEmpty);
  });
  test('expiry during persistence does not send a join after save', () async {
    invites.expiry = now.add(const Duration(seconds: 1));
    await review();
    privacy.holdSave = Completer();
    model.acknowledge(true);
    final joining = model.join();
    now = now.add(const Duration(seconds: 2));
    privacy.holdSave!.complete(
      LocalPrivacySnapshot(revision: 1, settings: model.draft),
    );
    await joining;
    expect(model.error, 'inviteInvalid');
    expect(model.savedChoices, isTrue);
    expect(invites.calls, ['read', 'save']);
  });
  test(
    'unknown outcome locks flow against resending or new previews',
    () async {
      invites.result = const CommunityInviteOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      await review();
      model.acknowledge(true);
      await model.join();
      await model.join();
      await model.verify('other');
      model.clearPreview();
      expect(invites.previews, 1);
      expect(invites.calls.where((c) => c == 'accept'), hasLength(1));
      expect(model.outcome?.status, 'unknown');
    },
  );
  test('duplicate click while save is pending cannot send twice', () async {
    await review();
    privacy.holdSave = Completer();
    model.acknowledge(true);
    final joining = model.join();
    await model.join();
    privacy.holdSave!.complete(
      LocalPrivacySnapshot(revision: 1, settings: model.draft),
    );
    await joining;
    expect(invites.calls, ['read', 'save', 'accept']);
  });
  test('account change discards a late preview', () async {
    invites.holdPreview = Completer();
    final pending = model.verify('code');
    invites.events.add(null);
    invites.holdPreview!.complete(invites.value);
    await pending;
    expect(model.invalidated, isTrue);
    expect(model.preview, isNull);
  });
  test('account change during settings save never joins', () async {
    await review();
    privacy.holdSave = Completer();
    model.acknowledge(true);
    final pending = model.join();
    final draft = model.draft;
    privacy.events.add(null);
    privacy.holdSave!.complete(
      LocalPrivacySnapshot(revision: 1, settings: draft),
    );
    await pending;
    expect(model.draft, isNull);
    expect(invites.calls, ['read', 'save']);
  });
}
