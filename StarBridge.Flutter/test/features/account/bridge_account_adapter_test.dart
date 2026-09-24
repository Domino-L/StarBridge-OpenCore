import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'legacy login waits for delayed account.changed before returning',
    () async {
      final host = _LifecycleAccountHostHarness(legacy: true);
      addTearDown(host.close);
      expect(
        (await host.adapter.read()).snapshot?.sessionState,
        AccountSessionState.signedOut,
      );
      expect(
        (await host.adapter.loginLegacy(
          'old@example.invalid',
          'short',
        )).outcome,
        'verified',
      );
      expect(host._session.activeGeneration, 1);
      final result = await host.adapter.read();
      expect(result.snapshot?.sessionState, AccountSessionState.legacySignedIn);
      expect(result.snapshot?.route?.authority, 'starbridge-relay-synthetic');
      expect(host.requestNames, isNot(contains('profile.getSelf')));
      expect(
        (await host.adapter.execute(const LogoutAccount()))
            .snapshot
            ?.sessionState,
        AccountSessionState.signedOut,
      );
      expect(host._session.activeGeneration, 2);
    },
  );
  for (final state in ['legacySignedIn', 'legacyUnavailable']) {
    test(
      '$state reads a Relay identity without querying SCM profile',
      () async {
        final host = _AccountHostHarness(
          accountState: state,
          contextAuthority: 'starbridge-relay-synthetic',
        );
        addTearDown(host.close);
        final result = await host.adapter.read();
        expect(result.outcome, AccountActionOutcome.completed);
        expect(result.snapshot?.route?.authority, 'starbridge-relay-synthetic');
        expect(result.snapshot?.profile?.displayName, 'Legacy Commander');
        expect(
          result.snapshot?.profile?.maskedAccount,
          'o****@example.invalid',
        );
        expect(
          result.snapshot?.profile?.avatarImageData,
          'data:image/png;base64,account-photo',
        );
        expect(result.snapshot?.supportsPreferenceWrite, isFalse);
        expect(
          result.snapshot?.sessionState,
          state == 'legacySignedIn'
              ? AccountSessionState.legacySignedIn
              : AccountSessionState.legacyUnavailable,
        );
        expect(host.requestNames, ['account.getCurrent']);
        await host.adapter.execute(const LogoutAccount());
        expect(
          host.requests
              .firstWhere((r) => r.name == 'account.logout')
              .accountContext
              ?.authority,
          'starbridge-relay-synthetic',
        );
        expect(host.requestNames, isNot(contains('profile.getSelf')));
      },
    );
  }
  test(
    'legacy header receives the bound ID from existing local policy',
    () async {
      final host = _AccountHostHarness(
        accountState: 'legacySignedIn',
        contextAuthority: 'starbridge-relay-synthetic',
      );
      addTearDown(host.close);
      host._session.acceptHostCapabilities(['account.read']);
      final result = await host.adapter.read();
      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.identity.authoritativeHandle, 'Aster-Lin');
      expect(host.requestNames, [
        'account.getCurrent',
        'gameIdentity.getPolicy',
      ]);
    },
  );
  test('legacy state rejects an SCM authority', () async {
    final host = _AccountHostHarness(accountState: 'legacySignedIn');
    addTearDown(host.close);
    expect((await host.adapter.read()).outcome, AccountActionOutcome.failed);
    expect(host.requestNames, ['account.getCurrent']);
  });
  test(
    'legacy login requires capability and cannot project a SCM session',
    () async {
      final old = _AccountHostHarness();
      addTearDown(old.close);
      expect(
        (await old.adapter.loginLegacy('old@example.invalid', 'short')).outcome,
        'unavailable',
      );
      expect(old.requests, isEmpty);
      final host = _AccountHostHarness(legacyLoginAvailable: true);
      addTearDown(host.close);
      expect(
        (await host.adapter.loginLegacy(
          ' old@example.invalid ',
          ' short ',
        )).outcome,
        'verified',
      );
      expect(host.requestNames, ['account.loginLegacy']);
      expect(host.requests.single.accountContext, isNull);
      expect(host.requests.single.payload, {
        'schemaVersion': 1,
        'email': 'old@example.invalid',
        'password': ' short ',
      });
      expect(host._session.activeGeneration, 7);
    },
  );
  test('legacy login rejects a fabricated signedIn outcome', () async {
    final host = _AccountHostHarness(
      legacyLoginAvailable: true,
      legacyLoginOutcome: 'signedIn',
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.loginLegacy('old@example.invalid', 'short')).outcome,
      'unavailable',
    );
  });
  test(
    'legacy login cancels pending requests without duplicate sends',
    () async {
      final host = _AccountHostHarness(
        legacyLoginAvailable: true,
        delayedRequest: 'account.loginLegacy',
        responseDelay: const Duration(milliseconds: 120),
      );
      addTearDown(host.close);
      final pending = host.adapter.loginLegacy('old@example.invalid', 'short');
      while (!host.requestNames.contains('account.loginLegacy')) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        (await host.adapter.loginLegacy(
          'other@example.invalid',
          'short',
        )).outcome,
        'busy',
      );
      await host.adapter.cancelLegacyPasswordLogin();
      expect((await pending).outcome, 'cancelled');
      expect(host.requestNames, contains('bridge.cancel'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    },
  );
  test(
    'password recovery requires optional Host capability and never logs in',
    () async {
      final oldHost = _AccountHostHarness();
      addTearDown(oldHost.close);
      expect(oldHost.adapter.supportsPasswordRecovery, isFalse);
      expect(
        (await oldHost.adapter.sendPasswordResetCode('old@example.invalid'))
            .outcome,
        'unavailable',
      );
      expect(oldHost.requests, isEmpty);
      final host = _AccountHostHarness(recoveryAvailable: true);
      addTearDown(host.close);
      expect(
        (await host.adapter.sendPasswordResetCode(' old@example.invalid '))
            .outcome,
        'codeRequested',
      );
      expect(
        (await host.adapter.confirmPasswordReset(
          ' old@example.invalid ',
          ' 123456 ',
          ' synthetic password ',
        )).outcome,
        'reset',
      );
      expect(host.requestNames, [
        'account.sendPasswordResetCode',
        'account.confirmPasswordReset',
      ]);
      expect(
        host.requests.every((request) => request.accountContext == null),
        isTrue,
      );
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'email': 'old@example.invalid',
        'verificationCode': '123456',
        'newPassword': ' synthetic password ',
      });
    },
  );

  test('password recovery fails closed on an unsupported outcome', () async {
    final host = _AccountHostHarness(
      recoveryAvailable: true,
      recoveryOutcome: 'signedIn',
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.sendPasswordResetCode('old@example.invalid')).outcome,
      'unavailable',
    );
    expect(host.requestNames, isNot(contains('account.login')));
  });

  test(
    'password recovery is cancellable and does not duplicate a pending send',
    () async {
      final host = _AccountHostHarness(
        recoveryAvailable: true,
        delayedRequest: 'account.sendPasswordResetCode',
        responseDelay: const Duration(milliseconds: 120),
      );
      addTearDown(host.close);
      final pending = host.adapter.sendPasswordResetCode('old@example.invalid');
      while (!host.requestNames.contains('account.sendPasswordResetCode')) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        (await host.adapter.sendPasswordResetCode('old@example.invalid'))
            .outcome,
        'busy',
      );
      await host.adapter.cancelPasswordRecovery();
      expect((await pending).outcome, 'cancelled');
      expect(host.requestNames, contains('bridge.cancel'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    },
  );

  test('S2 negotiated existing-account link uses proof command but never provisions', () async {
    final harness = _AccountHostHarness(linkAvailable: true);
    addTearDown(harness.close);
    final initial = await harness.adapter.read();
    expect(initial.snapshot?.compatibility.availableActions, [
      AccountCompatibilityAction.linkExistingAccount,
    ]);
    final linked = await harness.adapter.execute(
      const LinkLegacyAccount(
        credential: LegacyAccountCredential(
          accountName: ' chosen@example.invalid ',
          password: ' synthetic ',
        ),
      ),
    );
    expect(linked.outcome, AccountActionOutcome.completed);
    expect(
      linked.snapshot?.compatibility.identityState,
      AccountCompatibilityIdentityState.linked,
    );
    final sent = harness.requests.singleWhere(
      (r) => r.name == 'account.linkLegacyAccount',
    );
    expect(sent.payload['credential'], {
      'accountName': 'chosen@example.invalid',
      'password': ' synthetic ',
    });
    expect(sent.accountContext?.subject, 'synthetic-subject');
    final create = await harness.adapter.execute(
      const CreateCompatibilityIdentity(),
    );
    expect(create.outcome, AccountActionOutcome.failed);
    expect(
      harness.requestNames,
      isNot(contains('account.createCompatibilityIdentity')),
    );
  });

  test('S2 read-only Host cannot expose a link action', () async {
    final harness = _AccountHostHarness(compatibilityAvailable: true);
    addTearDown(harness.close);
    final result = await harness.adapter.read();
    expect(result.snapshot?.compatibility.availableActions, isEmpty);
    final rejected = await harness.adapter.execute(
      const LinkLegacyAccount(
        credential: LegacyAccountCredential(
          accountName: 'synthetic',
          password: 'synthetic',
        ),
      ),
    );
    expect(rejected.outcome, AccountActionOutcome.failed);
    expect(harness.requestNames, isNot(contains('account.linkLegacyAccount')));
  });

  test('S2 password rejection retains SCM session and can retry', () async {
    final harness = _AccountHostHarness(
      linkAvailable: true,
      linkError: 'account.legacy_credentials_rejected',
    );
    addTearDown(harness.close);
    await harness.adapter.read();
    final rejected = await harness.adapter.execute(
      const LinkLegacyAccount(
        credential: LegacyAccountCredential(
          accountName: 'synthetic',
          password: 'synthetic',
        ),
      ),
    );
    expect(rejected.failure?.code, 'account.legacy_credentials_rejected');
    final refreshed = await harness.adapter.read();
    expect(refreshed.snapshot?.sessionState, AccountSessionState.signedIn);
    expect(
      refreshed.snapshot?.compatibility.identityState,
      AccountCompatibilityIdentityState.unlinked,
    );
  });

  test(
    'S2 cancellation targets the pending request and rechecks state',
    () async {
      final harness = _AccountHostHarness(
        linkAvailable: true,
        delayedRequest: 'account.linkLegacyAccount',
        responseDelay: const Duration(milliseconds: 120),
      );
      addTearDown(harness.close);
      await harness.adapter.read();
      final pending = harness.adapter.execute(
        const LinkLegacyAccount(
          credential: LegacyAccountCredential(
            accountName: 'synthetic',
            password: 'synthetic',
          ),
        ),
      );
      while (!harness.requestNames.contains('account.linkLegacyAccount')) {
        await Future<void>.delayed(Duration.zero);
      }
      final cancelled = await harness.adapter.execute(
        const CancelCompatibilityOperation(),
      );
      expect(cancelled.snapshot?.sessionState, AccountSessionState.signedIn);
      expect((await pending).outcome, AccountActionOutcome.cancelled);
      expect(harness.requestNames, contains('bridge.cancel'));
      // Simulate server completion racing cancellation: late reply cannot complete the old request.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final refreshed = await harness.adapter.read();
      expect(
        refreshed.snapshot?.compatibility.identityState,
        AccountCompatibilityIdentityState.linked,
      );
    },
  );

  test(
    'S2 compatibility reads verified linked state without enabling creation',
    () async {
      final harness = _AccountHostHarness(
        compatibilityAvailable: true,
        relayState: 'ready',
      );
      addTearDown(harness.close);
      final result = await harness.adapter.read();
      expect(result.outcome, AccountActionOutcome.completed);
      expect(
        result.snapshot?.compatibility.relayState,
        AccountCompatibilityRelayState.ready,
      );
      expect(result.snapshot?.compatibility.legacyFeaturesAvailable, isTrue);
      expect(result.snapshot?.compatibility.availableActions, isEmpty);
      expect(harness.requestNames, contains('account.getCompatibilityState'));
    },
  );

  test('S2 compatibility outage does not sign the SCM account out', () async {
    final harness = _AccountHostHarness(
      compatibilityAvailable: true,
      compatibilityError: 'account.compatibility_read_unavailable',
    );
    addTearDown(harness.close);
    final result = await harness.adapter.read();
    expect(result.outcome, AccountActionOutcome.completed);
    expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
    expect(result.snapshot?.compatibility.legacyFeaturesAvailable, isFalse);
  });

  test(
    'restore generation event rereads the account without reporting failure',
    () async {
      final harness = _AccountHostHarness(advanceGenerationOnFirstRead: true);
      addTearDown(harness.close);
      final result = await harness.adapter.read();
      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.generation, 8);
      expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
      expect(
        harness.requestNames
            .where((name) => name == 'account.getCurrent')
            .length,
        2,
      );
    },
  );

  test(
    'profile actions are read-only when the Host does not advertise them',
    () async {
      final harness = _AccountHostHarness(actionsAvailable: false);
      addTearDown(harness.close);
      final result = await harness.adapter.read();
      expect(
        AccountProjection.fromSnapshot(result.snapshot!).canEditPreferences,
        isFalse,
      );
    },
  );

  test(
    'clearing local cache does not read and recreate it immediately',
    () async {
      final harness = _AccountHostHarness();
      addTearDown(harness.close);
      await harness.adapter.read();
      harness.requests.clear();
      final result = await harness.adapter.execute(
        const ClearAccountProfileCache(),
      );
      expect(result.outcome, AccountActionOutcome.completed);
      expect(harness.requestNames, ['profile.clearLocalCache']);
      expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
    },
  );

  testWidgets(
    'preference authorization can take longer than the default request deadline',
    (tester) async {
      final harness = _AccountHostHarness(
        delayedRequest: 'profile.patchPreferences',
        responseDelay: const Duration(seconds: 25),
      );
      addTearDown(harness.close);
      await harness.adapter.read();
      final pending = harness.adapter.execute(
        const SaveAccountPreferences(
          patch: AccountPreferencePatch(
            localeSpecified: true,
            locale: 'en-US',
            timeZoneSpecified: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 26));
      final result = await pending;
      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.profile?.locale, 'en-US');
    },
  );

  test('preference save consumes the confirmed response without a second full refresh', () async {
    final harness = _AccountHostHarness();
    addTearDown(harness.close);
    await harness.adapter.read();
    harness.requests.clear();
    final result = await harness.adapter.execute(
      const SaveAccountPreferences(
        patch: AccountPreferencePatch(
          localeSpecified: true,
          locale: 'en-US',
          timeZoneSpecified: false,
        ),
      ),
    );
    expect(result.snapshot?.profile?.locale, 'en-US');
    expect(harness.requestNames, ['profile.patchPreferences']);
  });
  for (final delayedRequest in [
    'account.getCurrent',
    'profile.getSelf',
    'gameIdentity.getPolicy',
  ]) {
    testWidgets('$delayedRequest waits for a bounded multi-step Host read', (
      tester,
    ) async {
      final harness = _AccountHostHarness(
        delayedRequest: delayedRequest,
        responseDelay: const Duration(seconds: 20),
      );
      addTearDown(harness.close);
      final pending = harness.adapter.read();
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      final result = await pending;
      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
      expect(
        harness.requestNames,
        isNot(contains('account.getCompatibilityState')),
      );
    });
  }

  testWidgets(
    'an unresponsive account read still ends with a retryable timeout',
    (tester) async {
      final harness = _AccountHostHarness(
        delayedRequest: 'account.getCurrent',
        responseDelay: const Duration(seconds: 61),
      );
      addTearDown(harness.close);
      final pending = harness.adapter.read();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      final result = await pending;
      expect(result.outcome, AccountActionOutcome.failed);
      expect(result.failure?.code, 'bridge.timeout');
      expect(result.failure?.retryable, isTrue);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  test(
    'daily account refresh never contacts retired legacy compatibility',
    () async {
      final harness = _AccountHostHarness(
        compatibilityError: 'bridge.disconnected',
      );
      addTearDown(harness.close);
      final result = await harness.adapter.read();
      expect(result.outcome, AccountActionOutcome.completed);
      expect(harness.requestNames, [
        'account.getCurrent',
        'profile.getSelf',
        'gameIdentity.getPolicy',
      ]);
      expect(result.snapshot?.compatibility.availableActions, isEmpty);
    },
  );

  test(
    'reads account, profile and identity through the narrow adapter',
    () async {
      final harness = _AccountHostHarness();
      final adapter = harness.adapter;

      final result = await adapter.read();

      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.generation, 7);
      expect(result.snapshot?.profile?.displayName, 'Aster Lin');
      expect(result.snapshot?.profileFreshness, AccountProfileFreshness.live);
      expect(result.snapshot?.identity.state, AccountIdentityState.match);
      expect(result.snapshot?.identity.sensitiveWritesAllowed, isTrue);
      expect(
        result.snapshot?.compatibility.identityState,
        AccountCompatibilityIdentityState.unavailable,
      );
      expect(result.snapshot?.compatibility.availableActions, isEmpty);
      expect(harness.requestNames, [
        'account.getCurrent',
        'profile.getSelf',
        'gameIdentity.getPolicy',
      ]);
      await harness.close();
    },
  );

  test('legacy compatibility outage preserves the migrated account', () async {
    final harness = _AccountHostHarness(
      compatibilityError: 'account.compatibility_read_unavailable',
    );
    addTearDown(harness.close);

    final result = await harness.adapter.read();

    expect(result.outcome, AccountActionOutcome.completed);
    expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
    expect(result.snapshot?.profile?.displayName, 'Aster Lin');
    expect(result.snapshot?.identity.state, AccountIdentityState.match);
    expect(result.snapshot?.compatibility.legacyFeaturesAvailable, isFalse);
    expect(
      result.snapshot?.compatibility.relayState,
      AccountCompatibilityRelayState.notApplicable,
    );
    expect(result.snapshot?.compatibility.availableActions, isEmpty);
  });

  for (final code in [
    'account.reauthorization_required',
    'bridge.stale_generation',
    'bridge.invalid_envelope',
    'bridge.disconnected',
  ]) {
    test('current profile failure $code still fails closed', () async {
      final harness = _AccountHostHarness(profileError: code);
      addTearDown(harness.close);

      final result = await harness.adapter.read();

      expect(result.outcome, AccountActionOutcome.failed);
      expect(result.failure?.code, code);
    });
  }

  test('preference patch includes only explicitly changed fields', () async {
    final harness = _AccountHostHarness();
    final adapter = harness.adapter;
    await adapter.read();

    await adapter.execute(
      const SaveAccountPreferences(
        patch: AccountPreferencePatch(
          localeSpecified: false,
          timeZoneSpecified: true,
          timeZone: 'America/Regina',
        ),
      ),
    );

    final patchRequest = harness.requests.singleWhere(
      (request) => request.name == 'profile.patchPreferences',
    );
    final patch = patchRequest.payload['patch'] as Map<String, Object?>;
    expect(patch.containsKey('locale'), isFalse);
    expect(patch['timeZone'], 'America/Regina');
    expect(patchRequest.accountContext?.subject, 'synthetic-subject');
    await harness.close();
  });

  test('contradictory identity permission fails closed', () async {
    final harness = _AccountHostHarness(identityAllowsMismatch: true);

    final result = await harness.adapter.read();

    expect(result.outcome, AccountActionOutcome.failed);
    expect(result.failure?.code, 'bridge.invalid_envelope');
    await harness.close();
  });

  test(
    'temporary credential outage remains a recoverable session state',
    () async {
      final harness = _AccountHostHarness(
        accountState: 'credentialTemporarilyUnavailable',
      );

      final result = await harness.adapter.read();

      expect(result.outcome, AccountActionOutcome.completed);
      expect(
        result.snapshot?.sessionState,
        AccountSessionState.credentialTemporarilyUnavailable,
      );
      expect(result.snapshot?.route, isNull);
      expect(harness.requestNames, ['account.getCurrent']);
      await harness.close();
    },
  );

  test(
    'reauthorization state drops account context and profile reads',
    () async {
      final harness = _AccountHostHarness(
        accountState: 'reauthorizationRequired',
      );

      final result = await harness.adapter.read();

      expect(result.outcome, AccountActionOutcome.completed);
      expect(
        result.snapshot?.sessionState,
        AccountSessionState.reauthorizationRequired,
      );
      expect(result.snapshot?.route, isNull);
      expect(harness.requestNames, ['account.getCurrent']);
      await harness.close();
    },
  );

  for (final state in ['ready', 'unavailable']) {
    test(
      'historical relay $state cannot reactivate old compatibility',
      () async {
        final harness = _AccountHostHarness(relayState: state);
        addTearDown(harness.close);
        final result = await harness.adapter.read();
        expect(result.outcome, AccountActionOutcome.completed);
        expect(
          result.snapshot?.compatibility.relayState,
          AccountCompatibilityRelayState.notApplicable,
        );
        expect(result.snapshot?.compatibility.legacyFeaturesAvailable, isFalse);
        expect(result.snapshot?.compatibility.availableActions, isEmpty);
        expect(
          harness.requestNames,
          isNot(contains('account.getCompatibilityState')),
        );
      },
    );
  }

  for (final command in const <AccountPortCommand>[
    LinkLegacyAccount(
      credential: LegacyAccountCredential(
        accountName: 'legacy@example.com',
        password: 'synthetic-password',
      ),
    ),
    CreateCompatibilityIdentity(),
    CancelCompatibilityOperation(),
  ]) {
    test(
      'retired ${command.runtimeType} is rejected without sending credentials',
      () async {
        final harness = _AccountHostHarness();
        addTearDown(harness.close);
        await harness.adapter.read();
        harness.requests.clear();
        final result = await harness.adapter.execute(command);
        expect(result.outcome, AccountActionOutcome.failed);
        expect(result.failure?.code, 'bridge.capability_unavailable');
        expect(harness.requests, isEmpty);
      },
    );
  }

  test(
    'login waits for account.changed before refreshing the new generation',
    () async {
      final harness = _LifecycleAccountHostHarness();
      final initial = await harness.adapter.read();
      expect(initial.snapshot?.sessionState, AccountSessionState.signedOut);

      final result = await harness.adapter.execute(const BeginAccountLogin());

      expect(result.outcome, AccountActionOutcome.completed);
      expect(result.snapshot?.generation, 1);
      expect(result.snapshot?.sessionState, AccountSessionState.signedIn);
      expect(result.snapshot?.profile?.displayName, 'Aster Lin');
      final logout = await harness.adapter.execute(const LogoutAccount());
      expect(logout.outcome, AccountActionOutcome.completed);
      expect(logout.snapshot?.generation, 2);
      expect(logout.snapshot?.sessionState, AccountSessionState.signedOut);
      expect(harness.requestNames, [
        'account.getCurrent',
        'account.login',
        'account.getCurrent',
        'profile.getSelf',
        'gameIdentity.getPolicy',
        'account.logout',
        'account.getCurrent',
      ]);
      await harness.close();
    },
  );

  test(
    'production access gate maps to a dedicated user-facing message',
    () async {
      final harness = _LifecycleAccountHostHarness(
        loginErrorCode: 'account.environment_not_enabled',
      );

      final result = await harness.adapter.execute(const BeginAccountLogin());

      expect(result.outcome, AccountActionOutcome.failed);
      expect(result.failure?.code, 'account.environment_not_enabled');
      expect(result.failure?.messageKey, 'account.error.environmentNotEnabled');
      expect(result.failure?.retryable, isFalse);
      await harness.close();
    },
  );
}

final class _AccountHostHarness {
  _AccountHostHarness({
    bool compatibilityAvailable = false,
    bool recoveryAvailable = false,
    bool legacyLoginAvailable = false,
    this.legacyLoginOutcome,
    this.recoveryOutcome,
    bool linkAvailable = false,
    this.linkError,
    this.advanceGenerationOnFirstRead = false,
    this.actionsAvailable = true,
    this.identityAllowsMismatch = false,
    this.relayState,
    this.compatibilityError,
    this.profileError,
    this.delayedRequest,
    this.responseDelay = Duration.zero,
    this.accountState = 'signedIn',
    this.contextAuthority = 'scm-test',
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    _host = pair.host;
    _session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    adapter = BridgeAccountAdapter(_session);
    if (compatibilityAvailable ||
        linkAvailable ||
        recoveryAvailable ||
        legacyLoginAvailable) {
      _session.acceptHostCapabilities([
        'account.compatibility.read',
        if (linkAvailable) 'account.compatibility.linkExisting',
        if (recoveryAvailable) 'account.passwordRecovery',
        if (legacyLoginAvailable) 'account.legacyLogin',
      ]);
    }
    _subscription = _host.incoming.listen(_respond);
  }

  final bool identityAllowsMismatch;
  final bool advanceGenerationOnFirstRead;
  bool _advancedGeneration = false;
  final bool actionsAvailable;
  final String? relayState;
  final String? compatibilityError;
  final String? recoveryOutcome;
  final String? legacyLoginOutcome;
  final String? linkError;
  final String? profileError;
  final String? delayedRequest;
  final Duration responseDelay;
  final String accountState;
  final String contextAuthority;
  late final BridgeConnection _host;
  late final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgeAccountAdapter adapter;
  final List<BridgeEnvelope> requests = [];
  bool _compatibilityLinked = false;

  List<String> get requestNames => requests.map((item) => item.name).toList();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    if (request.name == delayedRequest) {
      await Future<void>.delayed(responseDelay);
    }
    if ((request.name == 'account.linkLegacyAccount' && linkError == null) ||
        request.name == 'account.createCompatibilityIdentity') {
      _compatibilityLinked = true;
    }
    final context = BridgeAccountContext(
      environment: 'synthetic',
      authority: contextAuthority,
      subject: 'synthetic-subject',
    );
    final errorCode = switch (request.name) {
      'account.getCompatibilityState' => compatibilityError,
      'account.linkLegacyAccount' => linkError,
      'profile.getSelf' => profileError,
      _ => null,
    };
    if (errorCode != null) {
      await _host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: context,
          payload: const {},
          status: 'error',
          error: BridgeErrorBody(
            code: errorCode,
            message: 'Synthetic failure.',
            retryable: true,
          ),
        ),
      );
      return;
    }
    final payload = switch (request.name) {
      'account.getCurrent' => <String, Object?>{
        'schemaVersion': 1,
        'state': accountState,
        'maskedAccount': accountState.startsWith('legacy')
            ? 'o****@example.invalid'
            : null,
        'avatarImageData': accountState.startsWith('legacy')
            ? 'data:image/png;base64,account-photo'
            : null,
        'displayName': accountState.startsWith('legacy')
            ? 'Legacy Commander'
            : accountState == 'signedIn'
            ? 'Aster Lin'
            : null,
        'avatarUrl': null,
      },
      'profile.getSelf' || 'profile.patchPreferences' => <String, Object?>{
        'schemaVersion': 1,
        'profile': <String, Object?>{
          'displayName': 'Aster Lin',
          'avatarUrl': null,
          'email': null,
          'locale': request.name == 'profile.patchPreferences'
              ? 'en-US'
              : 'zh-CN',
          'timeZone': 'Asia/Shanghai',
        },
        'source': 'live',
        'cachedAtUtc': null,
        'preferencesPolicy': <String, Object?>{
          if (actionsAvailable)
            'availableActions': [
              'profile.patchPreferences',
              'profile.clearLocalCache',
            ],
          'locales': ['zh-CN', 'en-US'],
          'timeZones': [
            <String, Object?>{
              'value': 'Asia/Shanghai',
              'label': 'Shanghai',
              'offset': 'UTC+08:00',
            },
            <String, Object?>{
              'value': 'America/Regina',
              'label': 'Regina',
              'offset': 'UTC-06:00',
            },
          ],
        },
      },
      'gameIdentity.getPolicy' => <String, Object?>{
        'schemaVersion': 1,
        'state': identityAllowsMismatch ? 'mismatch' : 'match',
        'authoritativeHandle': 'Aster-Lin',
        'sensitiveWritesAllowed': true,
      },
      'account.loginLegacy' => {
        'schemaVersion': 1,
        'outcome': legacyLoginOutcome ?? 'verified',
        'retryAfterSeconds': 0,
      },
      'account.sendPasswordResetCode' ||
      'account.confirmPasswordReset' => <String, Object?>{
        'schemaVersion': 1,
        'outcome':
            recoveryOutcome ??
            (request.name == 'account.sendPasswordResetCode'
                ? 'codeRequested'
                : 'reset'),
        'retryAfterSeconds': 60,
      },
      'account.getCompatibilityState' => <String, Object?>{
        'schemaVersion': 1,
        'identityState': _compatibilityLinked || relayState != null
            ? 'linked'
            : 'unlinked',
        'relayState':
            relayState ??
            (_compatibilityLinked ? 'notEstablished' : 'notApplicable'),
        'storedLegacyCredentialAvailable': false,
        'legacyFeaturesAvailable': relayState == 'ready',
        'availableActions': relayState == 'unavailable'
            ? <String>['retry']
            : _compatibilityLinked || relayState != null
            ? <String>[]
            : <String>['linkExistingAccount', 'createCompatibilityIdentity'],
      },
      'account.linkLegacyAccount' ||
      'account.createCompatibilityIdentity' => <String, Object?>{
        'schemaVersion': 1,
        'identityState': 'linked',
        'relayState': 'notEstablished',
        'storedLegacyCredentialAvailable': false,
        'legacyFeaturesAvailable': false,
        'availableActions': <String>[],
      },
      'profile.clearLocalCache' => <String, Object?>{
        'schemaVersion': 1,
        'cleared': true,
      },
      _ => <String, Object?>{'schemaVersion': 1},
    };
    await _host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext:
            request.name == 'account.getCurrent' &&
                accountState != 'signedIn' &&
                !accountState.startsWith('legacy')
            ? null
            : context,
        payload: payload,
        status: 'ok',
      ),
    );
    if (advanceGenerationOnFirstRead &&
        !_advancedGeneration &&
        request.name == 'account.getCurrent') {
      _advancedGeneration = true;
      await _host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 8,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
    }
  }

  Future<void> close() async {
    await adapter.close();
    await _subscription.cancel();
    await _session.close();
    await _host.close();
  }
}

final class _LifecycleAccountHostHarness {
  _LifecycleAccountHostHarness({this.loginErrorCode, this.legacy = false}) {
    final pair = InMemoryBridgeConnection.createPair();
    _host = pair.host;
    _session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
      requestTimeout: const Duration(seconds: 1),
    );
    if (legacy) {
      _session.acceptHostCapabilities([
        'account.legacyLogin',
        'account.legacySession',
      ]);
    }
    adapter = BridgeAccountAdapter(_session);
    _subscription = _host.incoming.listen(_respond);
  }

  late final BridgeConnection _host;
  late final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgeAccountAdapter adapter;
  final List<BridgeEnvelope> requests = [];
  final String? loginErrorCode;
  final bool legacy;
  bool _signedIn = false;

  List<String> get requestNames => requests.map((item) => item.name).toList();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    final context = BridgeAccountContext(
      environment: 'synthetic',
      authority: legacy ? 'starbridge-relay-synthetic' : 'scm-test',
      subject: 'synthetic-subject',
    );
    switch (request.name) {
      case 'account.login':
      case 'account.loginLegacy':
        if (loginErrorCode case final code?) {
          await _host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              payload: const <String, Object?>{},
              status: 'error',
              error: BridgeErrorBody(
                code: code,
                message: 'Account environment is not enabled.',
                retryable: false,
              ),
            ),
          );
          return;
        }
        _signedIn = true;
        await _sendResponse(request, const <String, Object?>{
          'schemaVersion': 1,
          'state': 'signedIn',
          'outcome': 'verified',
          'displayName': 'Aster Lin',
          'avatarUrl': null,
        }, context: context);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await _host.send(
          const BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 1,
            sequence: 1,
            payload: <String, Object?>{'schemaVersion': 1},
          ),
        );
      case 'account.logout':
        expect(request.accountContext?.subject, 'synthetic-subject');
        _signedIn = false;
        await _sendResponse(request, const <String, Object?>{
          'schemaVersion': 1,
          'state': 'signedOut',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await _host.send(
          const BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 2,
            sequence: 2,
            payload: <String, Object?>{'schemaVersion': 1},
          ),
        );
      case 'account.getCurrent':
        await _sendResponse(request, <String, Object?>{
          'schemaVersion': 1,
          'state': _signedIn
              ? (legacy ? 'legacySignedIn' : 'signedIn')
              : 'signedOut',
          'displayName': _signedIn ? 'Aster Lin' : null,
          'avatarUrl': null,
        }, context: _signedIn ? context : null);
      case 'profile.getSelf':
        await _sendResponse(request, const <String, Object?>{
          'schemaVersion': 1,
          'profile': <String, Object?>{
            'displayName': 'Aster Lin',
            'avatarUrl': null,
            'email': null,
            'locale': 'zh-CN',
            'timeZone': 'Asia/Shanghai',
          },
          'source': 'live',
          'cachedAtUtc': null,
          'preferencesPolicy': <String, Object?>{
            'locales': <String>['zh-CN', 'en-US'],
            'timeZones': <Object?>[],
          },
        }, context: context);
      case 'gameIdentity.getPolicy':
        await _sendResponse(request, const <String, Object?>{
          'schemaVersion': 1,
          'state': 'match',
          'authoritativeHandle': 'Aster-Lin',
          'sensitiveWritesAllowed': true,
        }, context: context);
      case 'account.getCompatibilityState':
        await _sendResponse(request, const <String, Object?>{
          'schemaVersion': 1,
          'identityState': 'linked',
          'relayState': 'notEstablished',
          'storedLegacyCredentialAvailable': false,
          'legacyFeaturesAvailable': false,
          'availableActions': <String>[],
        }, context: context);
      default:
        throw StateError('Unexpected request ${request.name}');
    }
  }

  Future<void> _sendResponse(
    BridgeEnvelope request,
    Map<String, Object?> payload, {
    BridgeAccountContext? context,
  }) {
    return _host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: context,
        payload: payload,
        status: 'ok',
      ),
    );
  }

  Future<void> close() async {
    await adapter.close();
    await _subscription.cancel();
    await _session.close();
    await _host.close();
  }
}
