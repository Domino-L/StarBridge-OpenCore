import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  test('initializes signed out without inventing an account', () async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedOut,
    );
    final module = createAccountModule(adapter);

    expect((await module.initialize()).outcome, AccountActionOutcome.completed);
    expect(module.projection.value.sessionState, AccountSessionState.signedOut);
    expect(module.projection.value.profile, isNull);
    expect(module.projection.value.canLogin, isTrue);
    module.dispose();
  });

  test(
    'temporary credential outage offers restore retry without a new login',
    () async {
      final adapter = InMemoryAccountAdapter(
        initial: const AccountHostSnapshot(
          generation: 0,
          sessionState: AccountSessionState.credentialTemporarilyUnavailable,
          profileFreshness: AccountProfileFreshness.unavailable,
          identity: AccountIdentityProjection.unavailable(),
          compatibility: AccountCompatibilityProjection.unavailable(),
          localeOptions: [],
          timeZoneOptions: [],
        ),
      );
      final module = createAccountModule(adapter);

      await module.initialize();

      expect(module.projection.value.canLogin, isFalse);
      expect(module.projection.value.canRetrySessionRestore, isTrue);
      module.dispose();
    },
  );

  test('reauthorization permits only a new authorization flow', () async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.reauthorizationRequired,
    );
    final module = createAccountModule(adapter);

    await module.initialize();

    expect(module.projection.value.canLogin, isTrue);
    expect(module.projection.value.canRetrySessionRestore, isFalse);
    expect(module.projection.value.canLogout, isFalse);
    module.dispose();
  });

  test('login advances generation and publishes the Host snapshot', () async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedOut,
    );
    final module = createAccountModule(adapter);
    await module.initialize();

    final result = await module.beginLogin();
    await _waitFor(() => !module.projection.value.isBusy);

    expect(result.outcome, AccountActionOutcome.completed);
    expect(module.projection.value.sessionState, AccountSessionState.signedIn);
    expect(module.projection.value.generation, 1);
    expect(module.projection.value.profile?.displayName, 'Aster Lin');
    expect(module.projection.value.identity.sensitiveWritesAllowed, isTrue);
    module.dispose();
  });

  test('cancel login restores an actionable signed-out state', () async {
    final adapter = InMemoryAccountAdapter(
      initial: const AccountHostSnapshot.signedOut(generation: 0),
      holdLoginUntilCancelled: true,
    );
    final module = createAccountModule(adapter);
    await module.initialize();

    final login = module.beginLogin();
    await _waitFor(
      () => module.projection.value.operation == AccountOperation.signingIn,
    );
    final cancellation = await module.cancelLogin();
    final staleLogin = await login;

    expect(cancellation.outcome, AccountActionOutcome.cancelled);
    expect(staleLogin.outcome, AccountActionOutcome.stale);
    expect(module.projection.value.sessionState, AccountSessionState.signedOut);
    expect(module.projection.value.canLogin, isTrue);
    module.dispose();
  });

  test('preference save sends only fields that changed', () async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedIn,
    );
    final module = createAccountModule(adapter);
    await module.initialize();

    await module.savePreferences(locale: 'zh-CN', timeZone: 'America/Regina');
    final command = adapter.commands.whereType<SaveAccountPreferences>().single;

    expect(command.patch.localeSpecified, isFalse);
    expect(command.patch.timeZoneSpecified, isTrue);
    expect(command.patch.timeZone, 'America/Regina');
    expect(module.projection.value.profile?.timeZone, 'America/Regina');
    module.dispose();
  });

  test('cached profile is readable but not writable', () async {
    final adapter = InMemoryAccountAdapter.forReview(AccountReviewState.cached);
    final module = createAccountModule(adapter);
    await module.initialize();

    expect(
      module.projection.value.profileFreshness,
      AccountProfileFreshness.cached,
    );
    expect(module.projection.value.canEditPreferences, isFalse);
    expect(
      (await module.savePreferences(locale: 'en-US', timeZone: 'UTC')).outcome,
      AccountActionOutcome.rejected,
    );
    module.dispose();
  });

  test(
    'legacy link can be cancelled without inventing a linked state',
    () async {
      final source = InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      );
      final initial = source.snapshot;
      await source.close();
      final adapter = InMemoryAccountAdapter(
        initial: initial,
        holdCompatibilityUntilCancelled: true,
      );
      final module = createAccountModule(adapter);
      await module.initialize();

      final link = module.linkLegacyAccount(
        accountName: 'legacy@example.com',
        password: 'synthetic-password',
      );
      await _waitFor(
        () =>
            module.projection.value.operation ==
            AccountOperation.linkingLegacyAccount,
      );
      final cancellation = await module.cancelCompatibilityOperation();
      final staleLink = await link;

      expect(cancellation.outcome, AccountActionOutcome.cancelled);
      expect(staleLink.outcome, AccountActionOutcome.stale);
      expect(
        module.projection.value.compatibility.identityState,
        AccountCompatibilityIdentityState.unlinked,
      );
      expect(
        module.projection.value.notice?.messageKey,
        'account.compatibility.cancelled',
      );
      module.dispose();
    },
  );

  test('retryable failure preserves the last trustworthy projection', () async {
    final adapter = InMemoryAccountAdapter.forReview(
      AccountReviewState.signedIn,
    );
    final module = createAccountModule(adapter);
    await module.initialize();
    adapter.nextFailure = const AccountFailure(
      code: 'bridge.disconnected',
      messageKey: 'account.error.hostUnavailable',
      retryable: true,
    );

    final result = await module.refresh();

    expect(result.outcome, AccountActionOutcome.failed);
    expect(module.projection.value.profile?.displayName, 'Aster Lin');
    expect(module.projection.value.failure?.retryable, isTrue);
    expect(module.projection.value.operation, AccountOperation.none);
    module.dispose();
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
