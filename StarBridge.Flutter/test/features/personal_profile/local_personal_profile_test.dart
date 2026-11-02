import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  test('a cold-start owner race on the local read is retried, not shown as unavailable', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.pendingLocalReadErrors.add('profile_local.account_changed');
    final snapshot = await h.port.read();
    expect(snapshot.availability, PersonalProfileAvailability.available);
    expect(
      h.connection.requests.where((r) => r.name == 'personalProfile.localRead'),
      hasLength(2),
    );
  });
  test(
    'a persistent local owner mismatch stops after bounded retries',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.localReadError = 'profile_local.account_changed';
      final snapshot = await h.port.read();
      expect(snapshot.availability, PersonalProfileAvailability.unavailable);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.localRead',
        ),
        hasLength(
          1 + BridgeLocalPersonalProfile.ownerPendingRetryDelays.length,
        ),
      );
    },
  );
  test('other local read failures are not retried', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.localReadError = 'profile_local.invalid_request';
    await h.port.read();
    expect(
      h.connection.requests.where((r) => r.name == 'personalProfile.localRead'),
      hasLength(1),
    );
  });
  test(
    'retry after partial rename cannot overwrite a newer device name',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final draft = edit(await h.port.read());
      h.connection.failSave = true;
      final partial = await h.port.save(draft);
      expect(partial.failureKey, 'profile.callsign.localPending');
      expect(partial.requiresReload, isTrue);
      final requestsAfterPartial = h.connection.requests.length;
      h.connection.callSign = 'Newer device name';
      h.connection.failSave = false;
      final retry = await h.port.save(draft);
      expect(retry.failureKey, 'profile.error.refreshBeforeSave');
      expect(h.connection.callSign, 'Newer device name');
      expect(h.connection.content, isNull);
      expect(h.connection.requests.length, requestsAfterPartial);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.localSave',
        ),
        hasLength(1),
      );
    },
  );
  test(
    'missing rename capability rejects combined edit before page write',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.session.acceptHostCapabilities([
        'personalProfile.presentation.write.v1',
      ]);
      h.remote.presentation = PersonalProfilePresentation.fromProfile({
        'revision': 4,
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'content': {},
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'default',
          },
        },
      });
      final page = await h.port.read();
      final result = await h.port.save(edit(page));
      expect(result.failureKey, 'profile.callsign.unavailable');
      expect(h.remote.writes, 0);
      expect(
        h.connection.requests.where(
          (r) =>
              r.name == 'personalProfile.localSave' ||
              r.name == 'account.updateCallSign',
        ),
        isEmpty,
      );
      expect(h.connection.content, isNull);
      // Editing the page without renaming remains available.
      expect(
        (await h.port.save(edit(page, callSign: page.callSign))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.remote.writes, 1);
    },
  );
  test('versioned page recovers only after a fresh successful read', () async {
    final h = Harness();
    addTearDown(h.close);
    h.session.acceptHostCapabilities([
      'account.callSign',
      'personalProfile.presentation.write.v1',
    ]);
    h.remote.available = false;
    final unavailable = await h.port.read();
    expect(
      (await h.port.save(edit(unavailable, callSign: unavailable.callSign)))
          .outcome,
      PersonalProfileActionOutcome.rejected,
    );
    h.remote.available = true;
    h.remote.presentation = PersonalProfilePresentation.fromProfile({
      'revision': 4,
      'avatarStyle': 0,
      'wallpaperId': 'none',
      'content': {},
      'presentation': {
        'schemaVersion': 1,
        'sourceVersion': 'a' * 64,
        'origins': {
          for (final group in PersonalProfilePresentation.groups)
            group: 'default',
        },
      },
    });
    expect(
      (await h.port.save(edit(unavailable, callSign: unavailable.callSign)))
          .outcome,
      PersonalProfileActionOutcome.rejected,
    );
    expect(h.remote.writes, 0);
    final refreshed = await h.port.read();
    expect(
      (await h.port.save(edit(refreshed, callSign: refreshed.callSign)))
          .outcome,
      PersonalProfileActionOutcome.completed,
    );
    expect(h.remote.writes, 1);
    expect(h.connection.revision, 1);
  });
  for (final changedScope in ['subject', 'authority', 'environment']) {
    test('observed page authority does not leak across $changedScope', () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.presentation = PersonalProfilePresentation.fromProfile({
        'revision': 4,
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'content': {},
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'default',
          },
        },
      });
      final oldPage = await h.port.read();
      h.session.advanceGeneration(8);
      h.connection.generation = 8;
      if (changedScope == 'subject') h.connection.subject = 'other-owner';
      if (changedScope == 'authority') h.connection.authority = 'other-issuer';
      if (changedScope == 'environment') {
        h.connection.environment = 'other-test';
      }
      h.remote.presentation = null;
      h.remote.available = false;
      expect(
        (await h.port.save(edit(oldPage, callSign: oldPage.callSign))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      // An older Host still owns its local-only page. Another owner's observed
      // versioned page must not silently change that contract.
      final otherPage = await h.port.read();
      expect(
        (await h.port.save(edit(otherPage, callSign: otherPage.callSign)))
            .outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.remote.writes, 0);
      expect(
        h.connection.requests
            .where((r) => r.name == 'personalProfile.localSave')
            .single
            .accountContext
            ?.subject,
        h.connection.subject,
      );
    });
  }
  for (final throwsRead in [false, true]) {
    test(
      'versioned Host cold read failure cannot become local success: $throwsRead',
      () async {
        final h = Harness();
        addTearDown(h.close);
        h.session.acceptHostCapabilities([
          'account.callSign',
          'personalProfile.presentation.write.v1',
        ]);
        h.remote.available = false;
        if (throwsRead) h.remote.readError = StateError('Synthetic outage');
        final page = await h.port.read();
        expect(page.local!.remoteAvailable, isFalse);
        final result = await h.port.save(edit(page, callSign: page.callSign));
        expect(result.outcome, PersonalProfileActionOutcome.rejected);
        expect(result.failureKey, 'profile.error.refreshBeforeSave');
        expect(h.connection.content, isNull);
        expect(h.remote.writes, 0);
        expect(
          h.connection.requests.where(
            (r) => r.name == 'personalProfile.localSave',
          ),
          isEmpty,
        );
      },
    );
  }
  test(
    'known account-level page cannot fall back to local save after read outage',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.presentation = PersonalProfilePresentation.fromProfile({
        'revision': 4,
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'content': {},
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'default',
          },
        },
      });
      await h.port.read();
      h.remote.available = false;
      final cached = await h.port.read();
      final result = await h.port.save(edit(cached, callSign: cached.callSign));
      expect(result.outcome, PersonalProfileActionOutcome.rejected);
      expect(result.failureKey, 'profile.error.refreshBeforeSave');
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.localSave',
        ),
        isEmpty,
      );
      expect(h.remote.writes, 0);
      expect(h.connection.content, isNull);
    },
  );
  for (final origin in [
    'custom',
    'linkedLegacy',
    'imported',
    'default',
    'unknown',
  ]) {
    test(
      'page reread respects $origin without rewriting local history',
      () async {
        final h = Harness();
        addTearDown(h.close);
        final before = await h.port.read();
        expect(
          (await h.port.save(edit(before, callSign: before.callSign))).outcome,
          PersonalProfileActionOutcome.completed,
        );
        final oldContent = h.connection.content;
        final oldRevision = h.connection.revision;
        h.remote.about = '';
        h.remote.presentation = PersonalProfilePresentation.fromProfile({
          'revision': 4,
          'avatarStyle': 0,
          'wallpaperId': 'none',
          'content': {},
          'presentation': {
            'schemaVersion': 1,
            'sourceVersion': 'a' * 64,
            'origins': {
              for (final group in PersonalProfilePresentation.groups)
                group: origin,
            },
          },
        });
        final reread = await h.port.read();
        expect(reread.about, origin == 'unknown' ? 'Local introduction' : '');
        expect(identical(h.connection.content, oldContent), isTrue);
        expect(h.connection.revision, oldRevision);
        expect(h.remote.writes, 0);
      },
    );
  }
  for (final mode in ['saved', 'remote-failed', 'local-failed']) {
    test('versioned page coordinates account and local save: $mode', () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.presentation = PersonalProfilePresentation.fromProfile({
        'revision': 4,
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'content': {},
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'default',
          },
        },
      });
      h.remote.pageOutcome = mode == 'remote-failed'
          ? PersonalProfileActionOutcome.failed
          : PersonalProfileActionOutcome.completed;
      h.connection.failSave = mode == 'local-failed';
      final profile = await h.port.read();
      final change = PersonalProfileEdit(
        callSign: profile.callSign,
        about: 'Explicit new intro',
        avatarStyle: profile.avatarStyle,
        wallpaperId: profile.wallpaperId,
        visibility: profile.visibility,
        moduleLayout: profile.moduleLayout,
      );
      final result = await h.port.save(change);
      expect(
        result.outcome,
        mode == 'saved'
            ? PersonalProfileActionOutcome.completed
            : PersonalProfileActionOutcome.failed,
      );
      if (mode == 'local-failed') expect(result.requiresReload, isTrue);
      expect(h.remote.pageGroups!.keys, ['introduction']);
      expect(h.remote.writes, 1);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.localSave',
        ),
        hasLength(mode == 'remote-failed' ? 0 : 1),
      );
      expect(
        (await h.port.save(change)).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(h.remote.writes, 1);
    });
  }
  test(
    'SCM profile avatar takes priority over stale account chrome avatar',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.avatarImageData = 'data:image/png;base64,account-default';
      h.remote.avatarImageData = 'data:image/png;base64,inherited-profile';
      final profile = await h.port.read();
      expect(profile.avatarImageData, h.remote.avatarImageData);
      expect(h.connection.content, isNull);
      expect(h.remote.writes, 0);
    },
  );
  test(
    'legacy avatar authority and SCM missing-avatar fallback stay unchanged',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.avatarImageData = 'data:image/png;base64,account-current';
      expect(
        (await h.port.read()).avatarImageData,
        h.connection.avatarImageData,
      );
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.remote.avatarImageData = 'data:image/png;base64,older-profile';
      expect(
        (await h.port.read()).avatarImageData,
        h.connection.avatarImageData,
      );
    },
  );
  test(
    'SCM offline editor saves other local fields but cannot rename the account',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.remote.available = false;
      h.connection.displayName = 'SCM Display';
      final profile = await h.port.read();
      expect(
        (await h.port.save(edit(profile))).failureKey,
        'profile.callsign.unavailable',
      );
      expect(h.connection.content, isNull);
      expect(
        (await h.port.save(edit(profile, callSign: profile.callSign))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.connection.content!['introduction'], 'Local introduction');
      expect(
        h.connection.requests.where((r) => r.name == 'account.updateCallSign'),
        isEmpty,
      );
    },
  );
  test('SCM call sign is Java-owned even when the local page retains an older name', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.save(edit(await h.port.read()));
    h.connection.callSign = 'Other device';
    final after = await h.port.read();
    expect(after.callSign, 'Other device');
    expect(h.connection.content!['callSign'], 'Local call sign');
    expect(after.about, 'Local introduction');
    expect(after.gameHandle, 'Aster-Lin');
  });
  test('SCM rename syncs only call sign before local save, not whole remote profile', () async {
    final h = Harness();
    addTearDown(h.close);
    final before = await h.port.read();
    final saved = await h.port.save(edit(before));
    expect(saved.outcome, PersonalProfileActionOutcome.completed);
    final write = h.connection.requests.singleWhere(
      (r) => r.name == 'account.updateCallSign',
    );
    expect(write.payload, {
      'schemaVersion': 1,
      'expectedCallSign': 'Aster Lin',
      'callSign': 'Local call sign',
    });
    expect(write.accountContext?.subject, 'owner');
    expect(write.sessionGeneration, 7);
    expect(
      h.connection.requests.indexOf(write),
      lessThan(
        h.connection.requests.indexWhere(
          (r) => r.name == 'personalProfile.localSave',
        ),
      ),
    );
    expect(h.remote.writes, 0);
  });
  test(
    'rename conflict or unavailable write leaves local draft unsaved',
    () async {
      for (final error in [
        'account.callsign_conflict',
        'account.callsign_unavailable',
        'personal_profile.write_forbidden',
        'account.callsign_unconfirmed',
        'bridge.disconnected',
      ]) {
        final h = Harness();
        addTearDown(h.close);
        h.connection.callSignError = error;
        final draft = edit(await h.port.read());
        final result = await h.port.save(draft);
        expect(result.outcome, PersonalProfileActionOutcome.failed);
        expect(result.requiresReload, isTrue);
        final requestCount = h.connection.requests.length;
        expect((await h.port.save(draft)).requiresReload, isTrue);
        expect(h.connection.requests.length, requestCount);
        expect(h.connection.content, isNull);
        expect(
          h.connection.requests.where(
            (r) => r.name == 'personalProfile.localSave',
          ),
          isEmpty,
        );
      }
    },
  );
  test(
    'partial rename requires fresh read before an explicit local retry',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final before = await h.port.read();
      h.connection.failSave = true;
      final result = await h.port.save(edit(before));
      expect(result.failureKey, 'profile.callsign.localPending');
      expect(result.requiresReload, isTrue);
      expect(h.connection.callSign, 'Local call sign');
      expect(h.connection.content, isNull);
      h.connection.failSave = false;
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      final refreshed = await h.port.read();
      expect(refreshed.callSign, 'Local call sign');
      expect(
        (await h.port.save(edit(refreshed))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(
        h.connection.requests.where((r) => r.name == 'account.updateCallSign'),
        hasLength(1),
      );
      expect(h.connection.callSign, 'Local call sign');
      expect((await h.port.read()).callSign, 'Local call sign');
    },
  );
  test(
    'missing call sign capability does not fall back to local account rename',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.session.acceptHostCapabilities([]);
      expect(
        (await h.port.save(edit(await h.port.read()))).failureKey,
        'profile.callsign.unavailable',
      );
      expect(h.connection.content, isNull);
    },
  );
  test('completed import change reloads selected presentation without changing SCM identity or inventory', () async {
    final h = Harness();
    addTearDown(h.close);
    final before = await h.port.read();
    final inventory = h.hangar.snapshot;
    h.connection.content = {
      'callSign': 'Imported call sign',
      'introduction': 'Retained introduction',
      'avatarStyle': 0,
      'wallpaperId': 'none',
      'favoriteShipIds': <String>[],
      'modules': [
        {'id': 'skilled-roles', 'span': 2, 'isVisible': false, 'position': -1},
      ],
      'playStyle': {
        'roles': ['旧版岗位'],
        'support': ['旧支援'],
        'interests': ['兴趣一', '兴趣二', '兴趣三', '兴趣四'],
      },
    };
    h.connection.revision = 1;
    h.connection.callSign = 'Imported call sign';
    h.remote.importedSnapshot = projectLocalProfile(
      await h.remote.source.read(),
      null,
      inventory,
      null,
      legacyAccount: true,
      accountAvatarImageData: 'data:image/png;base64,synthetic-imported-avatar',
    );
    var invalidated = 0;
    final subscription = h.port.changes.listen((_) => invalidated++);
    addTearDown(subscription.cancel);
    h.connection.stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'personalProfile.changed',
        'sessionGeneration': 7,
        'sequence': 1,
        'payload': {'schemaVersion': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final after = await h.port.read();
    expect(invalidated, 1);
    expect(after.callSign, 'Imported call sign');
    expect(
      after.avatarImageData,
      'data:image/png;base64,synthetic-imported-avatar',
    );
    expect(after.gameHandle, before.gameHandle);
    expect(after.roles.single.displayLabel, '旧版岗位');
    expect(after.participationInterests.length, 4);
    expect(identical(h.hangar.snapshot, inventory), isTrue);
    expect(h.remote.writes, 0);
    expect(
      h.connection.requests.where((r) => r.name == 'personalProfile.localSave'),
      isEmpty,
    );
  });
  test(
    'legacy save synchronizes only background after local persistence',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.background = 'other';
      final result = await h.port.save(edit(await h.port.read()));
      expect(result.outcome, PersonalProfileActionOutcome.completed);
      expect(h.connection.background, 'none');
      final saves = h.connection.requests
          .where((r) => r.name == 'personalProfile.saveBackground')
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.payload, {
        'schemaVersion': 1,
        'expectedRevision': 4,
        'wallpaperId': 'none',
      });
      expect(
        h.connection.requests.indexOf(saves.single),
        greaterThan(
          h.connection.requests.indexWhere(
            (r) => r.name == 'personalProfile.localSave',
          ),
        ),
      );
      expect(h.connection.content!['introduction'], 'Local introduction');
      expect(h.remote.writes, 0);
    },
  );
  test(
    'background sync failure retains local save and reports partial result',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.background = 'other';
      h.connection.backgroundError = 'profile.background_conflict';
      final result = await h.port.save(edit(await h.port.read()));
      expect(result.outcome, PersonalProfileActionOutcome.failed);
      expect(result.failureKey, 'profile.local.backgroundPending');
      expect(h.connection.content!['wallpaperId'], 'none');
      expect(h.connection.revision, 1);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.saveBackground',
        ),
        isEmpty,
      );
      expect(h.remote.writes, 0);
    },
  );
  test('failed local save never publishes background', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.state = 'legacySignedIn';
    h.connection.authority = 'starbridge-relay-test';
    h.connection.failSave = true;
    await h.port.save(edit(await h.port.read()));
    expect(
      h.connection.requests.where(
        (r) => r.name == 'personalProfile.saveBackground',
      ),
      isEmpty,
    );
  });
  test(
    'background conflict never repeats publication and local content survives',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.background = 'other';
      h.connection.backgroundWriteError = 'profile.background_conflict';
      final result = await h.port.save(edit(await h.port.read()));
      expect(result.failureKey, 'profile.local.backgroundPending');
      expect(
        h.connection.requests.where(
          (r) => r.name == 'personalProfile.saveBackground',
        ),
        hasLength(1),
      );
      expect(h.connection.background, 'other');
      expect(h.connection.revision, 1);
      expect((await h.port.read()).wallpaperId, 'none');
    },
  );
  test(
    'account invalidation while checking background cannot save either target',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.invalidateBackgroundRead = true;
      final result = await h.port.save(edit(await h.port.read()));
      expect(result.outcome, PersonalProfileActionOutcome.rejected);
      expect(
        h.connection.requests.where(
          (r) =>
              r.name == 'personalProfile.localSave' ||
              r.name == 'personalProfile.saveBackground',
        ),
        isEmpty,
      );
    },
  );
  test(
    'SCM local editor does not fall back to legacy background writes',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.port.save(edit(await h.port.read()));
      expect(
        h.connection.requests.where((r) => r.name.endsWith('Background')),
        isEmpty,
      );
      expect(h.remote.writes, 0);
    },
  );
  test('visibility saves only audience and rejects a lease after rereading the profile', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.read();
    final state = await h.port.readVisibility();
    final result = await h.port.saveVisibility(
      state,
      PersonalProfileVisibility.friendsFleetAndOrganizations,
    );
    expect(
      result.visibility,
      PersonalProfileVisibility.friendsFleetAndOrganizations,
    );
    expect(h.connection.content, isNull);
    expect(h.remote.writes, 0);
    final save = h.connection.requests.last;
    expect(save.name, 'personalProfile.saveVisibility');
    expect(save.payload.keys.toSet(), {
      'schemaVersion',
      'expectedRevision',
      'visibility',
    });
    h.connection.stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'personalProfile.changed',
        'sessionGeneration': 7,
        'sequence': 1,
        'payload': {'schemaVersion': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await h.port.read();
    final count = h.connection.requests.length;
    await expectLater(
      h.port.saveVisibility(result, PersonalProfileVisibility.everyone),
      throwsStateError,
    );
    expect(h.connection.requests.length, count);
  });
  test('SCM visibility keeps Java audience and refuses unsupported organization scope', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.availableVisibilities = [
      'public',
      'friendsAndMainFleet',
      'friendsOnly',
      'private',
    ];
    await h.port.read();
    final state = await h.port.readVisibility();
    final before = h.connection.requests.length;
    await expectLater(
      h.port.saveVisibility(
        state,
        PersonalProfileVisibility.friendsFleetAndOrganizations,
      ),
      throwsStateError,
    );
    expect(h.connection.requests.length, before);
    final result = await h.port.saveVisibility(
      state,
      PersonalProfileVisibility.friendsAndMainFleet,
    );
    expect(result.visibility, PersonalProfileVisibility.friendsAndMainFleet);
    expect(
      h.connection.requests.last.payload['visibility'],
      'friendsAndMainFleet',
    );
    expect(h.remote.writes, 0);
    for (final invalid in <List<String>>[
      ['public', 'unknown', 'private'],
      [],
      ['private', 'private'],
      ['public'],
    ]) {
      h.connection.availableVisibilities = invalid;
      await expectLater(h.port.readVisibility(), throwsFormatException);
    }
  });
  test('local profile projects the most recently added current ship', () async {
    final h = Harness();
    addTearDown(h.close);
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 2, 1);
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 2,
      savedAt: DateTime.utc(2026, 3, 1),
      ships: [
        LocalHangarShip(id: shipA, title: 'Older ship', addedAt: older),
        LocalHangarShip(
          id: shipB,
          title: 'Newer ship',
          addedAt: newer,
          imageAsset: 'assets/ships/catalog-carrack.jpg',
        ),
        const LocalHangarShip(id: 'unknown-date', title: 'Undated ship'),
      ],
      formerShips: [
        LocalHangarShip(
          id: 'former',
          title: 'Former ship',
          addedAt: DateTime.utc(2026, 4, 1),
        ),
      ],
    );
    final actual = (await h.port.read()).hangarSummary;
    expect(actual.recentlyAddedShip?.runtimeId, shipB);
    expect(
      actual.recentlyAddedShipImageAsset,
      'assets/ships/catalog-carrack.jpg',
    );
    expect(
      actual.recentlyAddedAtLabel,
      newer.toLocal().toString().split(' ').first,
    );
    expect(actual.shipCount, 3);
    expect(h.remote.writes, 0);
    expect(h.connection.content, isNull);
  });
  test(
    'local recent ship never borrows remote history or the save time',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.hangar.snapshot = LocalHangarSnapshot(
        revision: 2,
        savedAt: DateTime.utc(2026, 3, 1),
        ships: const [LocalHangarShip(id: shipA, title: 'Undated ship')],
      );
      var actual = (await h.port.read()).hangarSummary;
      expect(actual.recentlyAddedShip, isNull);
      expect(actual.recentlyAddedAtLabel, isEmpty);
      h.hangar.snapshot = LocalHangarSnapshot(
        revision: 3,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Unknown legacy time',
            addedAt: DateTime.utc(1),
          ),
        ],
      );
      actual = (await h.port.read()).hangarSummary;
      expect(actual.shipCount, 1);
      expect(actual.recentlyAddedShip, isNull);
      expect(actual.recentlyAddedAtLabel, isEmpty);
      h.hangar.snapshot = const LocalHangarSnapshot(revision: 3, ships: []);
      actual = (await h.port.read()).hangarSummary;
      expect(actual.recentlyAddedShip, isNull);
      expect(actual.shipCount, 0);
    },
  );
  testWidgets(
    'owner three-cell overview renders recent inventory without saving',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      h.hangar.snapshot = LocalHangarSnapshot(
        revision: 2,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Recently admitted fixture',
            addedAt: DateTime.utc(2026, 2, 1),
          ),
        ],
      );
      await tester.pumpWidget(
        StarBridgeApp(
          composition: AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            accountPort: InMemoryAccountAdapter.forReview(
              AccountReviewState.signedIn,
            ),
            personalProfilePort: h.port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('profile-hangar-recent-ship-panel'));
      await tester.ensureVisible(panel);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.text('Recently admitted fixture'),
        ),
        findsOneWidget,
      );
      expect(h.connection.content, isNull);
      expect(h.remote.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
    },
  );
  test('former ownership and favorite choices retain every instance even when its model is owned', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.save(edit(await h.port.read(), ids: [shipA]));
    final before = h.hangar.snapshot.ships;
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 2,
      ships: [before[1]],
      formerShips: [before[0]],
    );
    var profile = await h.port.read();
    expect(profile.favoriteShips.single.formerlyOwned, isTrue);
    expect(profile.local!.choices.length, 2);
    expect(profile.hangarSummary.shipCount, 1);
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 3,
      ships: [],
      formerShips: before,
    );
    profile = await h.port.read();
    expect(profile.favoriteShips.single.identity.runtimeId, shipA);
    expect(profile.favoriteShips.single.formerlyOwned, isTrue);
    expect(profile.local!.choices.length, 2);
    expect(profile.local!.choices.every((s) => s.formerlyOwned), isTrue);
    expect(profile.hangarSummary.shipCount, 0);
    expect(profile.hangarSummary.unresolvedFavoriteCount, 0);
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 4,
      ships: [before[1]],
      formerShips: [before[0]],
    );
    expect((await h.port.read()).favoriteShips.single.formerlyOwned, isTrue);
  });
  test('S2 empty defaults inherit old data without overwriting edits or explicit clears', () async {
    final remote = await InMemoryPersonalProfileAdapter.forReview(
      signedIn: true,
    ).read();
    final content = <String, Object?>{
      'callSign': 'Local name',
      'introduction': '',
      'avatarStyle': 1,
      'wallpaperId': 'local-wallpaper',
      'favoriteShipIds': <String>[],
      'modules': [
        {
          'id': 'favorite-ships',
          'span': 3,
          'isVisible': true,
          'position': 0,
          'favoriteShipIds': <String>[],
        },
      ],
    };
    final inherited = projectLocalProfile(
      remote,
      content,
      null,
      null,
      legacyAccount: true,
    );
    expect(inherited.about, remote.about);
    expect(inherited.favoriteShips.length, remote.favoriteShips.length);
    expect(inherited.callSign, 'Local name');
    expect(inherited.wallpaperId, 'local-wallpaper');
    expect(content['introduction'], '');
    final edited = projectLocalProfile(
      remote,
      {...content, 'introduction': 'My edit'},
      null,
      null,
      legacyAccount: true,
    );
    expect(edited.about, 'My edit');
    final cleared = projectLocalProfile(
      remote,
      {...content, 'preserveEmptyFields': true},
      null,
      null,
      legacyAccount: true,
    );
    expect(cleared.about, '');
    expect(cleared.favoriteShips, isEmpty);
  });
  test(
    'S2 local save remains available while the optional Relay read fails',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.displayName = 'Legacy Commander';
      h.connection.avatarImageData = 'data:image/png;base64,account-photo';
      h.remote.readError = StateError('Relay unavailable');
      await h.port.save(edit(await h.port.read(), ids: [shipA]));
      final profile = await h.port.read();
      expect(profile.favoriteShips.length, 1);
      expect(profile.avatarImageData, h.connection.avatarImageData);
      expect(h.connection.content!.containsKey('avatarImageData'), isFalse);
      expect(h.connection.revision, 1);
      expect(h.remote.reads, 2);
      expect(h.remote.writes, 0);
    },
  );
  test(
    'S2 profile retains remote data when the new local hangar is absent',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.hangar.snapshot = const LocalHangarSnapshot(revision: 0, ships: []);
      final expected = await h.remote.source.read();
      final actual = await h.port.read();
      expect(actual.about, expected.about);
      expect(actual.gameplayMinutes, expected.gameplayMinutes);
      expect(actual.affiliations.length, expected.affiliations.length);
      expect(actual.hangarSummary.shipCount, expected.hangarSummary.shipCount);
      expect(
        actual.hangarSummary.isAvailable,
        expected.hangarSummary.isAvailable,
      );
      expect(actual.favoriteShips.length, expected.favoriteShips.length);
      expect(h.connection.revision, 0);
      expect(h.remote.writes, 0);
      h.hangar.snapshot = const LocalHangarSnapshot(revision: 1, ships: []);
      final cleared = await h.port.read();
      expect(cleared.hangarSummary.shipCount, 0);
      expect(cleared.hangarSummary.isAvailable, isTrue);
    },
  );
  test(
    'hangar and personal page use identical catalog facts and instance totals',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.hangar.snapshot = const LocalHangarSnapshot(
        revision: 2,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            catalogId: 'catalog-carrack',
            category: 'exploration',
            sizeClass: 'large',
            deliveryStatus: 'flyable',
            priceUsd: 600,
            imageAsset: 'assets/ships/catalog-carrack.jpg',
            thumbnailAsset: 'assets/ships/catalog-square-carrack.png',
          ),
          LocalHangarShip(
            id: shipB,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            catalogId: 'catalog-carrack',
            category: 'exploration',
            sizeClass: 'large',
            deliveryStatus: 'flyable',
            priceUsd: 600,
            imageAsset: 'assets/ships/catalog-carrack.jpg',
          ),
          LocalHangarShip(
            id: 'unknown',
            title: 'Unlisted',
            imageAsset: 'C:/private/a.jpg',
            thumbnailAsset: 'C:/private/a.jpg',
          ),
        ],
      );
      await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
      final profile = await h.port.read();
      final totals = LocalHangarTotals(
        h.hangar.snapshot.ships.map(LocalHangarPresentation.fromSaved),
      );
      expect(profile.hangarSummary.shipCount, totals.count);
      expect(profile.hangarSummary.unpricedCount, totals.unpricedCount);
      expect(profile.hangarSummary.estimatedValueLabel, r'$1,200 USD');
      expect(profile.hangarSummary.categories.map((c) => c.count), [2, 1]);
      expect(profile.favoriteShips.length, 2);
      expect(
        profile.favoriteShips.first.imageAsset,
        'assets/ships/catalog-carrack.jpg',
      );
      expect(
        profile.favoriteShips.first.roleKey,
        'profile.local.category.exploration',
      );
      expect(profile.favoriteShips.first.sizeKey, 'profile.local.size.large');
      expect(profile.favoriteShips.first.valueLabel, r'$600 USD');
      expect(profile.local!.choices.last.imageAsset, isEmpty);
      expect(
        profile.favoriteShips.first.thumbnailAsset,
        'assets/ships/catalog-square-carrack.png',
      );
      expect(profile.favoriteShips.last.thumbnailAsset, isEmpty);
      expect(profile.local!.choices.last.thumbnailAsset, isEmpty);
      expect(h.remote.writes, 0);
    },
  );

  testWidgets(
    'local catalog values and unknown count fit the real profile page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      h.hangar.snapshot = const LocalHangarSnapshot(
        revision: 2,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            category: 'exploration',
            sizeClass: 'large',
            priceUsd: 600,
            imageAsset: 'assets/ships/carrack.png',
          ),
          LocalHangarShip(id: shipB, title: 'Unlisted'),
        ],
      );
      await tester.runAsync(
        () async => h.port.save(edit(await h.port.read(), ids: [shipA])),
      );
      await tester.pumpWidget(
        StarBridgeApp(
          composition: AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            accountPort: InMemoryAccountAdapter.forReview(
              AccountReviewState.signedIn,
            ),
            personalProfilePort: h.port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('profile-hangar-value-panel')),
      );
      expect(find.text('已知估值'), findsOneWidget);
      expect(find.text('1 艘未计价'), findsOneWidget);
      expect(find.textContaining('未知用途'), findsWidgets);
      expect(find.textContaining('profile.local.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.session.close);
    },
  );
  test('local edit survives reopen without a remote write or read-side file creation', () async {
    final h = Harness();
    addTearDown(h.close);
    final before = await h.port.read();
    expect(before.local!.choices.length, 2);
    expect(before.hangarSummary.shipCount, 2);
    expect(h.connection.content, isNull);
    expect(
      (await h.port.save(edit(before, ids: [shipA]))).outcome,
      PersonalProfileActionOutcome.completed,
    );
    expect(h.remote.writes, 0);
    expect(h.connection.content!['favoriteShipIds'], [shipA]);
    final after = await h.port.read();
    expect(after.callSign, 'Local call sign');
    expect(after.favoriteShips.single.identity.runtimeId, shipA);
    expect(after.favoriteShips.single.identity.simplifiedChineseName, '克拉克');
    await h.port.close();
    h.port = BridgeLocalPersonalProfile(
      h.session,
      remote: h.remote,
      hangar: () => h.hangar,
    );
    expect((await h.port.read()).about, 'Local introduction');
    expect(
      h.connection.requests.where(
        (r) => r.name == 'personalProfile.updateSelf',
      ),
      isEmpty,
    );
  });

  test(
    'failed save retries same operation and does not report success',
    () async {
      final h = Harness();
      // Exercise only the local writer, not a preceding account rename.
      h.connection.callSign = 'Local call sign';
      addTearDown(h.close);
      final before = await h.port.read();
      h.connection.failSave = true;
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.failed,
      );
      expect(h.connection.content, isNull);
      h.connection.failSave = false;
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      final saves = h.connection.requests
          .where((r) => r.name == 'personalProfile.localSave')
          .toList();
      expect(saves[0].payload['operationId'], saves[1].payload['operationId']);
      expect(saves[1].payload.containsKey('visibility'), isFalse);
      final confirmed = await h.port.read();
      h.connection.failSave = true;
      h.connection.commitOnFailure = true;
      expect(
        (await h.port.save(edit(confirmed))).outcome,
        PersonalProfileActionOutcome.failed,
      );
      final lostOperation = h.connection.operation;
      final recovered = await h.port.read();
      h.connection.failSave = false;
      expect(
        (await h.port.save(edit(recovered))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.connection.operation, isNot(lostOperation));
      expect(h.connection.revision, 3);
      expect(
        h.connection.requests.where((r) => r.name == 'account.updateCallSign'),
        isEmpty,
      );
    },
  );

  test(
    'account generation change rejects old edits and clears choices',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final before = await h.port.read();
      h.session.advanceGeneration(8);
      h.connection.generation = 8;
      h.connection.state = 'signedOut';
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(h.connection.content, isNull);
      expect(
        (await h.port.read()).availability,
        PersonalProfileAvailability.signedOut,
      );
    },
  );

  test(
    'saved local page remains usable when remote read is unavailable',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.port.save(edit(await h.port.read(), ids: [shipA]));
      h.remote.available = false;
      final local = await h.port.read();
      expect(local.availability, PersonalProfileAvailability.available);
      expect(local.local!.remoteAvailable, isFalse);
      expect(local.gameHandle, isEmpty);
      expect(local.callSign, 'Local call sign');
      expect(local.favoriteShips.single.identity.runtimeId, shipA);
      expect(
        (await h.port.save(edit(local))).outcome,
        PersonalProfileActionOutcome.completed,
      );
    },
  );

  test(
    'missing hangar differs from saved empty and keeps unresolved favorite IDs',
    () async {
      final remote = await InMemoryPersonalProfileAdapter.forReview(
        signedIn: true,
      ).read();
      final content = <String, Object?>{
        'callSign': 'Saved',
        'introduction': '',
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'modules': <Object?>[],
        'favoriteShipIds': [shipA],
      };
      final missing = projectLocalProfile(
        const PersonalProfileSnapshot.unavailable(),
        content,
        null,
        null,
      );
      expect(missing.hangarSummary.isAvailable, isFalse);
      expect(missing.local!.favoriteShipIds, [shipA]);
      expect(missing.hangarSummary.unresolvedFavoriteCount, 1);
      final empty = projectLocalProfile(
        remote,
        content,
        const LocalHangarSnapshot(revision: 1, ships: []),
        null,
      );
      expect(empty.hangarSummary.isAvailable, isTrue);
      expect(empty.hangarSummary.shipCount, 0);
      final unsaved = projectLocalProfile(
        const PersonalProfileSnapshot.unavailable(),
        content,
        const LocalHangarSnapshot(revision: 0, ships: []),
        null,
      );
      expect(unsaved.hangarSummary.isAvailable, isFalse);
    },
  );

  test('hangar save event refreshes the module without copying ships into profile storage', () async {
    final h = Harness();
    final module = createPersonalProfileModule(h.port);
    addTearDown(() async {
      module.dispose();
      await h.session.close();
    });
    await module.initialize();
    expect(module.projection.value.hangarSummary.shipCount, 2);
    h.hangar.snapshot = const LocalHangarSnapshot(revision: 2, ships: []);
    h.connection.stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'hangarReader.changed',
        'sessionGeneration': 7,
        'sequence': 1,
        'payload': {'schemaVersion': 1},
      }),
    );
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(module.projection.value.hangarSummary.shipCount, 0);
    expect(module.projection.value.hangarSummary.isAvailable, isTrue);
    expect(h.connection.content, isNull);
  });

  for (final legacy in [false, true]) {
    testWidgets(
      'local editor keeps failed draft with account-aware retry: legacy=$legacy',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final h = Harness(legacy: legacy);
        await tester.pumpWidget(
          StarBridgeApp(
            composition: AppComposition.forTest(
              windowChrome: InMemoryWindowChrome(),
              accountPort: InMemoryAccountAdapter.forReview(
                AccountReviewState.signedIn,
              ),
              personalProfilePort: h.port,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-command')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('account-menu-personal-profile')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-preview')), findsNothing);
        await tester.tap(find.byKey(const Key('profile-edit')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-visibility-selector')),
          findsNothing,
        );
        expect(find.text('保存页面'), findsOneWidget);
        final picker = find.byKey(
          const Key('profile-module-edit-favorite-ships'),
        );
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('profile-favorite-$shipA')));
        await tester.tap(find.byKey(const Key('profile-favorites-apply')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('profile-call-sign-field')),
        );
        await tester.enterText(
          find.byKey(const Key('profile-call-sign-field')),
          'Local draft',
        );
        h.connection.failSave = true;
        final save = find.byKey(const Key('profile-save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
        expect(find.text('Local draft'), findsOneWidget);
        h.connection.failSave = false;
        final requestsAfterFailure = h.connection.requests.length;
        await tester.tap(save);
        await tester.pumpAndSettle();
        if (legacy) {
          expect(h.connection.content!['callSign'], 'Local draft');
          expect(h.connection.content!['favoriteShipIds'], [shipA]);
        } else {
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          expect(h.connection.requests.length, requestsAfterFailure);
          expect(h.connection.callSign, 'Local draft');
          expect(h.connection.content, isNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.session.close);
      },
    );
  }
}

const shipA = '11111111111111111111111111111111';
const shipB = '22222222222222222222222222222222';
PersonalProfileEdit edit(
  PersonalProfileSnapshot profile, {
  String callSign = 'Local call sign',
  List<String>? ids,
  PersonalProfilePlayStyle? playStyle,
  PersonalProfileSchedule? schedule,
}) => PersonalProfileEdit(
  callSign: callSign,
  about: 'Local introduction',
  avatarStyle: 1,
  wallpaperId: 'none',
  visibility: profile.visibility,
  moduleLayout: profile.moduleLayout,
  favoriteShipIds: ids,
  playStyle: playStyle,
  schedule: schedule,
);

class Harness {
  Harness({bool legacy = false}) {
    if (legacy) {
      connection.state = 'legacySignedIn';
      connection.authority = 'starbridge-relay-test';
    }
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    session.acceptHostCapabilities(['account.callSign']);
    remote.connection = connection;
    port = BridgeLocalPersonalProfile(
      session,
      remote: remote,
      hangar: () => hangar,
    );
  }
  final connection = LocalProfileConnection();
  final remote = RemoteProfile();
  final hangar = SavedHangar();
  late final BridgeClientSession session;
  late BridgeLocalPersonalProfile port;
  Future<void> close() async {
    await port.close();
    await session.close();
  }
}

class RemoteProfile
    implements PersonalProfilePort, PersonalProfilePresentationWriter {
  String? about;
  PersonalProfilePresentation? presentation;
  Map<String, Map<String, Object?>>? pageGroups;
  PersonalProfileActionOutcome pageOutcome =
      PersonalProfileActionOutcome.completed;
  @override
  Future<PersonalProfileActionResult> savePresentation(
    PersonalProfilePresentation expected,
    Map<String, Map<String, Object?>> edits,
  ) async {
    expect(identical(expected, presentation), isTrue);
    writes++;
    pageGroups = edits;
    return PersonalProfileActionResult(
      pageOutcome,
      failureKey: pageOutcome == PersonalProfileActionOutcome.completed
          ? null
          : 'profile.error.refreshBeforeSave',
    );
  }

  String? avatarImageData;
  LocalProfileConnection? connection;
  final source = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  bool available = true;
  Object? readError;
  Completer<PersonalProfileSnapshot>? pendingRead;
  int writes = 0;
  int reads = 0;
  PersonalProfileSnapshot? importedSnapshot;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<PersonalProfileSnapshot> read() async {
    reads++;
    if (readError case final error?) throw error;
    if (pendingRead case final pending?) return pending.future;
    if (!available) return const PersonalProfileSnapshot.unavailable();
    final base = importedSnapshot ?? await source.read();
    return PersonalProfileSnapshot.available(
      presentation: presentation,
      callSign: connection?.callSign ?? base.callSign,
      gameHandle: base.gameHandle,
      about: about ?? base.about,
      avatarStyle: base.avatarStyle,
      avatarImageData: avatarImageData ?? base.avatarImageData,
      wallpaperId: base.wallpaperId,
      visibility: base.visibility,
      presenceIntent: base.presenceIntent,
      affiliations: base.affiliations,
      availabilityWindows: base.availabilityWindows,
      timeZoneLabel: base.timeZoneLabel,
      gameplayMinutes: base.gameplayMinutes,
      activityRhythm: base.activityRhythm,
      roles: base.roles,
      participationInterests: base.participationInterests,
      supportCapabilities: base.supportCapabilities,
      shipWishlist: base.shipWishlist,
      favoriteShips: base.favoriteShips,
      hangarSummary: base.hangarSummary,
      moduleLayout: base.moduleLayout,
      allowEditing: base.allowEditing,
      local: base.local,
    );
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    writes++;
    throw StateError('Local flow must not write remotely.');
  }

  @override
  Future<void> close() async {}
}

class SavedHangar implements LocalHangarPort {
  LocalHangarSnapshot snapshot = const LocalHangarSnapshot(
    revision: 1,
    ships: [
      LocalHangarShip(
        id: shipA,
        title: 'Carrack',
        cn: '克拉克',
        tw: '克拉克',
        liner: 'Anvil',
      ),
      LocalHangarShip(
        id: shipB,
        title: 'Carrack',
        cn: '克拉克',
        tw: '克拉克',
        liner: 'Anvil',
      ),
    ],
  );
  @override
  Future<LocalHangarSnapshot> read() async => snapshot;
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw UnimplementedError();
}

class LocalProfileConnection implements BridgeConnection {
  String subject = 'owner';
  String environment = 'test';
  String? callSign;
  String? callSignError;
  int backgroundRevision = 4;
  String background = 'none';
  String? backgroundError;
  String? backgroundWriteError;
  bool invalidateBackgroundRead = false;
  int visibilityRevision = 1;
  String visibility = 'private';
  List<String>? availableVisibilities;
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  Map<String, Object?>? content;
  int revision = 0;
  String? operation;
  bool failSave = false;
  bool commitOnFailure = false;
  int generation = 7;
  String state = 'signedIn';
  String authority = 'issuer';
  String? displayName;
  String? avatarImageData;
  String? localReadError;
  final pendingLocalReadErrors = <String>[];
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.messageType != 'request') return;
    requests.add(request);
    // Match Host preflight: the same desired value is already confirmed, while
    // a different current value must still match the editor's expected name.
    final currentCallSign = callSign ?? 'Aster Lin';
    final renameError =
        callSignError ??
        (request.name == 'account.updateCallSign' &&
                currentCallSign != request.payload['callSign'] &&
                currentCallSign != request.payload['expectedCallSign']
            ? 'account.callsign_conflict'
            : null);
    if (request.name == 'account.updateCallSign' && renameError == null) {
      callSign = request.payload['callSign'] as String;
    }
    if (request.name == 'personalProfile.readBackground' &&
        invalidateBackgroundRead) {
      stream.add(
        BridgeEnvelope.fromJson({
          'protocolVersion': 1,
          'messageType': 'event',
          'name': 'account.changed',
          'sessionGeneration': generation,
          'sequence': 1,
          'payload': {'schemaVersion': 1},
        }),
      );
    }
    if (request.name == 'personalProfile.saveBackground' &&
        backgroundError == null &&
        backgroundWriteError == null) {
      background = request.payload['wallpaperId'] as String;
      backgroundRevision++;
    }
    if (request.name == 'personalProfile.saveVisibility') {
      visibility = request.payload['visibility'] as String;
      visibilityRevision++;
    }
    final save = request.name == 'personalProfile.localSave';
    final errorCode = request.name == 'account.updateCallSign'
        ? renameError
        : request.name == 'personalProfile.saveBackground'
        ? backgroundWriteError ?? backgroundError
        : request.name.endsWith('Background')
        ? backgroundError
        : save && failSave
        ? 'profile_local.write_failed'
        : request.name == 'personalProfile.localRead'
        ? (pendingLocalReadErrors.isNotEmpty
              ? pendingLocalReadErrors.removeAt(0)
              : localReadError)
        : null;
    if (save && (!failSave || commitOnFailure)) {
      content = (request.payload['content'] as Map).cast<String, Object?>();
      revision++;
      operation = request.payload['operationId'] as String;
    }
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': generation,
        'status': errorCode != null ? 'error' : 'ok',
        if (errorCode != null)
          'error': {'code': errorCode, 'message': 'fixture', 'retryable': true},
        'accountContext': {
          'environment': environment,
          'authority': authority,
          'subject': subject,
        },
        'payload': request.name == 'account.updateCallSign'
            ? {'schemaVersion': 1, 'callSign': callSign}
            : request.name == 'account.getCurrent'
            ? {
                'schemaVersion': 1,
                'state': state,
                'displayName': displayName,
                'avatarImageData': avatarImageData,
              }
            : request.name.endsWith('Background')
            ? {
                'schemaVersion': 1,
                'revision': backgroundRevision,
                'wallpaperId': background,
              }
            : request.name.endsWith('Visibility')
            ? {
                'schemaVersion': 1,
                'revision': visibilityRevision,
                'visibility': visibility,
                if (availableVisibilities != null)
                  'availableVisibilities': availableVisibilities,
              }
            : {
                'schemaVersion': 1,
                'revision': revision,
                'operationId': operation,
                'content': content,
                'savedAt': revision == 0 ? null : '2026-01-01T00:00:00Z',
                'timeZones': [
                  {'id': 'UTC', 'label': 'UTC'},
                  {'id': 'America/Regina', 'label': '(UTC-06:00) Regina'},
                ],
              },
      }),
    );
  }
}
