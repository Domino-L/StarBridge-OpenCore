import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/session_warmup.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_read_preparation.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _path = String.fromEnvironment('STARBRIDGE_STAGED_PROFILE_WIRE');
final _skip = _path.isEmpty
    ? 'Requires actual staged Native profile wire.'
    : false;

void main() {
  test('cached optional observation metadata cannot advance the real synchronization time', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    final payload = (h.fixture['cached']['payload'] as Map)
        .cast<String, Object?>();
    expect(
      () => AccountPayloadDecoder.profile({
        ...payload,
        'observedAtUtc': '2099-01-01T00:00:00Z',
      }),
      throwsA(isA<BridgeFormatException>()),
    );
  }, skip: _skip);
  test('confirmed explicit link remains visible while independent cached profile revalidation is pending', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    h.session.acceptHostCapabilities([
      ...h.session.hostCapabilities,
      'account.compatibility.read',
      'account.compatibility.linkExisting',
    ]);
    h.liveKey = 'cached';
    h.extraReplies['account.getCompatibilityState'] = {
      'schemaVersion': 1,
      'identityState': 'unlinked',
      'relayState': 'notApplicable',
      'legacyFeaturesAvailable': false,
      'availableActions': ['linkExistingAccount'],
    };
    h.extraReplies['account.linkLegacyAccount'] = {
      'schemaVersion': 1,
      'identityState': 'linked',
      'relayState': 'notEstablished',
      'legacyFeaturesAvailable': false,
      'availableActions': <String>[],
    };
    await h.module.initialize();
    for (var i = 0; i < 4; i++) {
      await h.preparation.prepareNextRead();
    }
    expect(h.module.projection.value.canLinkLegacyAccount, isTrue);
    await h.module.linkLegacyAccount(
      accountName: 'synthetic-old',
      password: 'synthetic-input',
    );
    expect(
      h.module.projection.value.compatibility.identityState,
      AccountCompatibilityIdentityState.linked,
    );
    expect(h.module.projection.value.canLinkLegacyAccount, isFalse);
    expect(
      h.module.projection.value.compatibility.legacyFeaturesAvailable,
      isFalse,
    );
  }, skip: _skip);
  test(
    'successful optional avatar removal clears the previously displayed image',
    () async {
      final h = await StagedProfileHost.create();
      addTearDown(h.close);
      h.session.acceptHostCapabilities([
        ...h.session.hostCapabilities,
        'account.avatar.read',
      ]);
      (h.fixture['current']['payload'] as Map)['avatarImageData'] =
          'synthetic-old-image';
      h.extraReplies['account.readAvatar'] = {
        'schemaVersion': 1,
        'callSign': 'Current pilot',
        'imageData': null,
      };
      await h.module.initialize();
      expect(
        h.module.projection.value.profile?.avatarImageData,
        'synthetic-old-image',
      );
      for (var i = 0; i < 4; i++) {
        await h.preparation.prepareNextRead();
      }
      expect(h.module.projection.value.profile?.avatarImageData, isNull);
      expect(h.module.projection.value.profile?.displayName, 'Current pilot');
    },
    skip: _skip,
  );
  test('confirmed preference save does not discard independent queued identity reads', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    await h.preparation.prepareNextRead();
    await h.preparation.prepareNextRead();
    await h.module.savePreferences(
      locale: 'en-US',
      timeZone: h.module.projection.value.profile?.timeZone,
    );
    expect(h.module.projection.value.profile?.locale, 'en-US');
    expect(await h.preparation.prepareNextRead(), isTrue);
    expect(h.names.last, 'gameIdentity.getPolicy');
    expect(h.module.projection.value.profile?.locale, 'en-US');
    expect(
      h.module.projection.value.notice?.messageKey,
      'account.preferences.saved',
    );
    await h.module.refresh();
    expect(h.module.projection.value.profile?.locale, 'en-US');
    expect(h.module.projection.value.profile?.email, isNotNull);
  }, skip: _skip);
  test('fresh profile data replaces a cached nickname when optional presentation is not negotiated', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    h.liveDisplayName = 'New confirmed profile';
    await h.preparation.prepareNextRead();
    expect(
      h.module.projection.value.profile?.displayName,
      'New confirmed profile',
    );
  }, skip: _skip);

  test('generation retirement clears displayed cache before a held fresh scope can return', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    h.hold.addAll(['profile.getDisplayData', 'account.getCurrent']);
    final pending = h.preparation.prepareNextRead();
    await Future<void>.delayed(Duration.zero);
    await h.pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(h.module.projection.value.generation, 8);
    expect(h.module.projection.value.profile, isNull);
    await h.release('profile.getDisplayData');
    await pending;
    expect(h.module.projection.value.profile, isNull);
    expect(h.module.projection.value.canEditPreferences, isFalse);
  }, skip: _skip);
  test(
    'hard cache-read failure cannot leave an old live edit grant visible',
    () async {
      final h = await StagedProfileHost.create();
      addTearDown(h.close);
      await h.module.initialize();
      await h.preparation.prepareNextRead();
      await h.preparation.prepareNextRead();
      expect(h.module.projection.value.canEditPreferences, isTrue);
      h.cacheError = true;
      await h.module.refresh();
      expect(h.module.projection.value.profile, isNull);
      expect(h.module.projection.value.canEditPreferences, isFalse);
    },
    skip: _skip,
  );

  test(
    'explicit clear retires a cached display and all queued preparation',
    () async {
      final h = await StagedProfileHost.create();
      addTearDown(h.close);
      await h.module.initialize();
      await h.module.clearLocalCache();
      expect(h.module.projection.value.profile, isNull);
      expect(
        h.module.projection.value.profileFreshness,
        AccountProfileFreshness.unavailable,
      );
      expect(await h.preparation.prepareNextRead(), isFalse);
      expect(h.names, isNot(contains('profile.getDisplayData')));
    },
    skip: _skip,
  );

  test('unrequested Host cancellation retains read-only display and stops the work list', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    h.cancelLive = true;
    await h.preparation.prepareNextRead();
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.cached,
    );
    expect(h.module.projection.value.canEditPreferences, isFalse);
    expect(
      h.module.projection.value.notice?.messageKey,
      isNot('account.login.cancelled'),
    );
    expect(await h.preparation.prepareNextRead(), isFalse);
  }, skip: _skip);
  test(
    'cached account fields arrive before any private or auxiliary preparation',
    () async {
      final h = await StagedProfileHost.create();
      addTearDown(h.close);
      await h.module.initialize();
      expect(h.names, ['account.getCurrent', 'profile.readDisplayCache']);
      expect(h.module.projection.value.profile?.displayName, isNotEmpty);
      expect(h.module.projection.value.profile?.email, isNull);
      expect(
        h.module.projection.value.profileFreshness,
        AccountProfileFreshness.cached,
      );
      expect(
        h.module.projection.value.cachedAt,
        DateTime.parse(
          (h.fixture['cached']['payload'] as Map)['cachedAtUtc'] as String,
        ),
      );
      expect(h.module.projection.value.canEditPreferences, isFalse);
      expect(h.module.projection.value.isBusy, isFalse);
    },
    skip: _skip,
  );

  test('fresh profile appears while directory and identity remain held; editing waits for directory', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    await h.preparation.prepareNextRead();
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.live,
    );
    expect(h.module.projection.value.profile?.email, isNotNull);
    expect(h.module.projection.value.canEditPreferences, isFalse);
    h.hold.add('profile.getTimeZoneDirectory');
    final directory = h.preparation.prepareNextRead();
    await Future<void>.delayed(Duration.zero);
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.live,
    );
    expect(h.module.projection.value.profile?.email, isNotNull);
    expect(h.module.projection.value.canEditPreferences, isFalse);
    await h.release('profile.getTimeZoneDirectory');
    await directory;
    expect(h.module.projection.value.canEditPreferences, isTrue);
    h.hold.add('gameIdentity.getPolicy');
    final identity = h.preparation.prepareNextRead();
    await Future<void>.delayed(Duration.zero);
    expect(h.module.projection.value.profile?.email, isNotNull);
    h.preparation.cancelReadPreparation();
    await identity;
  }, skip: _skip);

  test('explicitly canceled background data never clears cached fields or reports login cancellation', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    final before = h.module.projection.value.cachedAt;
    h.hold.add('profile.getDisplayData');
    final pending = h.preparation.prepareNextRead();
    await Future<void>.delayed(Duration.zero);
    h.preparation.cancelReadPreparation();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(h.names, contains('bridge.cancel'));
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.cached,
    );
    expect(h.module.projection.value.cachedAt, before);
    expect(
      h.module.projection.value.notice?.messageKey,
      isNot('account.login.cancelled'),
    );
    await h.release('profile.getDisplayData');
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.cached,
    );
    await h.preparation.prepareNextRead();
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.live,
    );
  }, skip: _skip);

  test('hard data denial clears cached fields and cannot be revived by an auxiliary result', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    await h.module.initialize();
    h.liveKey = 'forbidden';
    await h.preparation.prepareNextRead();
    expect(h.module.projection.value.profile, isNull);
    expect(h.module.projection.value.canEditPreferences, isFalse);
    expect(h.module.projection.value.failure?.code, 'profile.read_forbidden');
    expect(await h.preparation.prepareNextRead(), isFalse);
    expect(h.names, isNot(contains('profile.getTimeZoneDirectory')));
  }, skip: _skip);

  test(
    'directory failure retains confirmed live content and same-owner draft',
    () async {
      final h = await StagedProfileHost.create();
      addTearDown(h.close);
      await h.module.initialize();
      await h.preparation.prepareNextRead();
      await h.preparation.prepareNextRead();
      h.module.preferencesDraft.setLocale('en-US');
      await h.module.refresh();
      expect(h.module.projection.value.profile?.email, isNotNull);
      expect(h.module.preferencesDraft.locale, 'en-US');
      await h.preparation.prepareNextRead();
      h.failDirectory = true;
      await h.preparation.prepareNextRead();
      expect(
        h.module.projection.value.profileFreshness,
        AccountProfileFreshness.live,
      );
      expect(h.module.projection.value.profile?.email, isNotNull);
      expect(h.module.projection.value.canEditPreferences, isFalse);
      expect(h.module.preferencesDraft.locale, 'en-US');
      expect(h.module.preferencesDraft.hasChanges, isTrue);
    },
    skip: _skip,
  );

  test('cache miss is ready for deferred fresh data and does not manufacture a profile', () async {
    final h = await StagedProfileHost.create();
    addTearDown(h.close);
    h.cacheKey = 'empty';
    await h.module.initialize();
    expect(h.module.projection.value.isSignedIn, isTrue);
    expect(h.module.projection.value.profile, isNull);
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.unavailable,
    );
    await h.preparation.prepareNextRead();
    expect(
      h.module.projection.value.profileFreshness,
      AccountProfileFreshness.live,
    );
  }, skip: _skip);

  testWidgets(
    'auxiliary recovery backoff only signals idle work while backgrounded',
    (t) async {
      final fixture = await t.runAsync(
        () async =>
            jsonDecode(await File(_path).readAsString())
                as Map<String, dynamic>,
      );
      final h = StagedProfileHost(fixture!);
      addTearDown(h.close);
      await h.module.initialize();
      await h.preparation.prepareNextRead();
      h.failDirectory = true;
      await h.preparation.prepareNextRead();
      await h.preparation.prepareNextRead();
      final warmup = SessionWarmup(
        now: t.binding.clock.now,
        account: h.module.projection,
        jobs: const [],
        workChanges: h.module.projection,
        cancelWork: h.preparation.cancelReadPreparation,
        continueWork: h.preparation.prepareNextRead,
      );
      addTearDown(warmup.dispose);
      warmup.setForeground(false);
      warmup.start();
      final before = h.names.length;
      await t.pump(const Duration(seconds: 30));
      expect(h.names.length, before);
      expect(
        h.module.projection.value.profileFreshness,
        AccountProfileFreshness.live,
      );
      expect(h.module.projection.value.canEditPreferences, isFalse);
      h.failDirectory = false;
      warmup.setForeground(true);
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      expect(h.names.last, 'profile.getTimeZoneDirectory');
      expect(h.module.projection.value.canEditPreferences, isTrue);
      warmup.dispose();
    },
    skip: _path.isEmpty,
  );

  testWidgets(
    'idle owner pauses and cancels held preparation on input and loss of foreground',
    (t) async {
      final fixture = await t.runAsync(
        () async =>
            jsonDecode(await File(_path).readAsString())
                as Map<String, dynamic>,
      );
      final h = StagedProfileHost(fixture!);
      addTearDown(h.close);
      await h.module.initialize();
      h.hold.add('profile.getDisplayData');
      final warmup = SessionWarmup(
        now: t.binding.clock.now,
        account: h.module.projection,
        jobs: const [],
        workChanges: h.module.projection,
        cancelWork: h.preparation.cancelReadPreparation,
        continueWork: h.preparation.prepareNextRead,
      );
      addTearDown(warmup.dispose);
      warmup.setForeground(false);
      warmup.start();
      await t.pump(const Duration(seconds: 10));
      expect(h.names, isNot(contains('profile.getDisplayData')));
      warmup.setForeground(true);
      await t.pump(const Duration(milliseconds: 300));
      expect(h.names, contains('profile.getDisplayData'));
      warmup.deferForInteraction();
      await t.pump();
      expect(h.names, contains('bridge.cancel'));
      expect(
        h.module.projection.value.profileFreshness,
        AccountProfileFreshness.cached,
      );
      final before = h.names.length;
      await t.pump(const Duration(milliseconds: 799));
      expect(h.names.length, before);
      warmup.setForeground(false);
      await t.pump(const Duration(seconds: 20));
      expect(h.names.length, before);
    },
    skip: _path.isEmpty,
  );
}

final class StagedProfileHost {
  StagedProfileHost(this.fixture) {
    session.acceptHostCapabilities([
      'profile.stagedRead',
      'account.preferences.write',
      'account.profileCache.clear',
    ]);
    incoming = pair.host.incoming.listen((request) {
      names.add(request.name);
      if (hold.contains(request.name)) {
        (held[request.name] ??= []).add(request);
      } else {
        reply(request);
      }
    });
    module = createAccountModule(BridgeAccountAdapter(session));
  }
  static Future<StagedProfileHost> create() async => StagedProfileHost(
    jsonDecode(await File(_path).readAsString()) as Map<String, dynamic>,
  );
  final Map<String, dynamic> fixture;
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final AccountModule module;
  AccountReadPreparation get preparation => module as AccountReadPreparation;
  late final StreamSubscription<BridgeEnvelope> incoming;
  final names = <String>[];
  final hold = <String>{};
  final held = <String, List<BridgeEnvelope>>{};
  String cacheKey = 'cached', liveKey = 'live';
  bool failDirectory = false, cacheError = false, cancelLive = false;
  String? liveDisplayName;
  final extraReplies = <String, Map<String, Object?>>{};
  final extraErrors = <String, BridgeErrorBody>{};
  void reply(BridgeEnvelope request) {
    if (extraErrors[request.name] case final error?) {
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: request.accountContext,
            status: 'error',
            payload: const {},
            error: error,
          ),
        ),
      );
      return;
    }
    if (extraReplies[request.name] case final payload?) {
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: request.accountContext,
            status: 'ok',
            payload: payload,
          ),
        ),
      );
      return;
    }
    if (request.name == 'profile.getDisplayData' && cancelLive) {
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: request.accountContext,
            status: 'cancelled',
            payload: const {},
          ),
        ),
      );
      return;
    }
    if (request.name == 'bridge.cancel' ||
        request.name == 'profile.getTimeZoneDirectory' && failDirectory) {
      final fail = request.name != 'bridge.cancel';
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: request.accountContext,
            status: fail ? 'error' : 'ok',
            payload: fail
                ? const {}
                : const {'schemaVersion': 1, 'cancelled': true},
            error: fail
                ? const BridgeErrorBody(
                    code: 'profile.directory_unavailable',
                    message: 'Synthetic auxiliary outage',
                    retryable: true,
                  )
                : null,
          ),
        ),
      );
      return;
    }
    final key = switch (request.name) {
      'account.getCurrent' => 'current',
      'profile.readDisplayCache' => cacheError ? 'forbidden' : cacheKey,
      'profile.getDisplayData' => liveKey,
      'profile.getTimeZoneDirectory' => 'directory',
      'gameIdentity.getPolicy' => 'identity',
      'profile.patchPreferences' => 'saved',
      'profile.clearLocalCache' => 'cleared',
      _ => throw StateError('Unexpected ${request.name}'),
    };
    final wire = (fixture[key] as Map).cast<String, Object?>();
    if (request.name == 'profile.patchPreferences') {
      cacheKey = 'cachedAfterSaved';
    }
    if (request.name == 'profile.getDisplayData') {
      cacheKey = switch (liveKey) {
        'live' => 'cachedAfterLive',
        'cached' => 'cached',
        _ => 'retired',
      };
    }
    unawaited(
      pair.host.send(
        BridgeEnvelope.fromJson({
          ...wire,
          'name': request.name,
          'correlationId': request.correlationId,
          'sessionGeneration': request.sessionGeneration,
          if (request.name == 'profile.getDisplayData' &&
              liveKey == 'live' &&
              liveDisplayName != null)
            'payload': {
              ...(wire['payload'] as Map),
              'profile': {
                ...((wire['payload'] as Map)['profile'] as Map),
                'displayName': liveDisplayName,
              },
            },
        }),
      ),
    );
  }

  Future<void> release(String name) async {
    hold.remove(name);
    for (final request in held.remove(name) ?? <BridgeEnvelope>[]) {
      reply(request);
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    module.dispose();
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
