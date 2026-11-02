import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

import '../tray_quick_panel_test.dart' show app;

void main() {
  for (final state in [
    AccountSessionState.credentialTemporarilyUnavailable,
    AccountSessionState.signedOut,
    AccountSessionState.reauthorizationRequired,
  ]) {
    for (final withCache in [false, true]) {
      testWidgets(
        'account menu distinguishes $state / cache $withCache without granting access',
        (tester) async {
          final module = createAccountModule(
            InMemoryAccountAdapter(
              initial: AccountHostSnapshot(
                generation: 1,
                sessionState: state,
                profileFreshness: withCache
                    ? AccountProfileFreshness.cached
                    : AccountProfileFreshness.unavailable,
                profile: withCache
                    ? const AccountProfile(displayName: 'Retained Pilot')
                    : null,
                cachedAt: withCache ? DateTime.utc(2026) : null,
                identity: const AccountIdentityProjection.unavailable(),
                compatibility:
                    const AccountCompatibilityProjection.unavailable(),
                localeOptions: const [],
                timeZoneOptions: const [],
              ),
            ),
          );
          final base = InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          );
          final chrome = AccountShellChrome(base: base, account: module);
          await tester.runAsync(module.initialize);
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => Localizations.override(
                  context: context,
                  delegates: const [AppStringsDelegate()],
                  child: AccountMenu(
                    destinations: const [],
                    projection: chrome.projection.value,
                    expanded: true,
                    onSelect: (_) {},
                    onLogin: () {},
                    onLogout: () {},
                    onIssueAction: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final unavailable =
              state == AccountSessionState.credentialTemporarilyUnavailable;
          expect(find.text('未登录'), unavailable ? findsNothing : findsOneWidget);
          if (unavailable) {
            expect(
              find.text(withCache ? 'Retained Pilot' : '账号待确认'),
              findsOneWidget,
            );
          }
          expect(chrome.projection.value.accountSignedIn, isFalse);
          expect(
            chrome.projection.value.accountLabel,
            unavailable && withCache ? 'Retained Pilot' : '',
          );
          await tester.pumpWidget(const SizedBox());
          chrome.dispose();
          module.dispose();
        },
      );
    }
  }
}
