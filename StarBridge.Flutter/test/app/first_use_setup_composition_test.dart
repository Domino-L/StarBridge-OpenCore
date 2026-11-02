import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/first_use_setup_composition.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_device_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_local_statistics_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_native_overlay_observation.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';

import '../features/onboarding/local_statistics_test_support.dart';
import '../features/onboarding/bridge_onboarding_adapter_test.dart' show wire;
import '../features/overlay_settings/overlay_appearance_center_entry_test.dart'
    show EntryPort;
import '../features/overlay_settings/overlay_appearance_preview_page_test.dart'
    show Window;

class EditorsFixture {
  final preferences = InMemoryAppPreferences();
  final overlay = OverlaySettingsModule(InMemoryOverlaySettingsAdapter());
  final notices = InMemoryNotificationSettingsAdapter.forReview();
  late final notifications = createNotificationSettingsModule(notices);
  late final editors = FirstUseDeviceEditors(
    preferences: preferences,
    overlay: overlay,
    notifications: notifications,
  );
  Future<void> ready() async {
    await overlay.refresh();
    await notifications.initialize();
  }

  void close() {
    preferences.dispose();
    overlay.dispose();
    notifications.dispose();
  }
}

Future<void> pump(
  WidgetTester tester,
  Widget Function(BuildContext) build,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('en', 'US'),
      ),
      locale: const Locale('en', 'US'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: Builder(builder: build)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'first-use Native preview borrows the saved workspace, opens read-only and restores its window',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      final port = EntryPort(configurations: const []);
      final window = Window();
      final overlay = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: port,
        editorWindow: window,
      );
      addTearDown(overlay.dispose);
      await overlay.initialize();
      final actionsBefore = List.of(port.storage.runtimeActions);
      final editor = FirstUseDeviceEditors(
        preferences: f.preferences,
        overlay: overlay,
        notifications: f.notifications,
      );
      var returned = false;
      await pump(
        tester,
        (context) => TextButton(
          onPressed: () async {
            await editor.openNativePreview(context);
            returned = true;
          },
          child: const Text('preview'),
        ),
      );
      await tester.tap(find.text('preview'));
      await tester.pumpAndSettle();
      final page = tester.widget<OverlayAppearancePreviewPage>(
        find.byType(OverlayAppearancePreviewPage),
      );
      expect(identical(page.module, overlay.workspace), true);
      expect(page.readOnly, true);
      expect(page.appearanceId, port.storage.snapshot.settings!['skin']);
      expect(port.live.opens, hasLength(1));
      expect(port.oldCarrierOpens, 0);
      expect(port.storage.mutations, isEmpty);
      expect(port.storage.runtimeActions, actionsBefore);
      expect(window.enters, 1);
      expect(window.exits, 0);
      await tester.tap(find.byKey(const Key('appearance-preview-exit')));
      await tester.pumpAndSettle();
      expect(port.live.closes, 1);
      expect(window.exits, 1);
      expect(returned, true);
    },
  );

  testWidgets(
    'unloaded, unsaved or unsupported workspace blocks preview without a refresh or window entry',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      final port = EntryPort(configurations: const []);
      final window = Window();
      final overlay = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: port,
        editorWindow: window,
      );
      addTearDown(overlay.dispose);
      final editor = FirstUseDeviceEditors(
        preferences: f.preferences,
        overlay: overlay,
        notifications: f.notifications,
      );
      late BuildContext context;
      await pump(tester, (value) {
        context = value;
        return const SizedBox();
      });
      await expectLater(editor.openNativePreview(context), throwsStateError);
      expect(port.storage.runtimeActions, isEmpty);
      await overlay.initialize();
      final actionsBefore = List.of(port.storage.runtimeActions);
      // Edits save on their own; only one that failed to save blocks.
      port.storage.writeFailure = OverlaySettingsFailure.writeFailed;
      overlay.workspace!.updateSetting('opacity', .7);
      expect(overlay.workspace!.projection.value.dirty, true);
      await expectLater(editor.openNativePreview(context), throwsStateError);
      expect(overlay.workspace!.projection.value.dirty, true);
      expect(port.storage.runtimeActions, actionsBefore);
      expect(
        port.storage.mutations.map((m) => m.kind).toSet(),
        {OverlayWorkspaceMutationKind.saveActive},
      );
      expect(port.live.opens, isEmpty);
      expect(window.enters, 0);
      await expectLater(f.editors.openNativePreview(context), throwsStateError);
    },
  );

  testWidgets(
    'explicit manual continuation mounts real adapters and reads without login or default writes',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      final bridge = StatisticsBridgeFixture();
      addTearDown(bridge.close);
      bridge.session.acceptHostCapabilities([
        BridgeOnboardingAdapter.capability,
        BridgeDeviceReviewAdapter.capability,
        BridgeLocalStatisticsAdapter.capability,
        BridgeOnlineReviewAdapter.capability,
      ]);
      bridge.onRequest = (request) => bridge.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: wire(),
        ),
      );
      final feature = createFirstUseSetupFeatures(
        bridge.session,
        f.editors,
      ).single;
      await pump(tester, feature.buildDestination);
      expect(bridge.requests, isEmpty);
      await tester.tap(find.byKey(const Key('first-use-manual-open')));
      await tester.pumpAndSettle();
      final page = tester.widget<OnboardingPage>(find.byType(OnboardingPage));
      expect(page.controller.value.facts.available, true);
      expect(page.controller.value.facts.handle, 'Pilot-Example');
      expect(page.deviceReview!.port, isA<BridgeDeviceReviewAdapter>());
      expect(page.localStatistics!.port, isA<BridgeLocalStatisticsAdapter>());
      expect(page.editDeviceSettings, isNotNull);
      expect(page.nativeOverlay!.port, isA<BridgeNativeOverlayObservation>());
      expect(page.onlineReview!.port, isA<BridgeOnlineReviewAdapter>());
      expect(page.openNativePreview, isNotNull);
      // A first-use user's opening step is recorded as UI progress only.
      expect(bridge.requests.map((request) => request.name), [
        'onboarding.read',
        'onboarding.saveProgress',
      ]);
      expect(bridge.requests.every((r) => r.accountContext == null), true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'reminder editor borrows the original controller and does not auto-save',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      final port = ReminderPort();
      final controller = ContinuousPlayController(port);
      addTearDown(controller.dispose);
      final editors = FirstUseDeviceEditors(
        preferences: f.preferences,
        overlay: f.overlay,
        notifications: f.notifications,
        playReminder: controller,
      );
      var returned = false;
      await pump(
        tester,
        (context) => TextButton(
          onPressed: () async {
            await editors.open(context, DeviceReviewSection.playReminder);
            returned = true;
          },
          child: const Text('reminder'),
        ),
      );
      await tester.tap(find.text('reminder'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester
              .widget<ContinuousPlayConnectedPanel>(
                find.byType(ContinuousPlayConnectedPanel),
              )
              .controller,
          controller,
        ),
        true,
      );
      expect(port.reads, 1);
      expect(port.writes, 0);
      await tester.tap(find.byKey(const Key('settings-entry-close')));
      await tester.pumpAndSettle();
      expect(returned, true);
      expect(port.writes, 0);
    },
  );
  test('subset capabilities cannot register product continuation or affect existing users', () async {
    final f = EditorsFixture();
    addTearDown(f.close);
    final bridge = StatisticsBridgeFixture(capabilities: false);
    addTearDown(bridge.close);
    expect(createFirstUseSetupFeatures(null, f.editors), isEmpty);
    bridge.session.acceptHostCapabilities([
      BridgeLocalStatisticsAdapter.capability,
      BridgeDeviceReviewAdapter.capability,
    ]);
    expect(createFirstUseSetupFeatures(bridge.session, f.editors), isEmpty);
    bridge.session.acceptHostCapabilities([
      BridgeLocalStatisticsAdapter.capability,
      BridgeDeviceReviewAdapter.capability,
      BridgeNativeOverlayObservation.capability,
      BridgeOnlineReviewAdapter.capability,
    ]);
    expect(createFirstUseSetupFeatures(bridge.session, f.editors), isEmpty);
    bridge.session.acceptHostCapabilities([BridgeOnboardingAdapter.capability]);
    final feature = createFirstUseSetupFeatures(
      bridge.session,
      f.editors,
    ).single;
    expect(feature.route, '/settings/setup');
    expect(feature.navigationParentId, 'settings');
    expect(bridge.requests, isEmpty);
  });
  testWidgets(
    'manual product entry remains explicit and fails closed without current complete capability',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      final bridge = StatisticsBridgeFixture();
      addTearDown(bridge.close);
      bridge.session.acceptHostCapabilities([
        BridgeOnboardingAdapter.capability,
      ]);
      final feature = createFirstUseSetupFeatures(
        bridge.session,
        f.editors,
      ).single;
      await pump(tester, feature.buildDestination);
      await tester.pumpAndSettle();
      expect(bridge.requests, isEmpty);
      bridge.session.acceptHostCapabilities([]);
      await tester.tap(find.byKey(const Key('first-use-manual-open')));
      await tester.pumpAndSettle();
      expect(bridge.requests, isEmpty);
    },
  );
  testWidgets(
    'startup/close editor is the original preference owner, without account statistics',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      await f.ready();
      var returned = false;
      await pump(
        tester,
        (context) => TextButton(
          onPressed: () async {
            await f.editors.open(context, DeviceReviewSection.application);
            returned = true;
          },
          child: const Text('edit'),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
      final page = tester.widget<GeneralSettingsPage>(
        find.byType(GeneralSettingsPage),
      );
      expect(identical(page.preferences, f.preferences), true);
      expect(page.gameplayTime, null);
      await tester.scrollUntilVisible(
        find.byKey(const Key('general-launch-at-startup')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('general-launch-at-startup')));
      await tester.pumpAndSettle();
      expect(
        f
            .preferences
            .projection
            .value
            .effective
            .applicationBehavior
            .launchAtStartup,
        true,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(returned, true);
      expect(
        f
            .preferences
            .projection
            .value
            .effective
            .applicationBehavior
            .launchAtStartup,
        true,
      );
    },
  );
  testWidgets(
    'overlay and notification editors borrow the original modules; unknown leave stays open',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      await f.ready();
      await pump(
        tester,
        (context) => Column(
          children: [
            TextButton(
              onPressed: () =>
                  f.editors.open(context, DeviceReviewSection.overlay),
              child: const Text('hud'),
            ),
            TextButton(
              onPressed: () =>
                  f.editors.open(context, DeviceReviewSection.notifications),
              child: const Text('notices'),
            ),
          ],
        ),
      );
      await tester.tap(find.text('hud'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester
              .widget<OverlaySettingsPage>(find.byType(OverlaySettingsPage))
              .module,
          f.overlay,
        ),
        true,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('notices'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester
              .widget<NotificationSettingsPage>(
                find.byType(NotificationSettingsPage),
              )
              .module,
          f.notifications,
        ),
        true,
      );
      final originalLeave = notificationLeaveGuards[f.notifications];
      var requests = 0;
      notificationLeaveGuards[f.notifications] = () async {
        requests++;
        return false;
      };
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.byType(NotificationSettingsPage), findsOneWidget);
      notificationLeaveGuards[f.notifications] = originalLeave;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationSettingsPage), findsNothing);
    },
  );
  testWidgets(
    'failed notification draft save retains editor until explicit discard',
    (tester) async {
      final f = EditorsFixture();
      addTearDown(f.close);
      await f.ready();
      var returned = false;
      await pump(
        tester,
        (context) => TextButton(
          onPressed: () async {
            await f.editors.open(context, DeviceReviewSection.notifications);
            returned = true;
          },
          child: const Text('edit'),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('notification-channel-windows')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('notification-channel-windows')));
      await tester.pumpAndSettle();
      f.notices.failNextUpdate = true;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notification-leave-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save changes').last);
      await tester.pumpAndSettle();
      expect(returned, false);
      expect(find.byType(NotificationSettingsPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-leave-discard')));
      await tester.pumpAndSettle();
      expect(returned, true);
    },
  );
}

class ReminderPort implements ContinuousPlayPort {
  int reads = 0, writes = 0;
  @override
  Future<ContinuousPlayValue> read() async {
    reads++;
    return const ContinuousPlayValue(
      enabled: false,
      firstMinutes: 90,
      repeatMinutes: 60,
      revision: 1,
    );
  }

  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes++;
    return desired;
  }
}
