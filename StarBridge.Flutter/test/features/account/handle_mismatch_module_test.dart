import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/app/composition/handle_mismatch_module.dart';
import 'package:starbridge_flutter/features/account/handle_mismatch_port.dart';

AccountProjection projection({
  int generation = 7,
  String? detected = 'Pilot-Alpha',
  AccountIdentityState state = AccountIdentityState.mismatch,
}) => const AccountProjection.loading().copyWith(
  sessionState: AccountSessionState.legacySignedIn,
  operation: AccountOperation.none,
  generation: generation,
  identity: AccountIdentityProjection(
    state: state,
    sensitiveWritesAllowed: false,
    authoritativeHandle: 'Pilot_Alpha',
    detectedHandle: detected,
  ),
);

final class _Port implements HandleMismatchPort {
  final pending = Completer<HandleCheckResult>();
  var checks = 0;
  @override
  Future<HandleCheckResult> check(int generation) {
    checks++;
    return pending.future;
  }

  @override
  Future<HandleNotificationReceipt?> notifyBackground(int generation) async =>
      HandleNotificationReceipt(generation, 'Pilot_Alpha', 'Pilot-Alpha');
}

final class _Writable implements HandleMismatchPort, LegacyHandleChangePort {
  final completion = Completer<void>();
  int writes = 0, cancels = 0;
  @override
  Future<HandleCheckResult> check(int generation) async => HandleCheckResult(
    HandleCheckState.ready,
    'Pilot_Alpha',
    'Pilot-Alpha',
    confirmationId: 'a' * 32,
  );
  @override
  Future<void> confirm(int generation, String confirmationId) {
    writes++;
    return completion.future;
  }

  @override
  Future<void> cancel(int generation, String confirmationId) async {
    cancels++;
  }

  @override
  Future<HandleNotificationReceipt?> notifyBackground(int generation) async =>
      null;
}

void main() {
  for (final mode in ['failure', 'late', 'cancel']) {
    test('confirmation $mode cannot clear evidence or replay writes', () async {
      final account = ValueNotifier(projection());
      final port = _Writable();
      var refreshes = 0;
      final module = HandleMismatchModule(
        account: account,
        gameLog: null,
        port: port,
        refresh: () async {
          refreshes++;
        },
      );
      addTearDown(module.dispose);
      addTearDown(account.dispose);
      await module.recheck();
      expect(module.canConfirm, isTrue);
      if (mode == 'cancel') {
        module.dismissConfirmation(module.notice!.key);
        await module.confirm();
        expect(port.writes, 0);
        expect(port.cancels, 1);
      } else {
        final operation = module.confirm();
        await module.confirm();
        expect(port.writes, 1);
        if (mode == 'late') {
          account.value = projection(generation: 8, detected: 'Other-Pilot');
          port.completion.complete();
        } else {
          port.completion.completeError(
            const FormatException('synthetic uncertain outcome'),
          );
        }
        await operation;
        await module.confirm();
        expect(port.writes, 1);
        expect(refreshes, 1); // prepare only, never refresh a stale owner
      }
      expect(module.notice, isNotNull);
      expect(module.canConfirm, isFalse);
    });
  }
  test('missing observation keeps persisted mismatch; punctuation is not normalized', () {
    final account = ValueNotifier(projection(detected: null));
    final module = HandleMismatchModule(
      account: account,
      gameLog: null,
      port: null,
      refresh: () async {},
    );
    expect(module.notice, isNotNull);
    expect(module.notice!.hasPair, isFalse);
    account.value = projection();
    expect(module.notice!.hasPair, isTrue);
    expect(module.notice!.key, (7, 'pilot_alpha', 'pilot-alpha'));
    account.value = projection(detected: null);
    expect(module.notice!.key, (7, 'pilot_alpha', 'pilot-alpha'));
    module.dispose();
    account.dispose();
  });

  for (final state in [
    AccountSessionState.loading,
    AccountSessionState.legacyUnavailable,
    AccountSessionState.credentialTemporarilyUnavailable,
    AccountSessionState.reauthorizationRequired,
  ]) {
    test(
      'transient $state retains evidence until explicit owner invalidation',
      () {
        final account = ValueNotifier(projection());
        final module = HandleMismatchModule(
          account: account,
          gameLog: null,
          port: null,
          refresh: () async {},
        );
        final key = module.notice!.key;
        account.value = account.value.copyWith(
          sessionState: state,
          identity: const AccountIdentityProjection.unavailable(),
        );
        expect(module.notice!.key, key);
        account.value = account.value.copyWith(
          sessionState: AccountSessionState.signedOut,
        );
        expect(module.notice, isNull);
        module.dispose();
        account.dispose();
      },
    );
  }

  test('a late check cannot refresh, fail or affect a new account', () async {
    final account = ValueNotifier(projection());
    final port = _Port();
    var refreshes = 0;
    final module = HandleMismatchModule(
      account: account,
      gameLog: null,
      port: port,
      refresh: () async {
        refreshes++;
      },
    );
    final pending = module.recheck();
    await module.recheck();
    expect(port.checks, 1);
    account.value = projection(generation: 8, detected: 'New-Pilot');
    port.pending.complete(
      const HandleCheckResult(
        HandleCheckState.unknown,
        'Pilot_Alpha',
        'Pilot-Alpha',
      ),
    );
    await pending;
    expect(refreshes, 0);
    expect(module.notice!.key, (8, 'pilot_alpha', 'new-pilot'));
    expect(module.busy, isFalse);
    expect(module.failed, isFalse);
    module.dispose();
    account.dispose();
  });

  test(
    'a consistent check is not authority to clear persisted mismatch by itself',
    () async {
      final account = ValueNotifier(projection());
      final port = _Port();
      var refreshes = 0;
      final module = HandleMismatchModule(
        account: account,
        gameLog: null,
        port: port,
        refresh: () async {
          refreshes++;
        },
      );
      final pending = module.recheck();
      port.pending.complete(
        const HandleCheckResult(
          HandleCheckState.consistent,
          'Pilot_Alpha',
          'Pilot_Alpha',
        ),
      );
      await pending;
      expect(refreshes, 1);
      expect(module.notice, isNotNull);
      account.value = projection(
        detected: 'Pilot_Alpha',
        state: AccountIdentityState.match,
      );
      expect(module.notice, isNull);
      module.dispose();
      account.dispose();
    },
  );
}
