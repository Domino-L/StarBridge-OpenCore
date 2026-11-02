import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';

import '../../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import '../tray_quick_panel_test.dart' show app;

void main() {
  testWidgets(
    'cold intentional offline is not rendered as signed out and can resume',
    (tester) async {
      final port = ModePort()..current = modeFact('offline');
      final mode = ConnectionModeController(port);
      await tester.runAsync(mode.refresh);
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
      final presence = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      var logins = 0, restores = 0;
      final release = presence.bindOnlineRestore(() async {
        restores++;
        return false;
      });
      final projection = InMemoryShellChrome.connectedProjection.copyWith(
        accountSignedIn: false,
        accountLabel: '',
        accountBusy: false,
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              delegates: const [AppStringsDelegate()],
              child: AccountMenu(
                destinations: const [],
                projection: projection,
                expanded: true,
                manualPresence: presence,
                onSelect: (_) {},
                onLogin: () {
                  logins++;
                },
                onLogout: () {},
                onIssueAction: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未登录'), findsNothing);
      expect(find.byKey(const Key('manual-presence-self')), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-identity-command')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-menu-login')), findsNothing);
      await tester.tap(find.byKey(const Key('account-presence-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manual-presence-online')));
      await tester.pumpAndSettle();
      expect(restores, 1);
      expect(logins, 0);
      expect(
        projection.accountSignedIn,
        false,
        reason: 'mode display must not invent authentication',
      );
      await tester.pumpWidget(const SizedBox());
      release();
      presence.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
}
