import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/startup/startup_content_gate.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';

AccountProjection _display() => AccountProjection(
  sessionState: AccountSessionState.loading,
  operation: AccountOperation.refreshing,
  generation: 0,
  profileFreshness: AccountProfileFreshness.cached,
  profile: const AccountProfile(displayName: 'Synthetic pilot'),
  cachedAt: DateTime.utc(2026, 10, 1),
  preparingDisplay: true,
  retainedReadId: '0123456789abcdef0123456789abcdef',
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

void main() {
  // User, 2026-10-20: "开应用的这个加载就是为了干这个事的，不要用户进去了结果用不了".
  // A cached display only prepares the shell offstage; it is shown on real
  // completion, or when the account cannot be confirmed.
  testWidgets(
    'a cached display prepares the shell offstage but never shows it early',
    (tester) async {
      final session = StartupSession()
        ..markPresented()
        ..readingAccount();
      final account = ValueNotifier(const AccountProjection.loading());
      Widget view(bool confirmed) => MaterialApp(
        home: StartupContentGate(
          session: session,
          account: account,
          preferencesConfirmed: confirmed,
          loading: (_) => const Text('Preparing'),
          shell: (_) => const Text('Shell'),
        ),
      );
      await tester.pumpWidget(view(false));
      account.value = _display();
      await tester.pump();
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Shell', skipOffstage: false), findsNothing);
      await tester.pumpWidget(view(true));
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Shell'), findsNothing);
      expect(find.text('Shell', skipOffstage: false), findsOneWidget);
      session.resolveAccount(account.value);
      await tester.pump();
      expect(session.value, StartupPhase.account);
      expect(session.complete, isFalse);
      expect(account.value.canLogin, isFalse);
      expect(account.value.canLogout, isFalse);
      expect(account.value.canEditPreferences, isFalse);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      session.dispose();
    },
  );

  testWidgets(
    'withdrawal keeps the offstage shell element; real completion shows it',
    (tester) async {
      final session = StartupSession()
        ..markPresented()
        ..readingAccount();
      final account = ValueNotifier(_display());
      final shell = ValueListenableBuilder<AccountProjection>(
        valueListenable: account,
        builder: (_, value, _) => ListView(
          children: [
            if (value.isPreparingDisplay) const Text('Cached rows'),
            for (var i = 0; i < 60; i++)
              SizedBox(height: 40, child: Text('Local row $i')),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StartupContentGate(
            session: session,
            account: account,
            preferencesConfirmed: true,
            loading: (_) => const Text('Preparing'),
            shell: (_) => shell,
          ),
        ),
      );
      final list = find.byType(ListView, skipOffstage: false);
      final mounted = tester.element(list);
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      account.value = const AccountProjection.loading();
      await tester.pump();
      expect(find.text('Cached rows', skipOffstage: false), findsNothing);
      expect(tester.element(list), same(mounted));
      expect(session.value, StartupPhase.account);
      account.value = account.value.copyWith(
        operation: AccountOperation.none,
        sessionState: AccountSessionState.signedOut,
      );
      session.resolveAccount(account.value);
      await tester.pump();
      // The real startup page enters after its handoff motion.
      expect(session.value, StartupPhase.ready);
      expect(find.text('Preparing'), findsOneWidget);
      session.enter();
      await tester.pumpAndSettle();
      expect(session.value, StartupPhase.complete);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Preparing'), findsNothing);
      expect(tester.element(find.byType(ListView)), same(mounted));
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      session.dispose();
    },
  );

  testWidgets('an unconfirmable account still shows the retained display', (
    tester,
  ) async {
    final session = StartupSession()
      ..markPresented()
      ..readingAccount();
    final account = ValueNotifier(_display());
    await tester.pumpWidget(
      MaterialApp(
        home: StartupContentGate(
          session: session,
          account: account,
          preferencesConfirmed: true,
          loading: (_) => const Text('Preparing'),
          shell: (_) => const Text('Shell'),
        ),
      ),
    );
    expect(find.text('Shell'), findsNothing);
    session.resolveAccount(
      account.value.copyWith(
        operation: AccountOperation.none,
        sessionState: AccountSessionState.credentialTemporarilyUnavailable,
      ),
    );
    await tester.pump();
    expect(session.value, StartupPhase.accountUnavailable);
    expect(find.text('Shell'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    session.dispose();
  });

  test('preparing read never survives completion, clearing, or generation', () {
    final display = _display();
    expect(display.copyWith().hasRetainedDisplayRead, isTrue);
    for (final retired in [
      display.copyWith(generation: 1),
      display.copyWith(operation: AccountOperation.none),
      display.copyWith(clearProfile: true),
      display.copyWith(clearCachedAt: true),
      display.copyWith(sessionState: AccountSessionState.signedIn),
    ]) {
      expect(retired.retainedReadId, isNull);
      expect(retired.isPreparingDisplay, isFalse);
    }
  });
}
