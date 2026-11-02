import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/runtime/example_scene_control.dart';
import 'package:starbridge_flutter/app/runtime/online_restore_flow.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_runtime_notices.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../app/tray_quick_panel_test.dart' show app;
import '../features/onboarding/connection_mode_test.dart' show modeWire;
import '../features/onboarding/online_review_test_support.dart';
import '../features/onboarding/retained_online_review_test.dart'
    show retainedWire;

Widget _localized(Widget child) {
  final frame = app(child) as MaterialApp;
  return MaterialApp(
    locale: frame.locale,
    supportedLocales: frame.supportedLocales,
    localizationsDelegates: [
      const AppStringsDelegate(),
      ...frame.localizationsDelegates!,
    ],
    theme: frame.theme,
    home: frame.home,
  );
}

final class _Lease implements NativeHostLease {
  _Lease(this.fixture);
  final OnlineBridgeFixture fixture;
  @override
  BridgeClientSession get session => fixture.session;
  @override
  Future<NativeHostTermination> get terminated =>
      Completer<NativeHostTermination>().future;
  @override
  Future<void> close() => fixture.close();
}

void main() {
  testWidgets(
    'actual recovery banner uses original review owner, not profile retry',
    (tester) async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
        BridgeOnlineInstallationAdapter.capability,
        BridgeConnectionModeAdapter.capability,
      ]);
      f.onRequest = (request) async {
        if (request.name == 'onboarding.mode.read') {
          await f.respond(
            request,
            value: modeWire('signInRequired', revision: 7),
          );
        } else if (request.name.startsWith('onboarding.onlineReview.v2.')) {
          // The original owner has not yet proved exit. Recovery must stop here.
          await f.respond(
            request,
            value: retainedWire(
              mode: request.name.endsWith('.cancel')
                  ? 'recoveryRequired'
                  : 'signInRequired',
              state: 'recoveryRequired',
            ),
          );
        } else {
          await f.pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'error',
              payload: const {},
              error: BridgeErrorBody(
                code: request.name.startsWith('account.')
                    ? 'account.local_mode'
                    : 'fixture.unavailable',
                message: 'Synthetic paused owner',
                retryable: false,
              ),
            ),
          );
        }
      };
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: _Lease(f),
        preferences: preferences,
        windowChrome: InMemoryWindowChrome(),
      );
      final presence = composition.manualPresence!;
      final ready = presence.connectionMode.refresh();
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await ready;
      final initializing = composition.account.initialize();
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await initializing;
      BuildContext? context;
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (value) {
              context = value;
              return Column(
                children: shellRuntimeNotices(
                  composition: composition,
                  projection: composition.shellChrome.projection.value,
                  exampleSceneControl: const ExampleSceneControl.hidden(),
                  onOpenPrivacy: () {},
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('继续恢复在线'), findsNothing);
      final flow = OnlineRestoreFlow(
        connection: presence,
        account: composition.account,
        context: () => context,
        current: () => true,
      );
      // Binding the original owner must enable the banner without another read.
      await tester.pump();
      expect(find.text('继续恢复在线'), findsOneWidget);
      expect(f.requests.where((r) => r.name.endsWith('.cancel')), isEmpty);
      final accountReads = f.requests
          .where((r) => r.name.startsWith('account.'))
          .length;
      await tester.tap(find.byKey(const Key('connection-status-retry')));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(
        f.requests.where((r) => r.name == 'onboarding.onlineReview.v2.cancel'),
        hasLength(1),
      );
      expect(
        f.requests.where((r) => r.name.startsWith('account.')),
        hasLength(accountReads),
      );
      expect(
        f.requests.any(
          (r) =>
              r.name.endsWith('.begin') ||
              r.name.endsWith('.resume') ||
              r.name.endsWith('.install'),
        ),
        false,
      );
      expect(composition.account.projection.value.isSignedIn, false);
      expect(presence.connectionMode.allowsOnlineTraffic, false);
      flow.dispose();
      await tester.pumpWidget(const SizedBox());
      composition.dispose();
      preferences.dispose();
      await tester.runAsync(f.close);
    },
  );
}
