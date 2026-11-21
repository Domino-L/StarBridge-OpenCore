// Account plan item 9: migration entry, controller projection and result.
import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_migration.dart';
import 'package:starbridge_flutter/features/account/account_migration_card.dart';
import 'package:starbridge_flutter/features/account/account_migration_confirm.dart';
import 'package:starbridge_flutter/features/account/account_migration_controller.dart';
import 'package:starbridge_flutter/features/account/account_migration_result.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/bridge_account_migration.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;

Map<String, Object?> reading({
  bool available = true,
  String state = 'completed',
  bool recoveryRequired = false,
  String localData = 'linked',
  bool resultPending = true,
}) => {
  'schemaVersion': 1,
  'available': available,
  'state': state,
  'friends': 12,
  'communities': 3,
  'merged': 2,
  'recoveryRequired': recoveryRequired,
  'localData': localData,
  'resultPending': resultPending,
};

final class FakeMigration implements AccountMigrationPort {
  Map<String, Object?> next = reading();
  int reads = 0, refreshes = 0, retries = 0, acknowledged = 0;
  @override
  bool supported = true;
  @override
  Future<AccountMigrationReading> read({bool refresh = false}) async {
    reads++;
    if (refresh) refreshes++;
    return AccountMigrationReading.parse(next);
  }

  @override
  Future<AccountMigrationReading> retry() async {
    retries++;
    return AccountMigrationReading.parse(next);
  }

  @override
  Future<void> acknowledge() async => acknowledged++;
}

AccountProjection account({
  AccountCompatibilityIdentityState identity =
      AccountCompatibilityIdentityState.linked,
  AccountCompatibilityRelayState relay = AccountCompatibilityRelayState.ready,
  int generation = 1,
}) => const AccountProjection.loading().copyWith(
  sessionState: AccountSessionState.signedIn,
  generation: generation,
  operation: AccountOperation.none,
  compatibility: AccountCompatibilityProjection(
    identityState: identity,
    relayState: relay,
    storedLegacyCredentialAvailable: false,
    legacyFeaturesAvailable: false,
    availableActions: const [],
  ),
);

void main() {
  test('the Host reading is parsed strictly and carries no account ID', () {
    final parsed = AccountMigrationReading.parse(reading());
    expect(parsed.state, 'completed');
    expect(parsed.friends, 12);
    expect(parsed.localData, AccountMigrationLocalData.linked);
    for (final broken in [
      {...reading(), 'schemaVersion': 2},
      {...reading(), 'state': 'done'},
      {...reading(), 'friends': -1},
      {...reading(), 'localData': 'written'},
      {...reading(), 'resultPending': 'yes'},
    ]) {
      expect(
        () => AccountMigrationReading.parse(broken),
        throwsFormatException,
      );
    }
  });

  test('the relay state "migrated" is decoded', () {
    final decoded = AccountPayloadDecoder.compatibility({
      'schemaVersion': 1,
      'identityState': 'linked',
      'relayState': 'migrated',
      'storedLegacyCredentialAvailable': false,
      'legacyFeaturesAvailable': false,
      'availableActions': <Object?>[],
    }, canLinkExisting: false);
    expect(decoded.relayState, AccountCompatibilityRelayState.migrated);
    expect(decoded.legacyFeaturesAvailable, isFalse);
  });

  group('controller projection', () {
    Future<AccountMigrationView> project(
      Map<String, Object?> next, {
      AccountCompatibilityIdentityState identity =
          AccountCompatibilityIdentityState.linked,
      AccountCompatibilityRelayState relay =
          AccountCompatibilityRelayState.ready,
    }) async {
      final port = FakeMigration()..next = next;
      final controller = AccountMigrationController(
        port,
        ValueNotifier(account(identity: identity, relay: relay)),
        pollFor: Duration.zero,
      );
      await pumpEventQueue();
      final view = controller.value;
      controller.dispose();
      return view;
    }

    test('switch off: nothing is offered', () async {
      expect(
        (await project(reading(available: false))).state,
        AccountMigrationState.unavailable,
      );
    });
    test('switch off but already migrated: the card stays migrated', () async {
      final view = await project(
        reading(available: false),
        relay: AccountCompatibilityRelayState.migrated,
      );
      expect(view.state, AccountMigrationState.completed);
      expect(view.resultAvailable, isFalse);
    });
    test('unlinked with nothing migrated: the entry', () async {
      expect(
        (await project(
          reading(state: 'none', resultPending: false),
          identity: AccountCompatibilityIdentityState.unlinked,
        )).state,
        AccountMigrationState.notLinked,
      );
    });
    test('linked and not yet migrated: waiting for the relay', () async {
      expect(
        (await project(reading(state: 'none', resultPending: false))).state,
        AccountMigrationState.migrating,
      );
    });
    test('failed and recovery are told apart', () async {
      expect(
        (await project(reading(state: 'failed', resultPending: false))).state,
        AccountMigrationState.failed,
      );
      expect(
        (await project(
          reading(
            state: 'failed',
            recoveryRequired: true,
            resultPending: false,
          ),
        )).state,
        AccountMigrationState.recoveryRequired,
      );
    });
    test('completed keeps the counts and local data', () async {
      final view = await project(reading(localData: 'pending'));
      expect(view.state, AccountMigrationState.completed);
      expect((view.friends, view.communities, view.merged), (12, 3, 2));
      expect(view.localData, AccountMigrationLocalData.pending);
    });
  });

  test('migrating: every 2 s for 30 s, then once a minute for an hour', () {
    fakeAsync((async) {
      final port = FakeMigration()..next = reading(state: 'migrating');
      final controller = AccountMigrationController(
        port,
        ValueNotifier(account()),
      );
      async.flushMicrotasks();
      expect(controller.value.state, AccountMigrationState.migrating);
      async.elapse(const Duration(seconds: 10));
      expect(port.reads, greaterThan(3));
      async.elapse(const Duration(seconds: 25));
      final quick = port.reads;
      expect(quick, lessThanOrEqualTo(17));
      expect(controller.value.stillWorking, isTrue);
      async.elapse(const Duration(minutes: 5));
      expect(
        port.reads - quick,
        inInclusiveRange(4, 6),
        reason: 'one a minute',
      );
      async.elapse(const Duration(hours: 2));
      final capped = port.reads;
      expect(capped - quick, lessThanOrEqualTo(61));
      async.elapse(const Duration(hours: 1));
      expect(port.reads, capped, reason: 'bounded, no endless polling');
      controller.dispose();
    });
  });

  test('a migration finishing after 30 s still reaches the card', () {
    fakeAsync((async) {
      final port = FakeMigration()..next = reading(state: 'migrating');
      final controller = AccountMigrationController(
        port,
        ValueNotifier(account()),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 3));
      expect(controller.value.stillWorking, isTrue);
      port.next = reading();
      async.elapse(const Duration(minutes: 1, seconds: 1));
      expect(controller.value.state, AccountMigrationState.completed);
      expect(controller.resultPending, isTrue);
      final reads = port.reads;
      async.elapse(const Duration(minutes: 10));
      expect(port.reads, reads, reason: 'polling stops once it is done');
      controller.dispose();
    });
  });

  test('the card and the startup prompt share one controller', () {
    final projection = ValueNotifier(account());
    final controller = AccountMigrationController(
      FakeMigration(),
      projection,
      pollFor: Duration.zero,
    )..shareThrough(projection);
    expect(AccountMigrationController.sharedFor(projection), same(controller));
    expect(
      AccountMigrationController.sharedFor(ValueNotifier(account())),
      null,
    );
    controller.dispose();
  });

  test('only one result dialog at a time, and it is marked once', () async {
    final port = FakeMigration();
    final controller = AccountMigrationController(
      port,
      ValueNotifier(account()),
      pollFor: Duration.zero,
    );
    await pumpEventQueue();
    final open = Completer<void>();
    var shown = 0;
    final first = controller.present((_) {
      shown++;
      return open.future;
    });
    expect(controller.presenting, isTrue);
    await controller.present((_) async => shown++);
    expect(shown, 1, reason: 'the second one is not shown over the first');
    open.complete();
    await first;
    expect(controller.presenting, isFalse);
    expect(port.acknowledged, 1);
    controller.dispose();
  });

  test('a read started before the mark cannot bring the result back', () async {
    final port = _SlowMigration();
    final controller = AccountMigrationController(
      port,
      ValueNotifier(account()),
      pollFor: Duration.zero,
    );
    await pumpEventQueue();
    port.release();
    await pumpEventQueue();
    expect(controller.resultPending, isTrue);
    final late = controller.load();
    await pumpEventQueue();
    await controller.acknowledge();
    port.release();
    await late;
    expect(controller.resultPending, isFalse);
    controller.dispose();
  });

  testWidgets('submitting clears the password field', (tester) async {
    String? sent;
    await tester.pumpWidget(
      support.app(
        AccountMigrationConfirm(
          onSubmit: (name, password, _) => sent = '$name/$password',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-migrate-name')),
      'old@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('account-migrate-password')),
      'pw-example',
    );
    await tester.tap(find.byKey(const Key('account-migrate-confirm-submit')));
    await tester.pump();
    expect(sent, 'old@example.invalid/pw-example');
    final field = tester.widget<TextField>(
      find.byKey(const Key('account-migrate-password')),
    );
    expect(field.controller!.text, isEmpty);
  });

  Future<BuildContext> rootContext(WidgetTester tester) async {
    late BuildContext root;
    await tester.pumpWidget(
      support.app(
        Builder(
          builder: (context) {
            root = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return root;
  }

  const result = AccountMigrationView(
    AccountMigrationState.completed,
    friends: 12,
  );

  testWidgets('the result dialog closes when the session changes', (
    tester,
  ) async {
    final projection = ValueNotifier(account());
    final root = await rootContext(tester);
    unawaited(
      showAccountMigrationResult(
        root,
        result,
        owner: (account: projection, generation: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountMigrationResult), findsOneWidget);
    projection.value = account(relay: AccountCompatibilityRelayState.migrated);
    await tester.pumpAndSettle();
    expect(
      find.byType(AccountMigrationResult),
      findsOneWidget,
      reason: 'same session',
    );
    projection.value = account(generation: 2);
    await tester.pumpAndSettle();
    expect(find.byType(AccountMigrationResult), findsNothing);
  });

  testWidgets('a session that changes before the first frame never sees it', (
    tester,
  ) async {
    final projection = ValueNotifier(account());
    final root = await rootContext(tester);
    var done = false;
    unawaited(
      showAccountMigrationResult(
        root,
        result,
        owner: (account: projection, generation: 1),
      ).then((_) => done = true),
    );
    // B signs in after A's result was pushed, before it was ever built.
    projection.value = account(generation: 2);
    await tester.pumpAndSettle();
    expect(find.byType(AccountMigrationResult), findsNothing);
    expect(done, isTrue);
    // Already changed when the caller decided: not shown at all.
    unawaited(
      showAccountMigrationResult(
        root,
        result,
        owner: (account: projection, generation: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountMigrationResult), findsNothing);
  });

  testWidgets('a lost session removes only its own dialog', (tester) async {
    final projection = ValueNotifier(account());
    final root = await rootContext(tester);
    unawaited(
      showAccountMigrationResult(
        root,
        result,
        owner: (account: projection, generation: 1),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: root,
        builder: (_) => const Dialog(child: Text('above')),
      ),
    );
    await tester.pumpAndSettle();
    projection.value = account(generation: 2);
    await tester.pumpAndSettle();
    expect(find.text('above'), findsOneWidget, reason: 'not ours to close');
    expect(find.byType(AccountMigrationResult), findsNothing);
  });

  testWidgets('a dialog already closing leaves the next route alone', (
    tester,
  ) async {
    final projection = ValueNotifier(account());
    final root = await rootContext(tester);
    unawaited(
      showAccountMigrationResult(
        root,
        result,
        owner: (account: projection, generation: 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-migrate-done')));
    await tester.pump();
    // Still running its exit animation when the next dialog opens.
    unawaited(
      showDialog<void>(
        context: root,
        builder: (_) => const Dialog(child: Text('next')),
      ),
    );
    await tester.pump();
    projection.value = account(generation: 2);
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
    expect(find.byType(AccountMigrationResult), findsNothing);
  });

  test('disposing the shared controller ends its polling and sharing', () {
    fakeAsync((async) {
      final port = FakeMigration()..next = reading(state: 'migrating');
      final projection = ValueNotifier(account());
      final controller = AccountMigrationController(port, projection)
        ..shareThrough(projection);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      controller.dispose();
      expect(AccountMigrationController.sharedFor(projection), null);
      final reads = port.reads;
      async.elapse(const Duration(hours: 2));
      expect(port.reads, reads, reason: 'no timer outlives its owner');
    });
  });

  test('acknowledging marks the result once', () async {
    final port = FakeMigration();
    final controller = AccountMigrationController(
      port,
      ValueNotifier(account()),
      pollFor: Duration.zero,
    );
    await pumpEventQueue();
    expect(controller.resultPending, isTrue);
    await controller.acknowledge();
    await controller.acknowledge();
    expect(controller.resultPending, isFalse);
    expect(port.acknowledged, 1);
    controller.dispose();
  });

  test('a compatibility change re-reads; a new session starts over', () async {
    final port = FakeMigration()..next = reading(state: 'none');
    final projection = ValueNotifier(account());
    final controller = AccountMigrationController(
      port,
      projection,
      pollFor: Duration.zero,
    );
    await pumpEventQueue();
    final reads = port.reads;
    port.next = reading();
    projection.value = account(relay: AccountCompatibilityRelayState.migrated);
    await pumpEventQueue();
    expect(port.reads, reads + 1);
    expect(controller.value.state, AccountMigrationState.completed);
    controller.dispose();
  });

  for (final state in AccountMigrationState.values.where(
    (s) => s != AccountMigrationState.unavailable,
  )) {
    testWidgets('card actions for ${state.name}', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        support.app(
          AccountMigrationCard(
            view: AccountMigrationView(state),
            onMigrate: (_) => tapped = 'migrate',
            onRetry: (_) => tapped = 'retry',
            onShowResult: (_) => tapped = 'result',
          ),
        ),
      );
      // Localizations load on the next frames; the progress bar never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final expected = switch (state) {
        AccountMigrationState.notLinked => 'account-migrate-start',
        AccountMigrationState.failed => 'account-migrate-retry',
        AccountMigrationState.completed => 'account-migrate-show-result',
        _ => null,
      };
      for (final key in [
        'account-migrate-start',
        'account-migrate-retry',
        'account-migrate-show-result',
      ]) {
        expect(
          find.byKey(Key(key)),
          key == expected ? findsOneWidget : findsNothing,
        );
      }
      expect(
        find.byKey(const Key('account-migrate-old-versions')),
        state == AccountMigrationState.completed
            ? findsOneWidget
            : findsNothing,
      );
      if (expected != null) {
        await tester.tap(find.byKey(Key(expected)));
        await tester.pump();
        expect(tapped, isNotNull);
      }
    });
  }

  testWidgets('a retired account without status shows no result button', (
    tester,
  ) async {
    await tester.pumpWidget(
      support.app(
        AccountMigrationCard(
          view: const AccountMigrationView(
            AccountMigrationState.completed,
            resultAvailable: false,
          ),
          onShowResult: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-migrate-show-result')), findsNothing);
    expect(find.text('旧账号已迁入这个 SCM 账号。'), findsOneWidget);
  });
}

/// Reads finish only when released, to order a read against acknowledge.
final class _SlowMigration extends FakeMigration {
  final _gates = <Completer<void>>[];
  void release() {
    if (_gates.isNotEmpty) _gates.removeAt(0).complete();
  }

  @override
  Future<AccountMigrationReading> read({bool refresh = false}) async {
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return super.read(refresh: refresh);
  }
}
