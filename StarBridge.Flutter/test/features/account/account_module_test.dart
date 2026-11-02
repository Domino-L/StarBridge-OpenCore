import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  test('refresh during an in-flight read coalesces one later read', () async {
    final port = _HeldRefreshPort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    final reading = module.initialize();
    for (var i = 0; i < 5; i++) {
      await module.refresh();
    }
    expect(port.reads, 1);
    port.first.complete(await port.source.read());
    await reading;
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 2);
    expect(port.source.commands, isEmpty);
  });
  test('queued refresh does not survive disposal', () async {
    final port = _HeldRefreshPort();
    final module = createAccountModule(port);
    final reading = module.initialize();
    await module.refresh();
    final result = await port.source.read();
    module.dispose();
    port.first.complete(result);
    await reading;
    expect(port.reads, 1);
  });
  testWidgets('profile recovery is bounded and cancelled by disposal', (
    tester,
  ) async {
    final port = _RecoveringProfilePort();
    final module = createAccountModule(port);
    await module.initialize();
    for (final seconds in [2, 5, 10, 30, 60]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(port.reads, 5);
    expect(port.commands, isEmpty);
    await module.refresh();
    final count = port.reads;
    module.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(port.reads, count);
  });
  testWidgets('logout cancels cached profile recovery', (tester) async {
    final port = _RecoveringProfilePort();
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    await module.logout();
    final reads = port.reads;
    await tester.pump(const Duration(minutes: 1));
    expect(port.reads, reads);
    expect(module.projection.value.sessionState, AccountSessionState.signedOut);
  });
  testWidgets(
    'cached SCM profile recovers without user action or invalidation',
    (tester) async {
      final port = _RecoveringProfilePort();
      final module = createAccountModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      expect(
        module.projection.value.profileFreshness,
        AccountProfileFreshness.cached,
      );
      port.recovered = true;
      await tester.pump(const Duration(seconds: 3));
      expect(
        module.projection.value.profileFreshness,
        AccountProfileFreshness.live,
      );
      expect(port.commands, isEmpty);
    },
  );
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
    expect(module.takeLoginSuccessFeedback(), isTrue);
    expect(module.takeLoginSuccessFeedback(), isFalse);
    await module.refresh();
    expect(module.takeLoginSuccessFeedback(), isFalse);
    module.dispose();
  });

  test('session restoration does not replay SCM success feedback', () async {
    final module = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await module.initialize();
    expect(module.takeLoginSuccessFeedback(), isFalse);
    await module.refresh();
    expect(module.takeLoginSuccessFeedback(), isFalse);
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

final class _HeldRefreshPort implements AccountPort {
  final first = Completer<AccountPortResult>();
  final source = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  int reads = 0;
  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();
  @override
  Future<AccountPortResult> read() => ++reads == 1 ? first.future : source.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) => source.execute(command);
  @override
  Future<void> close() => source.close();
}

final class _RecoveringProfilePort implements AccountPort {
  bool recovered = false;
  int reads = 0;
  final cached = InMemoryAccountAdapter.forReview(AccountReviewState.cached);
  final live = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  final List<AccountPortCommand> commands = [];
  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();
  @override
  Future<AccountPortResult> read() {
    reads++;
    return recovered ? live.read() : cached.read();
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) {
    commands.add(command);
    return live.execute(command);
  }

  @override
  Future<void> close() async {
    await cached.close();
    await live.close();
  }
}
