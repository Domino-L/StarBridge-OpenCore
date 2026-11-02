import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;

final class PausedAccountPort implements AccountPort {
  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();
  @override
  Future<AccountPortResult> read() async => const AccountPortResult.failed(
    AccountFailure(
      code: 'account.local_mode',
      messageKey: 'account.error.unavailable',
      retryable: false,
    ),
  );
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      throw StateError('No account action belongs in this read-only repro.');
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'cold pending online recovery is not a generic account/network failure',
    () async {
      // Mirrors the verified durable onlinePending-from-offline receipt. The
      // real Host deliberately pauses account dispatch until explicit recovery.
      // A pending mode must not be relabelled as a failed profile request.
      final port = ModePort()..current = modeFact('signInRequired');
      final mode = ConnectionModeController(port);
      final account = createAccountModule(PausedAccountPort());
      final base = InMemoryShellChrome(
        initial: InMemoryShellChrome.connectedProjection,
      );
      final chrome = AccountShellChrome(base: base, account: account);
      chrome.observeConnectionMode(mode);
      addTearDown(() async {
        chrome.dispose();
        account.dispose();
        mode.dispose();
        await port.events.close();
      });
      await mode.refresh();
      await account.initialize();
      expect(mode.allowsOnlineTraffic, false);
      expect(chrome.projection.value.accountSignedIn, false);
      expect(
        chrome.projection.value.accountIssue?.action,
        ConnectionIssueAction.restoreOnline,
      );
      expect(
        chrome.projection.value.accountIssue?.domain,
        ConnectionStatusDomain.identity,
      );
      expect(chrome.projection.value.connectionIssueUsesAccountAction, false);
      expect(
        chrome.projection.value.accountIssue?.detailKey,
        isNot('account.error.unavailable'),
        reason: 'a paused mode is not a failed profile request; never fabricate sign-in',
      );
    },
  );
}
