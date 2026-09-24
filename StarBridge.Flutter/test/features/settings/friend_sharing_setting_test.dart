import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';

import 'friend_sharing_controller_test.dart' show Harness;

void main() {
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets('six real sharing controls at narrow width $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness();
        final tokens = StyleRegistry()
            .resolve(AppPreferences.defaults.designStyleId, mode)
            .tokens;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.runtimeSupportedLocales(),
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildStarBridgeTheme(tokens, locale),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FriendSharingSetting(session: h.session),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SwitchListTile), findsNWidgets(6));
        expect(tester.takeException(), isNull);
        final control = find.byKey(const Key('friend-sharing-ship'));
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(h.writes.length, 1);
        expect(h.writes.single.payload['fields'], 8);
        expect(tester.widget<SwitchListTile>(control).value, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.close);
      });
    }
  }
}
