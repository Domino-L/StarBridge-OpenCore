import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/bridge_app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/social_windows/window_presentation.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_segmented_control.dart';
import 'package:starbridge_flutter/features/settings/general_settings_interaction.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app;
import '../../app/social_windows/social_window_test.dart' show native;

void main() {
  for (final style in InteractionStyle.values) {
    test(
      '$style persists through owner detach and fresh owner reopen',
      () async {
        final store = MemoryStore();
        final owner = AppPreferencesModule();
        await owner.attachStore(store);
        expect(await owner.setInteractionStyle(style), isTrue);
        expect(owner.projection.value.confirmed!.interactionStyle, style);
        expect(
          owner.projection.value.confirmed!.motionPreference,
          MotionPreference.followSystem,
        );
        owner.detachStore();
        owner.dispose();
        final reopened = AppPreferencesModule();
        await reopened.attachStore(store);
        expect(reopened.projection.value.effective.interactionStyle, style);
        expect(reopened.projection.value.revision, 1);
        reopened.dispose();
      },
    );

    test(
      '$style pending save rejects another write and rolls back on failure',
      () async {
        final store = MemoryStore()..pending = Completer();
        final owner = AppPreferencesModule();
        await owner.attachStore(store);
        final saving = owner.setInteractionStyle(style);
        expect(
          owner.projection.value.operation,
          AppPreferencesOperation.saving,
        );
        expect(
          owner.projection.value.confirmed!.interactionStyle,
          InteractionStyle.standard,
        );
        expect(owner.projection.value.effective.interactionStyle, style);
        expect(await owner.setInteractionStyle(InteractionStyle.glow), isFalse);
        store.pending!.completeError(
          const AppPreferencesStoreException(AppPreferencesFailure.saveFailed),
        );
        expect(await saving, isFalse);
        expect(
          owner.projection.value.effective.interactionStyle,
          InteractionStyle.standard,
        );
        expect(
          owner.projection.value.failure,
          AppPreferencesFailure.saveFailed,
        );
        expect(store.writes, 1);
        owner.dispose();
      },
    );

    testWidgets(
      '$style actual root scope follows saved settings above navigator',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = InMemoryAppPreferences();
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          preferences: preferences,
        );
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          StarBridgeApp(composition: composition, navigatorKey: navigator),
        );
        await tester.pumpAndSettle();
        final routeRead = Completer<InteractionData>();
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Builder(
                  builder: (context) {
                    if (!routeRead.isCompleted) {
                      routeRead.complete(InteractionScope.of(context));
                    }
                    return const Text('Route');
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect((await routeRead.future).suite, InteractionSuite.standard);
        unawaited(
          showStarBridgeDialog<void>(
            tester.element(find.text('Route')),
            builder: (context) => const Text('Live dialog'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await preferences.setInteractionStyle(style);
        await tester.pump();
        await tester.pump();
        final context = tester.element(find.text('Route'));
        expect(
          InteractionScope.of(context).suite,
          interactionSuiteFromName(style.name),
        );
        expect(
          InteractionScope.of(tester.element(find.text('Live dialog'))).suite,
          interactionSuiteFromName(style.name),
        );
        await preferences.setMotionPreference(MotionPreference.reduce);
        await tester.pump();
        await tester.pump();
        expect(InteractionScope.of(context).reduceMotion, isTrue);
        final dialogContext = tester.element(find.text('Live dialog'));
        expect(InteractionScope.of(dialogContext).reduceMotion, isTrue);
        expect(ModalRoute.of(dialogContext)!.animation!.value, 1);
        expect(
          InteractionScope.of(context).suite,
          interactionSuiteFromName(style.name),
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(
          InteractionScope.of(tester.element(find.byType(StarBridgeShell)))
              .reduceMotion,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$style actual tray surface follows live style within two frames',
      (tester) async {
        const channel = MethodChannel('starbridge/tray-surface');
        final messenger = tester.binding.defaultBinaryMessenger;
        Map<String, Object?> snapshot(
          InteractionStyle selected,
          bool reduced,
        ) => {
          ...TraySurfaceSnapshot(
            scope: 7,
            state: const TrayQuickPanelState(),
            interactionStyle: selected.name,
            reduceMotion: reduced,
          ).toMap(),
          'opening': 1,
          'keyboard': true,
        };
        messenger.setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'ready' ? snapshot(style, false) : null,
        );
        await tester.pumpWidget(const TraySurfaceApp());
        await tester.pumpAndSettle();
        var context = tester.element(find.byType(TrayQuickPanel));
        expect(
          InteractionScope.of(context).suite,
          interactionSuiteFromName(style.name),
        );
        await native(
          channel.name,
          'snapshot',
          snapshot(InteractionStyle.scan, true),
        );
        await tester.pump();
        await tester.pump();
        context = tester.element(find.byType(TrayQuickPanel));
        expect(InteractionScope.of(context).suite, InteractionSuite.scan);
        expect(InteractionScope.of(context).reduceMotion, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(channel, null);
      },
    );

    test(
      '$style encoded auxiliary presentation has no account or storage authority',
      () {
        final data = encodeWindowPresentation(
          AppPreferences.defaults.copyWith(interactionStyle: style),
        );
        expect(data.keys.toSet(), {
          'appearanceMode',
          'designStyleId',
          'locale',
          'reduceMotion',
          'interactionStyle',
        });
        expect(
          WindowPresentation.decode(data).theme
              .extension<StarBridgeInteractionTheme>()!
              .suite,
          interactionSuiteFromName(style.name),
        );
        final tray = TraySurfaceSnapshot(
          scope: 1,
          state: const TrayQuickPanelState(),
          interactionStyle: style.name,
        );
        expect(
          TraySurfaceSnapshot.parse(tray.toMap()).interactionStyle,
          style.name,
        );
      },
    );
  }

  test(
    'late completion after store replacement cannot change new scope',
    () async {
      final old = MemoryStore()..pending = Completer();
      final owner = AppPreferencesModule();
      await owner.attachStore(old);
      final saving = owner.setInteractionStyle(InteractionStyle.scan);
      final replacement = MemoryStore()
        ..values = AppPreferencesStoreValue.style(InteractionStyle.rail);
      await owner.attachStore(replacement);
      old.pending!.complete(
        AppPreferencesReadResult(
          values: AppPreferencesStoreValue.style(InteractionStyle.scan),
          revision: 1,
          source: AppPreferencesSource.stored,
        ),
      );
      expect(await saving, isFalse);
      expect(
        owner.projection.value.effective.interactionStyle,
        InteractionStyle.rail,
      );
      owner.dispose();
    },
  );

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
  ]) {
    testWidgets(
      'style choices remain reachable at 200 percent narrow width $locale',
      (tester) async {
        var selected = InteractionStyle.standard;
        await tester.pumpWidget(
          app(
            SizedBox(
              width: 280,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                // Match GeneralSettingsPage's vertical scroll surface: English
                // explanatory copy at 200% is taller than this narrow viewport.
                child: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, update) => GeneralSettingsInteraction(
                      value: selected,
                      enabled: true,
                      onChanged: (style) async {
                        update(() => selected = style);
                        return true;
                      },
                    ),
                  ),
                ),
              ),
            ),
            suite: InteractionSuite.rail,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final adapter = tester
            .widget<StarBridgeSegmentedControl<InteractionStyle>>(
              find.byType(StarBridgeSegmentedControl<InteractionStyle>),
            );
        for (final option in adapter.segments) {
          final label = find.text(option.label);
          await tester.ensureVisible(label);
          await tester.pumpAndSettle();
          await tester.tap(label);
          await tester.pumpAndSettle();
          expect(selected, option.value);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final responseStyle in [
    null,
    'standard',
    'rail',
    'scan',
    'glow',
    'unknown',
    1,
  ]) {
    test('bridge read compatibility style=$responseStyle', () async {
      final pair = InMemoryBridgeConnection.createPair();
      unawaited(
        pair.host.incoming.forEach((request) async {
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': 4,
                'storageState': 'ready',
                'preferences': {
                  'localeOverride': 'en-US',
                  'appearanceMode': 'dark',
                  'motionPreference': 'followSystem',
                  'interactionStyle': ?responseStyle,
                },
              },
            ),
          );
        }),
      );
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      try {
        final future = BridgeAppPreferencesStore(session).read();
        if (responseStyle == 'unknown' || responseStyle == 1) {
          await expectLater(
            future,
            throwsA(
              isA<AppPreferencesStoreException>().having(
                (e) => e.failure,
                'failure',
                AppPreferencesFailure.invalidResponse,
              ),
            ),
          );
        } else {
          expect(
            (await future).values.interactionStyle.name,
            responseStyle ?? 'standard',
          );
        }
      } finally {
        await session.close();
        await pair.host.close();
      }
    });
  }

  test(
    'bridge style patch uses revision and no identity, preserves host result',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final requestSeen = Completer<BridgeEnvelope>();
      unawaited(
        pair.host.incoming.forEach((request) async {
          requestSeen.complete(request);
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': 5,
                'storageState': 'ready',
                'preferences': {
                  'localeOverride': 'en-US',
                  'appearanceMode': 'dark',
                  'motionPreference': 'reduce',
                  'interactionStyle': 'scan',
                },
              },
            ),
          );
        }),
      );
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      try {
        final result = await BridgeAppPreferencesStore(session).update(
          const AppPreferencesPatch.interaction(InteractionStyle.scan),
          expectedRevision: 4,
        );
        final request = await requestSeen.future;
        expect(request.accountContext, isNull);
        expect(request.payload['patch'], {'interactionStyle': 'scan'});
        expect(request.payload['expectedRevision'], 4);
        expect(result.values.motionPreference, MotionPreference.reduce);
        expect(result.values.interactionStyle, InteractionStyle.scan);
      } finally {
        await session.close();
        await pair.host.close();
      }
    },
  );
}

class AppPreferencesStoreValue {
  static StoredAppPreferences style(InteractionStyle style) =>
      StoredAppPreferences(
        localeOverride: const Locale('en'),
        appearanceMode: AppPreferences.defaults.appearanceMode,
        motionPreference: MotionPreference.followSystem,
        interactionStyle: style,
      );
}

class MemoryStore implements AppPreferencesStore {
  StoredAppPreferences values = AppPreferencesStoreValue.style(
    InteractionStyle.standard,
  );
  int revision = 0, writes = 0;
  Completer<AppPreferencesReadResult>? pending;
  @override
  Future<AppPreferencesReadResult> read() async => AppPreferencesReadResult(
    values: values,
    revision: revision,
    source: AppPreferencesSource.stored,
  );
  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) async {
    expect(expectedRevision, revision);
    writes++;
    if (pending != null) return pending!.future;
    values = values.apply(patch);
    revision++;
    return read();
  }

  @override
  void dispose() {}
}
