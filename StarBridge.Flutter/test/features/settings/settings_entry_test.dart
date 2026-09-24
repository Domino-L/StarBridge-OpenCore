import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_overview.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';

import '../friends/social_layout_test.dart' show capture, loadFonts, size;
import 'local_notification_test.dart' show Fixture;

Widget app(Widget child, Locale locale, GlobalKey repaint) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => RepaintBoundary(key: repaint, child: child!),
  home: Scaffold(body: child),
);

void main() {
  test('every retained entry has explicit actions and three-language copy', () {
    expect(
      settingsEntryActions.keys.toSet(),
      SettingsCapabilityCatalog.planned.map((e) => e.id).toSet(),
    );
    for (final actions in settingsEntryActions.values) {
      expect(actions, isNotEmpty);
      expect(actions.toSet().length, actions.length);
      for (final locale in AppStrings.supportedLocales) {
        for (final key in [
          ...actions,
          'title',
          'intro',
          'unavailable',
          'notice',
          'close',
          'options',
        ]) {
          expect(
            settingsEntryText(AppStrings.resolve(locale), key),
            isNotEmpty,
          );
        }
      }
    }
    expect(settingsEntryActions['application-updates'], [
      'checkUpdates',
      'releaseNotes',
      'downloadUpdate',
      'installUpdate',
    ]);
    expect(settingsEntryActions['local-data-storage'], [
      'viewDirectory',
      'openDirectory',
      'moveDirectory',
    ]);
  });

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('all entries open without enabling actions at 390px $locale', (
      tester,
    ) async {
      size(tester, const Size(390, 760));
      final repaint = GlobalKey();
      for (final entry in SettingsCapabilityCatalog.planned) {
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: PlannedSettingsCapabilities(section: entry.section),
            ),
            locale,
            repaint,
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(Key('settings-capability-${entry.id}'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byKey(Key('settings-entry-${entry.id}')), findsOneWidget);
        for (final action in settingsEntryActions[entry.id]!) {
          final button = tester.widget<OutlinedButton>(
            find.byKey(Key('settings-action-${entry.id}-$action')),
          );
          expect(button.onPressed, isNull);
        }
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('settings-entry-close')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsCapabilityEntryDialog), findsNothing);
      }
    });
  }

  testWidgets(
    'ordinary notification mode exposes pending entries without saving',
    (tester) async {
      size(tester, const Size(1000, 900));
      final fixture = Fixture();
      await fixture.start();
      addTearDown(fixture.close);
      await fixture.module.refresh();
      await tester.pumpWidget(
        app(
          NotificationSettingsPage(module: fixture.module),
          const Locale('zh', 'CN'),
          GlobalKey(),
        ),
      );
      await tester.pumpAndSettle();
      final before = fixture.requests.length;
      for (final id in ['source-rules', 'player-activity', 'continuous-play']) {
        final target = find.byKey(Key('settings-capability-$id'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byKey(Key('settings-entry-$id')), findsOneWidget);
        await tester.tap(find.byKey(const Key('settings-entry-close')));
        await tester.pumpAndSettle();
      }
      expect(fixture.requests.length, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared redemption entry contains no code submission', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEntitlementRedemptionEntry(context),
            child: const Text('open'),
          ),
        ),
        const Locale('zh', 'CN'),
        GlobalKey(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-entry-entitlement-redemption')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('entry review screenshots', (tester) async {
    await loadFonts();
    final repaint = GlobalKey();
    for (final width in [1100.0, 390.0]) {
      size(tester, Size(width, 800));
      await tester.pumpWidget(
        app(
          const SingleChildScrollView(
            child: PlannedSettingsCapabilities(
              section: SettingsSection.generalData,
            ),
          ),
          const Locale('zh', 'CN'),
          repaint,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, repaint, 'settings-entries-${width.toInt()}');
      final target = find.byKey(
        const Key('settings-capability-application-updates'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      await capture(tester, repaint, 'settings-update-entry-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('settings-entry-close')));
      await tester.pumpAndSettle();
    }
  });
}
