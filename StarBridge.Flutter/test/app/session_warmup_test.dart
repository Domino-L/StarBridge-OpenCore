import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/session_warmup.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';

AccountProjection accountState(
  AccountSessionState state, {
  int generation = 1,
}) => const AccountProjection.loading().copyWith(
  sessionState: state,
  operation: AccountOperation.none,
  generation: generation,
);

void main() {
  testWidgets('failed startup job does not discard remaining idle work', (
    tester,
  ) async {
    final account = ValueNotifier(accountState(AccountSessionState.signedIn));
    var calls = 0;
    final warmup = SessionWarmup(
      account: account,
      jobs: [() async => throw StateError('offline')],
      continueWork: () async {
        calls++;
        return false;
      },
    );
    addTearDown(account.dispose);
    addTearDown(warmup.dispose);
    warmup.start();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
  });
  testWidgets(
    'idle continuation drains, wakes for new work, and yields to input',
    (tester) async {
      final account = ValueNotifier(accountState(AccountSessionState.signedIn));
      final changes = ChangeNotifier();
      var remaining = 5, startup = 0, batches = 0;
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            startup++;
          },
        ],
        workChanges: changes,
        continueWork: () async {
          if (remaining == 0) return false;
          remaining--;
          batches++;
          return true;
        },
      );
      addTearDown(account.dispose);
      addTearDown(changes.dispose);
      addTearDown(warmup.dispose);
      warmup.start();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      expect((startup, batches), (1, 5));
      remaining = 2;
      await tester.pump(const Duration(seconds: 2));
      expect(batches, 5);
      changes.notifyListeners();
      warmup.deferForInteraction();
      await tester.pump(const Duration(milliseconds: 350));
      expect(batches, 5);
      warmup.setForeground(false);
      await tester.pump(const Duration(seconds: 2));
      expect(batches, 5);
      warmup.setForeground(true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect((startup, batches), (1, 7));
    },
  );
  testWidgets(
    'only mounted ready session warms once, in separate bounded batches',
    (tester) async {
      final account = ValueNotifier(accountState(AccountSessionState.loading));
      final calls = <int>[];
      final pending = Completer<void>();
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            calls.add(1);
            await pending.future;
          },
          () async {
            calls.add(2);
          },
        ],
      );
      addTearDown(account.dispose);
      addTearDown(warmup.dispose);
      account.value = accountState(AccountSessionState.signedIn);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, isEmpty);
      warmup.start();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, [1]);
      await tester.pump(const Duration(seconds: 3));
      expect(calls, [1]);
      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, [1, 2]);
      account.value = account.value.copyWith(
        profile: const AccountProfile(displayName: 'Updated'),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(calls, [1, 2]);
    },
  );

  testWidgets(
    'interaction and background pause unstarted work without consuming input',
    (tester) async {
      final account = ValueNotifier(
        accountState(AccountSessionState.legacySignedIn),
      );
      var reads = 0;
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            reads++;
          },
        ],
      );
      addTearDown(account.dispose);
      addTearDown(warmup.dispose);
      warmup.start();
      warmup.deferForInteraction();
      await tester.pump(const Duration(milliseconds: 350));
      expect(reads, 0);
      warmup.setForeground(false);
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 0);
      warmup.setForeground(true);
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 1);
    },
  );

  testWidgets(
    'logout drops old queue; new generation starts a new bounded queue',
    (tester) async {
      final account = ValueNotifier(accountState(AccountSessionState.signedIn));
      final pending = Completer<void>();
      final calls = <String>[];
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            calls.add('${account.value.generation}:first');
            if (account.value.generation == 1) await pending.future;
          },
          () async {
            calls.add('${account.value.generation}:second');
          },
        ],
      );
      addTearDown(account.dispose);
      addTearDown(warmup.dispose);
      warmup.start();
      await tester.pump(const Duration(milliseconds: 300));
      account.value = accountState(
        AccountSessionState.signedOut,
        generation: 2,
      );
      pending.complete();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, ['1:first']);
      account.value = accountState(AccountSessionState.signedIn, generation: 3);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, ['1:first', '3:first', '3:second']);
    },
  );

  testWidgets(
    'failure does not retry forever and dispose cancels remaining work',
    (tester) async {
      final account = ValueNotifier(accountState(AccountSessionState.signedIn));
      var reads = 0;
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            reads++;
            throw StateError('offline');
          },
          () async {
            reads++;
          },
        ],
      );
      addTearDown(account.dispose);
      warmup.start();
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, 1);
      warmup.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in [
    AccountSessionState.signedOut,
    AccountSessionState.legacyUnavailable,
    AccountSessionState.reauthorizationRequired,
  ]) {
    testWidgets('$state never starts speculative private reads', (
      tester,
    ) async {
      final account = ValueNotifier(accountState(state));
      var reads = 0;
      final warmup = SessionWarmup(
        account: account,
        jobs: [
          () async {
            reads++;
          },
        ],
      );
      addTearDown(account.dispose);
      addTearDown(warmup.dispose);
      warmup.start();
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 0);
    });
  }
}
