import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/startup/startup_content_gate.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_offline_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/offline_personal_profile_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../features/onboarding/connection_mode_test.dart' show ModePort;
import 'tray_quick_panel_test.dart' show app;

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  testWidgets(
    'held Native root reveals actual cached profile, not Ready or an editor',
    (tester) async {
      final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
      BridgeEnvelope frame(String key) =>
          BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
      final prepared = frame('prepared');
      final rootId = prepared.payload['rootCorrelationId']! as String;
      late InMemoryBridgePair pair;
      late BridgeClientSession session;
      late AccountModule account;
      late StartupSession startup;
      late ModePort modes;
      late ConnectionModeController mode;
      late List<BridgeEnvelope> requests;
      late StreamSubscription<BridgeEnvelope> subscription;
      late Future<AccountActionResult> pending;
      late BridgeEnvelope request;
      var finished = false;
      void readiness() => startup.resolveAccount(account.projection.value);
      await tester.runAsync(() async {
        var counter = 0;
        pair = InMemoryBridgeConnection.createPair();
        session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
          correlationIdFactory: () =>
              counter++ == 0 ? rootId : 'ui-cache-$counter',
        );
        session.acceptHostCapabilities([
          'account.restoreDisplay',
          'account.offlineData.read',
        ]);
        account = createAccountModule(BridgeAccountAdapter(session));
        startup = StartupSession()
          ..markPresented()
          ..readingAccount();

        account.projection.addListener(readiness);
        modes = ModePort();
        mode = ConnectionModeController(modes);
        await mode.refresh();
        requests = <BridgeEnvelope>[];
        final root = Completer<BridgeEnvelope>();
        subscription = pair.host.incoming.listen((request) {
          requests.add(request);
          if (request.name == 'account.getCurrent' && !root.isCompleted) {
            root.complete(request);
          }
          if (request.name == 'account.offlineData.read') {
            // The Native artifact contains a profile, not an inventory. Confirm
            // inventory absence explicitly; do not fabricate cached ships.
            final payload = request.payload['kind'] == 'profile'
                ? frame('cachedProfile').payload
                : <String, Object?>{
                    'schemaVersion': 1,
                    'revision': 0,
                    'content': null,
                  };
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: request.sessionGeneration,
                  status: 'ok',
                  payload: payload,
                ),
              ),
            );
          }
        });

        pending = account.initialize().whenComplete(() => finished = true);
        request = await root.future;
      });
      final page = OfflinePersonalProfilePage(
        mode: mode,
        account: account.projection,
        createPort: () => throw StateError('No mode switch authorized'),
        createRetainedPort: (id) => BridgeOfflinePersonalProfile.retained(
          session,
          id,
          isCurrent: () =>
              account.projection.value.hasRetainedDisplayRead &&
              account.projection.value.retainedReadId == id,
        ),
        online: const Text('Actual online owner'),
      );
      try {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                delegates: const [AppStringsDelegate()],
                child: StartupContentGate(
                  session: startup,
                  account: account.projection,
                  preferencesConfirmed: true,
                  loading: (_) => const Text('Still preparing'),
                  shell: (_) => page,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Still preparing'), findsOneWidget);
        await tester.runAsync(() async {
          await pair.host.send(prepared);
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        // Drain real bridge IO between fake-clock frames. pumpAndSettle alone
        // can advance a child timeout before its real stream response runs.
        for (
          var attempt = 0;
          attempt < 10 &&
              find
                  .textContaining('Stored cold introduction')
                  .evaluate()
                  .isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('Stored cold introduction'), findsOneWidget);
        expect(find.text('Still preparing'), findsNothing);
        expect(find.byKey(const Key('profile-edit')), findsNothing);
        expect(find.byKey(const Key('profile-save')), findsNothing);
        expect(startup.value, StartupPhase.account);
        expect(finished, isFalse);
        expect(account.projection.value.isSignedIn, isFalse);
        expect(
          requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(1),
        );
        expect(
          requests.every(
            (r) =>
                r.name == 'account.getCurrent' ||
                r.name == 'account.offlineData.read' &&
                    r.accountContext == null,
          ),
          isTrue,
          reason: requests.map((r) => '${r.messageType}:${r.name}').join(', '),
        );

        // An authoritative signed-out outcome must remove cached content.
        // This response is a lifecycle fixture; the cached frames above are Native output.
        await tester.runAsync(() async {
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 0,
              status: 'ok',
              payload: const {'schemaVersion': 1, 'state': 'signedOut'},
            ),
          );
          await pending;
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('Stored cold introduction'), findsNothing);
        expect(find.text('Actual online owner'), findsOneWidget);
        expect(account.projection.value.retainedReadId, isNull);
        expect(startup.value, StartupPhase.complete);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.projection.removeListener(readiness);
        account.dispose();
        await tester.runAsync(() async {
          await pending;
          await subscription.cancel();
          await session.close();
          await pair.host.close();
          mode.dispose();
          await modes.events.close();
        });
        startup.dispose();
      }
    },
    skip: _path.isEmpty,
  );
}
