import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  test(
    'draft survives refresh and clears only after confirmed save or discard',
    () async {
      final port = InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      );
      final module = createAccountModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final draft = module.preferencesDraft;
      draft.setLocale('en-US');
      expect(draft.hasChanges, isTrue);
      await module.refresh();
      expect(draft.locale, 'en-US');
      expect(draft.hasChanges, isTrue);
      expect(port.commands, isEmpty);
      await module.savePreferences(
        locale: draft.locale,
        timeZone: draft.timeZone,
      );
      expect(draft.hasChanges, isFalse);
      draft.setLocale('zh-CN');
      draft.discard();
      expect(draft.locale, 'en-US');
      expect(draft.hasChanges, isFalse);
    },
  );

  test('logout clears draft and prevents editing another account', () async {
    final port = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
    final module = createAccountModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    final draft = module.preferencesDraft;
    draft.setLocale('en-US');
    await module.logout();
    expect(module.projection.value.sessionState, AccountSessionState.signedOut);
    expect(draft.locale, isEmpty);
    expect(draft.hasChanges, isFalse);
    draft.setLocale('en-US');
    expect(draft.locale, isEmpty);
  });
}
