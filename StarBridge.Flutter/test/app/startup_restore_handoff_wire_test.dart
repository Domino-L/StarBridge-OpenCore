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
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../features/onboarding/connection_mode_test.dart' show ModePort;
import 'tray_quick_panel_test.dart' show app;

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  testWidgets(
    'actual successful root preserves materialized readonly profile through generation',
    (tester) async {
      final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
      BridgeEnvelope frame(String key) =>
          BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
      final prepared = frame('prepared');
      final completed = frame('completed');
      final rootId = prepared.payload['rootCorrelationId']! as String;
      late InMemoryBridgePair pair;
      late BridgeClientSession session;
      late AccountModule account;
      late PersonalProfileModule online;
      late StartupSession startup;
      late ModePort modes;
      late ConnectionModeController mode;
      late List<BridgeEnvelope> requests;
      late StreamSubscription<BridgeEnvelope> subscription;
      late Future<AccountActionResult> pending;
      late Future<dynamic> onlinePending;
      var finished = false;
      var metadataReleased = false, freshReleased = false, signedOut = false;
      final heldMetadata = <BridgeEnvelope>[], heldFresh = <BridgeEnvelope>[];
      const emptyMetadata = <String, Object?>{
        'schemaVersion': 1,
        'source': 'unavailable',
        'preferencesPolicy': {
          'locales': [],
          'timeZones': [],
          'availableActions': [],
        },
      };
      Future<void> reply(
        BridgeEnvelope request,
        Map<String, Object?> payload,
      ) => pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: completed.accountContext,
          status: 'ok',
          payload: payload,
        ),
      );
      Future<void> replyFresh(BridgeEnvelope request) {
        // Explicit fresh-domain fixture derived from the Native readonly schema;
        // these edited fields are not claimed as server/device evidence.
        final payload = jsonDecode(
          jsonEncode(
            (frame('cachedProfile').payload['remote'] as Map)['payload'],
          ),
        ) as Map<String, dynamic>;
        payload['editable'] = true;
        final profile = payload['profile'] as Map;
        profile['revision'] = 1;
        (profile['identity'] as Map)['callSign'] = 'Fresh synthetic pilot';
        (profile['identity'] as Map)['gameHandle'] = 'FreshSyntheticPilot';
        (profile['content'] as Map)['introduction'] = 'Fresh after auth';
        return reply(request, payload);
      }

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
          'profile.stagedRead',
        ]);
        account = createAccountModule(BridgeAccountAdapter(session));
        online = createPersonalProfileModule(
          BridgePersonalProfileAdapter(session),
        );
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
          if (request.name == 'account.getCurrent') {
            if (!root.isCompleted) {
              root.complete(request);
            } else {
              final payload = {...completed.payload}
                ..remove('restoreDisplayReadId');
              unawaited(
                pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: 1,
                    messageType: 'response',
                    name: request.name,
                    correlationId: request.correlationId,
                    sessionGeneration: request.sessionGeneration,
                    accountContext: signedOut ? null : completed.accountContext,
                    status: 'ok',
                    payload: signedOut
                        ? const {'schemaVersion': 1, 'state': 'signedOut'}
                        : payload,
                  ),
                ),
              );
            }
          }
          if (request.name == 'profile.readDisplayCache') {
            if (metadataReleased) {
              unawaited(reply(request, emptyMetadata));
            } else {
              heldMetadata.add(request);
            }
          }
          if (request.name == 'personalProfile.getSelf') {
            if (freshReleased) {
              unawaited(replyFresh(request));
            } else {
              heldFresh.add(request);
            }
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
        onlinePending = online.initialize();
        await root.future;
      });
      final page = OfflinePersonalProfilePage(
        onlineModule: online,
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
        online: PersonalProfilePage(module: online),
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

        final originalPage = tester.element(find.byType(PersonalProfilePage));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels;
        expect(position, greaterThan(0));
        await tester.runAsync(() async {
          await pair.host.send(completed);
          // Explicit queue fixture; actual successful response and preparing
          // display above are Native output, this schema follows the dispatcher.
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'account.changed',
              sessionGeneration: 1,
              sequence: prepared.sequence! + 1,
              payload: const {'schemaVersion': 1},
            ),
          );
          await Future<void>.delayed(Duration.zero);
        });
        for (var attempt = 0; attempt < 5; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(find.textContaining('Stored cold introduction'), findsOneWidget);
        expect(
          tester.element(find.byType(PersonalProfilePage)),
          same(originalPage),
        );
        expect(find.byKey(const Key('profile-edit')), findsNothing);
        expect(account.projection.value.retainedReadId, isNull);
        expect(account.projection.value.generation, 1);
        expect(startup.complete, isFalse);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          position,
        );
        await tester.runAsync(() async {
          metadataReleased = true;
          for (final request in heldMetadata.toList()) {
            await reply(request, emptyMetadata);
          }
        });
        for (
          var attempt = 0;
          attempt < 10 && !account.projection.value.isSignedIn;
          attempt++
        ) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(account.projection.value.isSignedIn, isTrue);
        expect(find.textContaining('Stored cold introduction'), findsOneWidget);
        expect(find.byKey(const Key('profile-edit')), findsNothing);
        await tester.runAsync(() async {
          freshReleased = true;
          for (final request in heldFresh.toList()) {
            await replyFresh(request);
          }
        });
        for (
          var attempt = 0;
          attempt < 20 &&
              find.textContaining('Fresh after auth').evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(
          online.projection.value.availability,
          PersonalProfileAvailability.available,
          reason:
              '${online.projection.value.failureKey}; ${requests.map((r) => '${r.name}@${r.sessionGeneration}').join(', ')}',
        );
        expect(online.projection.value.about, 'Fresh after auth');
        expect(find.textContaining('Stored cold introduction'), findsNothing);
        expect(find.textContaining('Fresh after auth'), findsOneWidget);
        expect(
          tester.element(find.byType(PersonalProfilePage)),
          same(originalPage),
        );
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          position,
        );
        expect(find.byKey(const Key('profile-edit')), findsOneWidget);
        expect(
          requests.where((r) => r.name == 'account.offlineData.read'),
          hasLength(2),
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          signedOut = true;
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'account.changed',
              sessionGeneration: 2,
              sequence: prepared.sequence! + 2,
              payload: const {'schemaVersion': 1},
            ),
          );
          await Future<void>.delayed(Duration.zero);
        });
        for (var attempt = 0; attempt < 5; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(find.textContaining('Fresh after auth'), findsNothing);
        expect(find.textContaining('Stored cold introduction'), findsNothing);
        expect(find.byKey(const Key('profile-edit')), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        account.projection.removeListener(readiness);
        account.dispose();
        online.dispose();
        await tester.runAsync(() async {
          await session.close();
          await pending;
          await onlinePending;
          await subscription.cancel();
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
