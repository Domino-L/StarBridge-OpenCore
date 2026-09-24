import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/presence_color.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  for (final mode in AppearanceMode.values) {
    final tokens = FutureRestraintStyle.resolve(mode);
    final colors = tokens.colors;
    test('presence semantic palette follows $mode theme', () {
      expect(presenceColor(colors, 'presence.online'), colors.info);
      expect(presenceColor(colors, 'presence.inGame'), colors.success);
      expect(presenceColor(colors, 'presence.away'), colors.warning);
      expect(presenceColor(colors, 'presence.offline'), colors.offline);
      expect(presenceColor(colors, 'presence.notInGame'), colors.offline);
      expect(presenceColor(colors, 'presence.unknown'), colors.warning);
      expect(presenceColor(colors, 'presence.gameUnknown'), colors.warning);
    });

    testWidgets('account status and avatar use presence colors in $mode', (
      tester,
    ) async {
      var projection = InMemoryShellChrome.connectedProjection.copyWith(
        accountSignedIn: true,
        accountLabel: 'Test',
        presenceKey: 'presence.online',
      );
      Future<void> show({bool expanded = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
            locale: const Locale('zh', 'CN'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: AccountMenu(
                  destinations: const [],
                  projection: projection,
                  expanded: expanded,
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
      }

      Color? textColor(String key) =>
          tester.widget<Text>(find.byKey(Key(key))).style?.color;
      Color avatarColor() =>
          (tester
                      .widget<Container>(
                        find.byKey(const Key('account-avatar-status')),
                      )
                      .decoration!
                  as BoxDecoration)
              .border!
              .top
              .color;

      await show();
      expect(textColor('account-presence'), colors.info);
      expect(avatarColor(), colors.info);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('account-command')),
      );
      expect(button.style!.side!.resolve({}), BorderSide.none);
      expect(
        button.style!.side!.resolve({WidgetState.hovered}),
        BorderSide.none,
      );
      expect(
        button.style!.side!.resolve({WidgetState.focused})!.color,
        colors.focusRing,
      );
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      expect(textColor('account-app-presence'), colors.info);
      expect(textColor('account-game-presence'), colors.warning);
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();

      projection = projection.copyWith(presenceKey: 'presence.away');
      await show();
      expect(find.text('暂离'), findsOneWidget);
      expect(textColor('account-presence'), colors.warning);
      expect(avatarColor(), colors.warning);
      projection = projection.copyWith(
        presenceKey: 'presence.online',
        gamePresence: GamePresenceState.running,
        gameVersion: 'EPTU',
      );
      await show();
      expect(find.text('游戏中 · EPTU'), findsOneWidget);
      expect(textColor('account-presence'), colors.success);
      expect(avatarColor(), colors.success);
      await show(expanded: false);
      expect(avatarColor(), colors.success);

      projection = projection.copyWith(
        accountIssue: const ConnectionIssueProjection(
          domain: ConnectionStatusDomain.network,
          titleKey: 'presence.unknown',
          detailKey: 'presence.unknown',
          state: ConnectionVisualState.disconnected,
        ),
      );
      await show();
      expect(textColor('account-status-issue'), colors.danger);
      expect(avatarColor(), colors.danger);

      projection = projection.copyWith(
        clearAccountIssue: true,
        accountSignedIn: false,
        presenceKey: 'presence.offline',
      );
      await show();
      expect(textColor('account-presence'), colors.offline);
      expect(avatarColor(), colors.offline);
      projection = projection.copyWith(
        accountSignedIn: true,
        accountAvatarImageData: 'data:image/png;base64,invalid-test-image',
      );
      await show();
      final photoDecoration =
          tester
                  .widget<Container>(
                    find.byKey(const Key('account-avatar-status')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(photoDecoration.border, isNull);
      expect(photoDecoration.color, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
