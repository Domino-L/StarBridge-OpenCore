import 'package:flutter/material.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';

void main() {
  testWidgets('general shortcuts delegate to runtime and shell owners', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    var exits = 0;
    String? destination;
    await tester.pumpWidget(
      _app(
        Actions(
          actions: {
            ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
              onInvoke: (_) {
                exits++;
                return null;
              },
            ),
            OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
              onInvoke: (intent) {
                destination = intent.route;
                return null;
              },
            ),
          },
          child: GeneralSettingsPage(preferences: preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final exit = find.byKey(const Key('general-exit-application'));
    await tester.ensureVisible(exit);
    await tester.pumpAndSettle();
    await tester.tap(exit);
    expect(exits, 1);
    final overlay = find.byKey(const Key('general-overlay-settings'));
    await tester.ensureVisible(overlay);
    await tester.pumpAndSettle();
    await tester.tap(overlay);
    expect(destination, '/overlay');
  });
  testWidgets(
    'grouped data entries remain discoverable and About reuses its page',
    (tester) async {
      final preferences = InMemoryAppPreferences();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        _app(GeneralSettingsPage(preferences: preferences)),
      );
      await tester.pumpAndSettle();
      for (final id in [
        'local-data-management',
        'local-data-storage',
        'entitlement-redemption',
        'application-updates',
      ]) {
        expect(find.byKey(Key('settings-capability-$id')), findsOneWidget);
      }
      expect(find.text('地点代码采集'), findsNothing);
      final about = find.byKey(const Key('general-about-application'));
      await tester.ensureVisible(about);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('client-version-open')), findsOneWidget);
      await tester.tap(about);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-about-app-icon')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('general-about-back')));
      await tester.pumpAndSettle();
      expect(about, findsOneWidget);
    },
  );

  testWidgets('real device choices are interactive and use accepted previews', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      _app(GeneralSettingsPage(preferences: preferences)),
    );
    await tester.pumpAndSettle();

    expect(find.text('把客户端调到顺手'), findsOneWidget);
    expect(find.byKey(const Key('general-appearance-dark')), findsOneWidget);
    expect(find.byKey(const Key('general-appearance-light')), findsOneWidget);

    await tester.tap(find.byKey(const Key('general-appearance-light')));
    await tester.pump();
    expect(
      preferences.projection.value.effective.appearanceMode,
      AppearanceMode.light,
    );

    await tester.tap(find.byKey(const Key('general-reduce-motion')));
    await tester.pump();
    expect(
      preferences.projection.value.effective.motionPreference,
      MotionPreference.reduce,
    );

    final launch = find.byKey(const Key('general-launch-at-startup'));
    await tester.ensureVisible(launch);
    await tester.pumpAndSettle();
    expect(launch, findsOneWidget);
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(
      preferences
          .projection
          .value
          .effective
          .applicationBehavior
          .launchAtStartup,
      isTrue,
    );

    final closeBehavior = find.byKey(const Key('general-close-behavior'));
    await tester.tap(
      find.descendant(of: closeBehavior, matching: find.text('进入系统托盘')),
    );
    await tester.pumpAndSettle();
    expect(
      preferences
          .projection
          .value
          .effective
          .applicationBehavior
          .keepRunningInBackground,
      isTrue,
    );

    final startupBehavior = find.byKey(const Key('general-startup-behavior'));
    await tester.tap(
      find.descendant(of: startupBehavior, matching: find.text('进入系统托盘')),
    );
    await tester.pumpAndSettle();
    expect(
      preferences.projection.value.effective.applicationBehavior.startMinimized,
      isTrue,
    );

    await tester.ensureVisible(launch);
    await tester.pumpAndSettle();
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(
      preferences.projection.value.effective.applicationBehavior.startMinimized,
      isTrue,
    );
    expect(
      tester.widget<SegmentedButton<bool>>(startupBehavior).onSelectionChanged,
      isNull,
    );
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(
      preferences.projection.value.effective.applicationBehavior.startMinimized,
      isTrue,
    );

    final redemption = find.byKey(
      const Key('settings-capability-entitlement-redemption'),
    );
    await tester.ensureVisible(redemption);
    await tester.pumpAndSettle();
    expect(redemption, findsOneWidget);
    expect(find.text('兑换码与权益'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'production settings navigation keeps real and reserved sections',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = InMemoryAppPreferences();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        _app(
          SettingsPage(
            initialSection: SettingsSection.generalData,
            accountAndIdentityBuilder: (_) => const Text('account'),
            generalDataBuilder: (_) =>
                GeneralSettingsPage(preferences: preferences),
            syncPrivacyBuilder: (_) => const Text('privacy'),
            notificationsBuilder: (_) => const Text('notifications'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-section-accountIdentity')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-section-generalData')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-section-aboutLegal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-section-syncPrivacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-section-notifications')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-section-diagnostics')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings-section-syncPrivacy')));
      await tester.pumpAndSettle();

      expect(find.text('privacy'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    },
  );

  testWidgets('corrupt preference recovery is visible without blocking edits', (
    tester,
  ) async {
    final preferences = AppPreferencesModule(
      systemLocales: const [Locale('zh', 'CN')],
    );
    addTearDown(preferences.dispose);
    await preferences.attachStore(const _RecoveredStore());
    await tester.pumpWidget(
      _app(GeneralSettingsPage(preferences: preferences)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('设置文件已损坏'), findsOneWidget);
    final light = tester.widget<InkWell>(
      find.byKey(const Key('general-appearance-light')),
    );
    expect(light.onTap, isNotNull);
  });

  testWidgets('a retained preference read failure offers an explicit retry', (
    tester,
  ) async {
    final preferences = AppPreferencesModule(
      systemLocales: const [Locale('zh', 'CN')],
    );
    addTearDown(preferences.dispose);
    await preferences.attachStore(const _RecoveredStore());
    final recoveringStore = _RecoveringReadStore();
    await preferences.attachStore(recoveringStore);
    await tester.pumpWidget(
      _app(GeneralSettingsPage(preferences: preferences)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('general-settings-retry')), findsOneWidget);
    final lightBeforeRetry = tester.widget<InkWell>(
      find.byKey(const Key('general-appearance-light')),
    );
    expect(lightBeforeRetry.onTap, isNull);

    await tester.tap(find.byKey(const Key('general-settings-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('general-settings-retry')), findsNothing);
    final lightAfterRetry = tester.widget<InkWell>(
      find.byKey(const Key('general-appearance-light')),
    );
    expect(lightAfterRetry.onTap, isNotNull);
  });
}

Widget _app(Widget home) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: home),
  );
}

final class _RecoveredStore implements AppPreferencesStore {
  const _RecoveredStore();

  @override
  Future<AppPreferencesReadResult> read() async {
    return const AppPreferencesReadResult(
      values: StoredAppPreferences(
        localeOverride: Locale('zh', 'CN'),
        appearanceMode: AppearanceMode.dark,
        motionPreference: MotionPreference.followSystem,
      ),
      revision: 0,
      source: AppPreferencesSource.recoveredDefaults,
    );
  }

  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) async {
    return AppPreferencesReadResult(
      values: (await read()).values.apply(patch),
      revision: expectedRevision + 1,
      source: AppPreferencesSource.stored,
    );
  }

  @override
  void dispose() {}
}

final class _RecoveringReadStore implements AppPreferencesStore {
  var _attempt = 0;

  @override
  Future<AppPreferencesReadResult> read() async {
    _attempt++;
    if (_attempt == 1) {
      throw const AppPreferencesStoreException(
        AppPreferencesFailure.readFailed,
        retryable: true,
      );
    }
    return const AppPreferencesReadResult(
      values: StoredAppPreferences(
        localeOverride: Locale('zh', 'CN'),
        appearanceMode: AppearanceMode.dark,
        motionPreference: MotionPreference.followSystem,
      ),
      revision: 3,
      source: AppPreferencesSource.stored,
    );
  }

  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) async {
    throw StateError('Update should not run during the retry test.');
  }

  @override
  void dispose() {}
}
