import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import 'presence/direct_online_restore_flow_test.dart' show RetainedAccount;

void main() {
  test(
    'retained offline name is visible without granting a signed-in session',
    () async {
      final port = ModePort()
        ..current = ConnectionModeSnapshot(
          scope: 7,
          revision: 22,
          state: ConnectionModeState.offline,
          offlineAccount: OfflineAccountDisplay(
            'Synthetic Pilot',
            DateTime.utc(2026, 10, 14),
          ),
        );
      final mode = ConnectionModeController(port);
      final account = RetainedAccount(() => 7, coldStart: true);
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: account,
      )..observeConnectionMode(mode);
      addTearDown(() async {
        chrome.dispose();
        account.dispose();
        mode.dispose();
        await port.events.close();
      });
      await mode.refresh();
      expect(chrome.projection.value.accountLabel, 'Synthetic Pilot');
      expect(chrome.projection.value.presenceKey, 'presence.offline');
      expect(chrome.projection.value.accountSignedIn, isFalse);
      port.current = modeFact('local');
      await mode.refresh();
      expect(chrome.projection.value.accountLabel, isEmpty);
    },
  );
  for (final code in ['account.local_mode', 'bridge.timeout']) {
    for (final hostFailed in [false, true]) {
      test(
        'offline chrome preserves real errors ($code / host: $hostFailed)',
        () async {
          final port = ModePort()..current = modeFact('offline');
          final mode = ConnectionModeController(port);
          final account = RetainedAccount(() => 7, coldStart: true);
          account.projection.value = account.projection.value.copyWith(
            failure: AccountFailure(
              code: code,
              messageKey: 'account.error.unavailable',
              retryable: false,
            ),
          );
          final base = InMemoryShellChrome(
            initial: hostFailed
                ? InMemoryShellChrome.disconnectedProjection
                : InMemoryShellChrome.connectedProjection,
          );
          final chrome = AccountShellChrome(base: base, account: account);
          chrome.observeConnectionMode(mode);
          expect(chrome.projection.value.accountIssue, isNotNull);
          await mode.refresh();
          expect(
            chrome.projection.value.accountIssue,
            code == 'account.local_mode' ? isNull : isNotNull,
          );
          expect(chrome.projection.value.accountSignedIn, false);
          expect(
            chrome.projection.value.connectionIssue,
            hostFailed || code != 'account.local_mode' ? isNotNull : isNull,
          );
          if (hostFailed) {
            expect(
              chrome.projection.value.connectionIssue?.titleKey,
              'connection.host.disconnected.title',
            );
          }
          port.current = modeFact('online');
          await mode.refresh();
          expect(chrome.projection.value.accountIssue, isNotNull);
          chrome.dispose();
          account.dispose();
          mode.dispose();
          await port.events.close();
        },
      );
    }
  }
}
