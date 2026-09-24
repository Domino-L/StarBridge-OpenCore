import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';

void main() {
  test(
    'event selection rejects retired bits and preserves choices while disabled',
    () {
      const selected = EventSharingChoice(enabled: true, selectedTypes: 36);
      final off = selected.copyWith(enabled: false);
      expect(off.effectiveTypes, 0);
      expect(off.copyWith(enabled: true).effectiveTypes, 36);
      expect(EventSharingChoice.fromJson(off.toJson()).selectedTypes, 36);
      expect(EventSharingChoice.unconfirmed.effectiveTypes, 0);
      for (final value in [-1, 16, 63, 64]) {
        expect(
          () => EventSharingChoice.fromJson({
            'enabled': true,
            'selectedTypes': value,
          }),
          throwsFormatException,
        );
      }
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'independent compact event choices fit narrow large text $locale',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var choice = EventSharingChoice.unconfirmed;
        await tester.pumpWidget(
          _app(
            locale,
            StatefulBuilder(
              builder: (context, setState) => EventScopeEditor(
                scopeKey: 'event-room',
                title: 'Room',
                description: 'Current room only',
                choice: choice,
                canEdit: true,
                onChanged: (value) => setState(() => choice = value),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Switch), findsNWidgets(5));
        expect(
          tester
              .widgetList<Switch>(find.byType(Switch))
              .every((s) => s.onChanged == null),
          true,
        );
        final master = find.byType(Checkbox);
        await tester.ensureVisible(master);
        await tester.tap(master);
        await tester.pumpAndSettle();
        expect(choice.effectiveTypes, 47);
        final life = find.byKey(
          const Key('privacy-scope-event-room-field-life'),
        );
        await tester.ensureVisible(life);
        await tester.pumpAndSettle();
        await tester.tap(life);
        await tester.pumpAndSettle();
        expect(choice.selectedTypes, 15);
        await tester.ensureVisible(master);
        await tester.pumpAndSettle();
        await tester.tap(master);
        await tester.pumpAndSettle();
        expect(choice.enabled, false);
        expect(choice.selectedTypes, 15);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _app(Locale locale, Widget child) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}
