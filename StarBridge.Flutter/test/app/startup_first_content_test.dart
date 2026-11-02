import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/startup/startup_content_gate.dart';
import 'package:starbridge_flutter/app/startup/startup_first_content.dart';
import 'package:starbridge_flutter/app/startup/startup_readiness_binding.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';

class _Account implements AccountModule {
  _Account(AccountProjection value) : projection = ValueNotifier(value);
  @override
  final ValueNotifier<AccountProjection> projection;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// User report 2026-10-20: the startup screen closed before the call sign,
// joined organizations, presence and sharing status had loaded.

AccountProjection _signedIn({bool refreshing = false}) =>
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.signedIn,
      operation: refreshing
          ? AccountOperation.refreshing
          : AccountOperation.none,
      generation: 4,
    );

void main() {
  test(
    'signed-in startup waits in content until first-glance items settle',
    () {
      final session = StartupSession()..markPresented();
      session.resolveAccount(_signedIn(), firstContentSettled: false);
      expect(session.value, StartupPhase.content);
      // A same-generation background refresh never sends it back to account.
      session.resolveAccount(
        _signedIn(refreshing: true),
        firstContentSettled: false,
      );
      expect(session.value, StartupPhase.content);
      session.resolveAccount(_signedIn(), firstContentSettled: true);
      expect(session.value, StartupPhase.ready);
      session.dispose();
    },
  );

  test('signed-out and unpresented startup never wait for first content', () {
    final signedOut = StartupSession()..markPresented();
    signedOut.resolveAccount(
      const AccountProjection.loading().copyWith(
        sessionState: AccountSessionState.signedOut,
        operation: AccountOperation.none,
      ),
      firstContentSettled: false,
    );
    expect(signedOut.value, StartupPhase.ready);
    signedOut.dispose();
  });

  testWidgets(
    'first content settles on its items, never past the safety limit',
    (tester) async {
      {
        final account = _Account(_signedIn());
        final calls = ValueNotifier(0), organizations = ValueNotifier(0);
        var callSign = false, joined = false, notified = 0;
        final binding = StartupReadinessBinding(
          account: account,
          mode: null,
          current: () => true,
          onChanged: () => notified++,
          firstContent: [
            StartupFirstContentItem('callSign', calls, () => callSign),
            StartupFirstContentItem('joined', organizations, () => joined),
          ],
        );
        expect(binding.firstContentSettled, isFalse);
        callSign = true;
        calls.value++;
        expect(notified, 1);
        expect(binding.firstContentSettled, isFalse);
        joined = true;
        organizations.value++;
        expect(binding.firstContentSettled, isTrue);

        // A stalled read cannot hold startup beyond the limit.
        final stalled = StartupReadinessBinding(
          account: account,
          mode: null,
          current: () => true,
          onChanged: () => notified++,
          firstContent: [
            StartupFirstContentItem('presence', calls, () => false),
          ],
        );
        expect(stalled.firstContentSettled, isFalse);
        await tester.pump(
          StartupFirstContentLimit.safety - const Duration(milliseconds: 1),
        );
        expect(stalled.firstContentSettled, isFalse);
        final before = notified;
        await tester.pump(const Duration(milliseconds: 1));
        expect(notified, before + 1);
        expect(stalled.firstContentSettled, isTrue);
        binding.dispose();
        stalled.dispose();
        calls.dispose();
        organizations.dispose();
      }
    },
  );

  testWidgets(
    'content builds the shell offstage and enters on the same element',
    (tester) async {
      final session = StartupSession()..markPresented();
      final account = ValueNotifier(_signedIn());
      var shellBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StartupContentGate(
            session: session,
            account: account,
            preferencesConfirmed: true,
            loading: (_) => const Text('Preparing'),
            shell: (_) {
              shellBuilds++;
              return const Text('Shell');
            },
          ),
        ),
      );
      expect(find.text('Shell', skipOffstage: false), findsNothing);
      session.resolveAccount(account.value, firstContentSettled: false);
      await tester.pump();
      expect(session.value, StartupPhase.content);
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Shell'), findsNothing);
      expect(find.text('Shell', skipOffstage: false), findsOneWidget);
      final offstage = tester.element(find.text('Shell', skipOffstage: false));
      final loading = tester.element(find.text('Preparing'));
      session.resolveAccount(account.value, firstContentSettled: true);
      await tester.pump();
      expect(session.value, StartupPhase.ready);
      expect(tester.element(find.text('Preparing')), same(loading));
      session.enter();
      await tester.pump();
      expect(find.text('Shell'), findsOneWidget);
      expect(find.text('Preparing'), findsNothing);
      expect(tester.element(find.text('Shell')), same(offstage));
      expect(shellBuilds, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      session.dispose();
    },
  );
}
