import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  test(
    'legacy account photo reaches chrome and is cleared on logout',
    () async {
      final module = createAccountModule(
        InMemoryAccountAdapter(
          initial: const AccountHostSnapshot(
            generation: 1,
            sessionState: AccountSessionState.legacySignedIn,
            profileFreshness: AccountProfileFreshness.live,
            profile: AccountProfile(
              displayName: 'Commander',
              avatarImageData: 'original-photo',
            ),
            identity: AccountIdentityProjection.unavailable(),
            compatibility: AccountCompatibilityProjection.unavailable(),
            localeOptions: [],
            timeZoneOptions: [],
          ),
        ),
      );
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: module,
      );
      addTearDown(() {
        chrome.dispose();
        module.dispose();
      });
      await module.initialize();
      expect(chrome.projection.value.accountAvatarImageData, 'original-photo');
      await module.logout();
      expect(chrome.projection.value.accountAvatarImageData, isNull);
      expect(chrome.projection.value.accountSignedIn, isFalse);
    },
  );
  test(
    'automatic restore generation change stays loading without a false error',
    () async {
      final port = _RestoringAccountPort();
      final module = createAccountModule(port);
      final errors = <AccountFailure?>[];
      module.projection.addListener(
        () => errors.add(module.projection.value.failure),
      );
      addTearDown(module.dispose);
      final initial = module.initialize();
      port.events.add(const AccountInvalidation(generation: 1));
      port.first.complete(
        const AccountPortResult.failed(
          AccountFailure(
            code: 'bridge.stale_generation',
            messageKey: 'account.error.sessionChanged',
            retryable: false,
          ),
        ),
      );
      await initial;
      expect(module.projection.value.isBusy, isTrue);
      expect(module.projection.value.failure, isNull);
      expect(errors.whereType<AccountFailure>(), isEmpty);
      port.second.complete(
        const AccountPortResult.completed(
          AccountHostSnapshot.signedOut(generation: 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(module.projection.value.generation, 1);
      expect(module.projection.value.isBusy, isFalse);
    },
  );

  test(
    'failed account read remains visible while retry is in flight',
    () async {
      final adapter =
          InMemoryAccountAdapter.forReview(AccountReviewState.signedIn)
            ..nextFailure = const AccountFailure(
              code: 'bridge.timeout',
              messageKey: 'account.error.timeout',
              retryable: true,
            );
      final module = createAccountModule(adapter);
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: module,
      );
      addTearDown(() {
        chrome.dispose();
        module.dispose();
      });
      await module.initialize();
      final issue = chrome.projection.value.connectionIssue;
      expect(issue, isNotNull);
      final retry = module.refresh();
      expect(chrome.projection.value.accountBusy, isTrue);
      expect(chrome.projection.value.connectionIssue, isNotNull);
      expect(
        chrome.projection.value.connectionIssue?.detailKey,
        issue!.detailKey,
      );
      expect(chrome.projection.value.connectionIssueUsesAccountAction, isTrue);
      await retry;
      expect(chrome.projection.value.accountBusy, isFalse);
      expect(chrome.projection.value.connectionIssue, isNull);
    },
  );

  test('overlapping refresh does not enqueue a second account read', () async {
    final adapter = InMemoryAccountAdapter();
    final module = createAccountModule(adapter);
    addTearDown(module.dispose);
    final first = module.initialize();
    final repeated = module.refresh();
    expect(adapter.readCount, 1);
    await first;
    expect((await repeated).outcome, AccountActionOutcome.rejected);
  });

  test(
    'temporary SCM credential outage marks shell sync as needing attention',
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
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: module,
      );

      await module.initialize();

      expect(chrome.projection.value.syncKey, 'sync.issue');
      expect(chrome.projection.value.accountSignedIn, isFalse);
      expect(
        chrome.projection.value.accountIssue?.domain,
        ConnectionStatusDomain.network,
      );
      expect(
        chrome.projection.value.accountIssue?.state,
        ConnectionVisualState.disconnected,
      );
      expect(
        chrome.projection.value.accountIssue?.titleKey,
        'connection.account.unavailable.title',
      );
      expect(
        chrome.projection.value.connectionIssue?.titleKey,
        'connection.account.unavailable.title',
      );
      expect(chrome.projection.value.connectionIssueUsesAccountAction, isTrue);
      chrome.dispose();
      module.dispose();
    },
  );

  test(
    'SCM reauthorization requirement marks shell sync as needing attention',
    () async {
      final adapter = InMemoryAccountAdapter.forReview(
        AccountReviewState.reauthorizationRequired,
      );
      final module = createAccountModule(adapter);
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: module,
      );

      await module.initialize();

      expect(chrome.projection.value.syncKey, 'sync.issue');
      expect(chrome.projection.value.accountSignedIn, isFalse);
      expect(
        chrome.projection.value.accountIssue?.domain,
        ConnectionStatusDomain.identity,
      );
      expect(
        chrome.projection.value.accountIssue?.state,
        ConnectionVisualState.limited,
      );
      expect(
        chrome.projection.value.accountIssue?.titleKey,
        'connection.account.reauthorize.title',
      );
      expect(
        chrome.projection.value.connectionIssue?.titleKey,
        'connection.account.reauthorize.title',
      );
      expect(chrome.projection.value.connectionIssueUsesAccountAction, isTrue);
      chrome.dispose();
      module.dispose();
    },
  );

  test(
    'healthy SCM account leaves the global status notice collapsed',
    () async {
      final module = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: module,
      );

      await module.initialize();

      expect(chrome.projection.value.connectionIssue, isNull);
      expect(chrome.projection.value.accountIssue, isNull);
      expect(chrome.projection.value.connectionIssueUsesAccountAction, isFalse);
      expect(chrome.projection.value.syncKey, 'sync.current');
      chrome.dispose();
      module.dispose();
    },
  );

  for (final identityState in [
    AccountCompatibilityIdentityState.linked,
    AccountCompatibilityIdentityState.unavailable,
  ]) {
    test(
      '$identityState retired compatibility cannot raise an account or status warning',
      () async {
        final module = createAccountModule(
          InMemoryAccountAdapter(
            initial: AccountHostSnapshot(
              generation: 4,
              sessionState: AccountSessionState.signedIn,
              profileFreshness: AccountProfileFreshness.live,
              identity: const AccountIdentityProjection.unavailable(),
              compatibility: AccountCompatibilityProjection(
                identityState: identityState,
                relayState: AccountCompatibilityRelayState.unavailable,
                storedLegacyCredentialAvailable: true,
                legacyFeaturesAvailable: false,
                availableActions: [AccountCompatibilityAction.retry],
              ),
              localeOptions: [],
              timeZoneOptions: [],
            ),
          ),
        );
        final chrome = AccountShellChrome(
          base: InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          ),
          account: module,
        );

        await module.initialize();

        expect(chrome.projection.value.accountIssue, isNull);
        expect(chrome.projection.value.connectionIssue, isNull);
        expect(
          chrome.projection.value.connectionIssueUsesAccountAction,
          isFalse,
        );
        expect(chrome.projection.value.syncKey, 'sync.current');
        expect(chrome.projection.value.accountSignedIn, isTrue);
        chrome.dispose();
        module.dispose();
      },
    );
  }

  test(
    'account and host issues remain on their own presentation paths',
    () async {
      final module = createAccountModule(
        InMemoryAccountAdapter.forReview(
          AccountReviewState.reauthorizationRequired,
        ),
      );
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.disconnectedProjection,
        ),
        account: module,
      );

      await module.initialize();

      expect(
        chrome.projection.value.connectionIssue?.titleKey,
        'connection.host.disconnected.title',
      );
      expect(
        chrome.projection.value.accountIssue?.titleKey,
        'connection.account.reauthorize.title',
      );
      expect(chrome.projection.value.connectionIssueUsesAccountAction, isFalse);
      chrome.dispose();
      module.dispose();
    },
  );
}

final class _RestoringAccountPort implements AccountPort {
  final events = StreamController<AccountInvalidation>.broadcast(sync: true);
  final first = Completer<AccountPortResult>();
  final second = Completer<AccountPortResult>();
  int reads = 0;
  @override
  Stream<AccountInvalidation> get invalidations => events.stream;
  @override
  Future<AccountPortResult> read() =>
      ++reads == 1 ? first.future : second.future;
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      throw UnimplementedError();
  @override
  Future<void> close() => events.close();
}
