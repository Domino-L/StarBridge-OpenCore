import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  for (final state in [
    AccountReviewState.cached,
    AccountReviewState.signedIn,
  ]) {
    test(
      'healthy initial $state is not evidence of a connection failure',
      () async {
        final module = createAccountModule(
          InMemoryAccountAdapter.forReview(state),
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
        expect(module.projection.value.isSignedIn, isTrue);
        expect(module.projection.value.failure, isNull);
        expect(chrome.projection.value.connectionIssue, isNull);
      },
    );
  }
}
