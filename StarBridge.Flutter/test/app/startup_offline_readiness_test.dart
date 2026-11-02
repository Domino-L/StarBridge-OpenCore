import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/startup/startup_readiness_binding.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import 'presence/direct_online_restore_flow_test.dart' show RetainedAccount;

final pausedAccount = const AccountProjection.loading().copyWith(
  operation: AccountOperation.none,
  sessionState: AccountSessionState.credentialTemporarilyUnavailable,
  failure: const AccountFailure(
    code: 'account.local_mode',
    messageKey: 'account.error.unavailable',
    retryable: false,
  ),
);

void main() {
  for (final state in [
    'offline',
    'local',
    'unavailable',
    'recoveryRequired',
    'signInRequired',
  ]) {
    test(
      'startup borrows confirmed $state without granting account authority',
      () async {
        final port = ModePort()..current = modeFact(state);
        final mode = ConnectionModeController(port);
        final startup = StartupSession()..markPresented();
        addTearDown(() async {
          startup.dispose();
          mode.dispose();
          await port.events.close();
        });
        await mode.refresh();
        startup.resolveAccount(pausedAccount, connectionMode: mode);
        expect(startup.value, switch (state) {
          'offline' || 'local' => StartupPhase.ready,
          'recoveryRequired' ||
          'signInRequired' => StartupPhase.accountUnavailable,
          _ => StartupPhase.account,
        });
        expect(startup.accountStatus, switch (state) {
          'offline' => StartupAccountStatus.offline,
          'local' => StartupAccountStatus.local,
          'recoveryRequired' ||
          'signInRequired' => StartupAccountStatus.onlineRecoveryRequired,
          _ => StartupAccountStatus.loading,
        });
        expect(pausedAccount.isSignedIn, false);
        expect(mode.allowsOnlineTraffic, false);
      },
    );
  }

  for (final code in [
    'account.local_mode',
    'bridge.invalid_envelope',
    'bridge.timeout',
  ]) {
    test('offline suppresses only the expected account pause: $code', () async {
      final port = ModePort()..current = modeFact('offline');
      final mode = ConnectionModeController(port);
      final startup = StartupSession()..markPresented();
      await mode.refresh();
      startup.resolveAccount(
        pausedAccount.copyWith(
          failure: AccountFailure(
            code: code,
            messageKey: 'account.error.unavailable',
            retryable: false,
          ),
        ),
        connectionMode: mode,
      );
      expect(
        startup.value,
        code == 'account.local_mode'
            ? StartupPhase.ready
            : StartupPhase.accountUnavailable,
      );
      startup.resolvePreparation(
        preferencesConfirmed: false,
        account: pausedAccount,
        connectionMode: mode,
      );
      expect(startup.value, StartupPhase.preferencesUnavailable);
      startup.dispose();
      mode.dispose();
      await port.events.close();
    });
  }

  test(
    'late offline observation reevaluates startup without an account event',
    () async {
      final port = ModePort()..current = modeFact('offline');
      final mode = ConnectionModeController(port);
      final account = RetainedAccount(() => 7, coldStart: true);
      final startup = StartupSession()..markPresented();
      var changes = 0, current = true;
      final binding = StartupReadinessBinding(
        account: account,
        mode: mode,
        current: () => current,
        onChanged: () {
          changes++;
          startup.resolveAccount(
            account.projection.value,
            connectionMode: mode,
          );
        },
      );
      startup.resolveAccount(account.projection.value, connectionMode: mode);
      expect(startup.value, StartupPhase.account);
      await binding.retry();
      expect(startup.value, StartupPhase.ready);
      expect(account.refreshes, 0);
      expect(changes, 1);
      port.current = modeFact('online');
      await binding.retry();
      expect(account.refreshes, 1);
      final before = changes;
      current = false;
      await mode.refresh();
      await binding.retry();
      expect(changes, before);
      expect(account.refreshes, 1);
      binding.dispose();
      current = true;
      await mode.refresh();
      expect(changes, before);
      account.dispose();
      mode.dispose();
      startup.dispose();
      await port.events.close();
    },
  );

  test(
    'unsupported legacy mode owner retains original account startup',
    () async {
      final port = ModePort()..supported = false;
      final mode = ConnectionModeController(port);
      final startup = StartupSession()..markPresented();
      await mode.refresh();
      startup.resolveAccount(
        AccountProjection.fromSnapshot(
          const AccountHostSnapshot.signedOut(generation: 0),
        ),
        connectionMode: mode,
      );
      expect(startup.value, StartupPhase.ready);
      expect(startup.accountStatus, StartupAccountStatus.signedOut);
      expect(mode.snapshot.state, ConnectionModeState.unsupported);
      startup.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
}
