import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/account/bridge_account_failure.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_request_operation.dart';

// CX-L07c: the Host keeps the account signed in when the local credential
// could not be retired, and reports account.logout_incomplete (retryable).
void main() {
  test('logout_incomplete maps to its own retryable notice', () {
    final failure = mapAccountBridgeFailure(
      const BridgeRemoteException('account.logout_incomplete', retryable: true),
    );

    expect(failure.code, 'account.logout_incomplete');
    expect(failure.messageKey, 'account.error.logoutIncomplete');
    expect(failure.retryable, isTrue);
  });

  test('logout_incomplete notice is translated in every locale', () {
    for (final locale in AppStrings.supportedLocales) {
      final text = AppStrings.resolve(locale).text('account.error.logoutIncomplete');
      expect(text, isNot('account.error.logoutIncomplete'), reason: '$locale');
    }
    expect(
      AppStrings.resolve(const Locale('zh', 'CN')).text('account.error.logoutIncomplete'),
      contains('退出未完成'),
    );
  });
}
