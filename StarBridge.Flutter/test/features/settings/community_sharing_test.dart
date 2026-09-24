import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

const membershipTime = '2026-09-12T12:34:56.1234567+00:00';
CommunitySharingTarget target(String code, {String time = membershipTime}) =>
    CommunitySharingTarget(
      code: code,
      name: 'Organization $code',
      joinedAt: time,
    );

void main() {
  test('organization logo is optional and never part of sharing choices', () {
    for (final logo in [null, 'fixture-image']) {
      final targets = CommunitySharingTargets.fromJson({
        'schemaVersion': 2,
        'primaryFleetCode': null,
        'communities': [
          {
            'code': 'A',
            'name': 'Organization A',
            'joinedAt': membershipTime,
            'logoImageData': ?logo,
          },
        ],
      });
      expect(targets.communities.single.logoImageData, logo);
      expect(
        targets.communities.single.choice().toJson().containsKey(
          'logoImageData',
        ),
        isFalse,
      );
    }
  });
  test('exact membership timestamp survives settings and unrelated edits', () {
    final settings = LocalPrivacySettings.editorDefaults.copyWith(
      communities: [target('A').choice(fields: 3)],
    );
    final restored = LocalPrivacySettings.fromJson(
      (jsonDecode(jsonEncode(settings.toJson())) as Map)
          .cast<String, Object?>(),
    );
    expect(
      restored.copyWith(roomFields: 8).communities!.single.joinedAt,
      membershipTime,
    );
    expect(restored.communities!.single.fields, 3);
    expect(
      LocalPrivacySettings.editorDefaults.toJson().containsKey('communities'),
      isFalse,
    );
    expect(
      LocalPrivacySettings.editorDefaults
          .copyWith(communities: [])
          .toJson()['communities'],
      isEmpty,
    );
    expect(
      () => CommunitySharingScope.validate([
        target('A').choice(),
        target('a').choice(),
      ]),
      throwsFormatException,
    );
    expect(() => target('A').choice(fields: 32), throwsFormatException);
  });

  test('first confirmation binds only explicit primary; merely reading never grants', () async {
    final port = SharingFixture();
    final controller = LocalPrivacyController(port);
    await controller.refresh();
    expect(port.writes, 0);
    expect(controller.draft!.communities, isNull);
    expect(
      controller
          .bindCommunityChoices(
            controller.draft!,
            preserveExistingOrganizationChoice: false,
          )
          .communities,
      isEmpty,
      reason: 'First-wave main fleet is closed; new organization grants require individual confirmation.',
    );
    final restricted = controller.draft!.copyWith(
      fleetFields: 1,
      roomFields: 8,
      fleetAllMembersCanView: false,
      fleetAdministratorsCanView: true,
    );
    final bound = controller.bindCommunityChoices(restricted);
    expect(bound.communities!.single.code, 'A');
    expect(bound.communities!.single.fields, 1);
    expect(bound.communities!.single.administratorsCanView, isTrue);
    expect(bound.roomFields, 8);
    expect(port.writes, 0);
    controller.edit(bound);
    expect(controller.unconfirmedCommunities.map((t) => t.code), ['B']);
    await controller.save();
    controller.editCommunity(target('B').choice(fields: 2));
    expect(controller.draft!.communities!.map((s) => s.fields), [1, 2]);
    port.targets = CommunitySharingTargets(
      primaryFleetCode: 'B',
      communities: [target('B')],
    );
    await controller.refreshCommunityTargets();
    expect(
      controller
          .bindCommunityChoices(controller.draft!)
          .communities!
          .first
          .code,
      'A',
      reason: 'Primary changes never rebind saved grants.',
    );
    controller.dispose();
  });

  test(
    'rejoining is unconfirmed and unavailable targets cannot expand scope',
    () async {
      final port = SharingFixture()
        ..settings = LocalPrivacySettings.editorDefaults.copyWith(
          communities: [target('A').choice(fields: 15)],
        );
      final controller = LocalPrivacyController(port);
      await controller.refresh();
      port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A', time: '2026-09-13T12:34:56+00:00')],
      );
      await controller.refreshCommunityTargets();
      expect(controller.unconfirmedCommunities.single.code, 'A');
      controller.editCommunity(target('A').choice(fields: 1));
      expect(controller.dirty, isFalse);
      port.failTargets = true;
      await controller.refreshCommunityTargets();
      expect(controller.communityTargetsFailed, isTrue);
      expect(controller.unconfirmedCommunities, isEmpty);
      expect(port.writes, 0);
      controller.dispose();
    },
  );
}

class SharingFixture
    implements LocalPrivacyPort, PrivacyPublicationPort, CommunitySharingPort {
  final events = StreamController<void>.broadcast();
  LocalPrivacySettings settings = LocalPrivacySettings.editorDefaults;
  CommunitySharingTargets targets = CommunitySharingTargets(
    primaryFleetCode: 'A',
    communities: [target('A'), target('B')],
  );
  int revision = 1, writes = 0, applies = 0;
  bool failTargets = false, failSave = false;
  Object? targetFailure;
  @override
  bool get communitySharingSupported => true;
  @override
  bool get publicationSupported => true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() async {
    if (targetFailure case final failure?) throw failure;
    if (failTargets) throw StateError('Unavailable');
    return targets;
  }

  @override
  Future<LocalPrivacySnapshot> read() async =>
      LocalPrivacySnapshot(revision: revision, settings: settings);
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings value) async {
    if (failSave) throw StateError('Save failed');
    writes++;
    revision++;
    settings = value;
    return read();
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    if (action == 'apply') applies++;
    return const PrivacyPublicationView('applied', firstUseRequired: false);
  }

  @override
  Future<void> close() => events.close();
}
