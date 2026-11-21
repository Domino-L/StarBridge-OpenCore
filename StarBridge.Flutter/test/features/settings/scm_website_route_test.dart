import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/help_support_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/help_support_port.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_flutter/features/settings/scm_route_port.dart';

void main() {
  test('every SCM failure translation retains the host placeholder', () {
    for (final strings in [helpSupportZhCn, helpSupportZhTw, helpSupportEnUs]) {
      expect(strings['help.scm.openFailed'], contains('{host}'));
      expect(strings['help.scm.openFailed'], isNot(contains('scm.flowcld.com')));
    }
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('zh', 'TW'), const Locale('en')]) {
    for (final active in [ScmRouteActive.domestic, ScmRouteActive.overseas, null]) {
      testWidgets('SCM website header and failure follow $active in $locale', (tester) async {
        final route = _Route();
        await tester.pumpWidget(_app(
          HelpSupportSettingsPage(port: _FailedOpen(), scmRoute: route), locale,
        ));
        await tester.pumpAndSettle();
        // A read still in flight must not claim the domestic website.
        expect(_scmTooltip(tester), 'SCM · scm.flowcld.com');
        if (active == null) {
          route.result.completeError(StateError('route unavailable'));
        } else {
          route.result.complete(ScmRouteStatus(
            mode: ScmRouteMode.auto, active: active, reason: null,
            restartRequired: false,
          ));
        }
        await tester.pumpAndSettle();
        final host = active == ScmRouteActive.domestic ? 'flowcld.xyz' : 'scm.flowcld.com';
        expect(_scmTooltip(tester), 'SCM · $host');
        await tester.tap(find.byKey(const Key('help-scm-team')));
        await tester.pumpAndSettle();
        final strings = locale.languageCode == 'en' ? helpSupportEnUs
            : locale.countryCode == 'TW' ? helpSupportZhTw : helpSupportZhCn;
        expect(find.text(strings['help.scm.openFailed']!.replaceAll('{host}', host)), findsOneWidget);
        expect(find.textContaining('{host}'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

String _scmTooltip(WidgetTester tester) => tester
    .widgetList<StarBridgeTooltip>(find.byType(StarBridgeTooltip))
    .singleWhere((tooltip) => tooltip.message.startsWith('SCM · '))
    .message;

class _Route implements ScmRoutePort {
  final result = Completer<ScmRouteStatus>();
  @override
  Future<ScmRouteStatus> read() => result.future;
  @override
  Future<ScmRouteStatus> save(ScmRouteMode mode) => throw UnsupportedError('read only');
}

class _FailedOpen implements HelpSupportPort {
  @override
  Future<Map<String, dynamic>> read(String name) async =>
      throw StateError('browser unavailable');
  @override
  Future<void> send(String contact, String message) async =>
      throw UnsupportedError('unused');
}

Widget _app(Widget home, Locale locale) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark).tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(), GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: home),
  );
}