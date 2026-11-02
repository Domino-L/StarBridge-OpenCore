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
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_offline_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/offline_personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeWire;
import 'tray_quick_panel_test.dart' show app;

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  for (final modeCase in [
    'synthetic',
    'delayed',
    'bootstrap',
    'duplicate',
    'offline',
    'failure',
  ]) {
    final useBridgeMode = modeCase != 'synthetic';
    for (final faultCase in ['fresh', 'transient', 'hard']) {
      testWidgets(
        'production composed profile preserves cache until its complete owner read: $faultCase${useBridgeMode ? " $modeCase-bridge-mode" : ""}',
        (tester) async {
          final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
          BridgeEnvelope frame(String key) => BridgeEnvelope.fromJson(
            (wire[key] as Map).cast<String, Object?>(),
          );
          final prepared = frame('prepared');
          final completed = frame('completed');
          final rootId = prepared.payload['rootCorrelationId']! as String;
          late InMemoryBridgePair pair;
          late BridgeClientSession session;
          late AccountModule account;
          late PersonalProfileModule online;
          late StartupSession startup;
          late ConnectionModePort modes;
          late ConnectionModeController mode;
          late List<BridgeEnvelope> requests;
          late StreamSubscription<BridgeEnvelope> subscription;
          late Future<AccountActionResult> pending;
          late Future<dynamic> onlinePending;
          var finished = false;
          var faultDelivered = false;
          final heldLocal = <BridgeEnvelope>[];
          final heldModes = <BridgeEnvelope>[];
          var metadataReleased = false,
              freshReleased = false,
              signedOut = false;
          final heldMetadata = <BridgeEnvelope>[],
              heldFresh = <BridgeEnvelope>[];
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

          final timeline = <String>[];
          void trace(String label) {
            if (!useBridgeMode) return;
            final read =
                (online as ProfileReadObservationOwner).readObservation;
            final a = account.projection.value;
            timeline.add(
              '$label a${a.generation}/${a.sessionState.name}/proof${a.hasDisplayHandoff} mode${mode.snapshot.scope}/${mode.snapshot.state.name}/continuity${mode.displayContinuity?.generation}/traffic${mode.allowsOnlineTraffic} read${read?.generation}/${read?.phase.name}',
            );
            if (timeline.length > 64) timeline.removeAt(0);
          }

          void readiness() {
            startup.resolveAccount(account.projection.value);
            trace('account');
          }

          await tester.runAsync(() async {
            var counter = useBridgeMode ? -1 : 0;
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
              if (useBridgeMode) BridgeConnectionModeAdapter.capability,
            ]);
            account = createAccountModule(BridgeAccountAdapter(session));
            online = createPersonalProfileModule(
              BridgeLocalPersonalProfile(
                session,
                remote: BridgePersonalProfileAdapter(session),
                hangar: () => BridgeLocalHangar(session),
              ),
            );
            startup = StartupSession()
              ..markPresented()
              ..readingAccount();

            account.projection.addListener(readiness);
            online.projection.addListener(() => trace('profile'));
            modes = useBridgeMode
                ? BridgeConnectionModeAdapter(session)
                : ModePort();
            mode = ConnectionModeController(modes);
            mode.addListener(() => trace('mode'));
            requests = <BridgeEnvelope>[];
            final root = Completer<BridgeEnvelope>();
            subscription = pair.host.incoming.listen((request) {
              requests.add(request);
              if (request.name == 'onboarding.mode.read') {
                if (request.sessionGeneration == 0) {
                  unawaited(
                    pair.host.send(
                      BridgeEnvelope(
                        protocolVersion: 1,
                        messageType: 'response',
                        name: request.name,
                        correlationId: request.correlationId,
                        sessionGeneration: request.sessionGeneration,
                        status: 'ok',
                        payload: modeWire('online'),
                      ),
                    ),
                  );
                } else {
                  heldModes.add(request);
                }
                return;
              }
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
                        accountContext: signedOut
                            ? null
                            : completed.accountContext,
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
              if (request.name == 'personalProfile.localRead') {
                if (faultCase != 'fresh' && !faultDelivered) {
                  heldLocal.add(request);
                  return;
                }
                // Explicit current local-file absence; no fabricated inventory.
                unawaited(
                  reply(request, const {
                    'schemaVersion': 1,
                    'revision': 0,
                    'content': null,
                    'savedAt': null,
                    'timeZones': [],
                  }),
                );
              }
              if (request.name.startsWith('hangarReader.')) {
                unawaited(
                  pair.host.send(
                    BridgeEnvelope(
                      protocolVersion: 1,
                      messageType: 'response',
                      name: request.name,
                      correlationId: request.correlationId,
                      sessionGeneration: request.sessionGeneration,
                      accountContext: completed.accountContext,
                      status: 'error',
                      payload: const {},
                      error: const BridgeErrorBody(
                        code: 'hangar.read_unavailable',
                        message: 'Explicit fixture absence',
                        retryable: false,
                      ),
                    ),
                  ),
                );
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

            await mode.refresh();
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
            expect(
              find.textContaining('Stored cold introduction'),
              findsOneWidget,
            );
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
                    useBridgeMode &&
                        r.name == 'onboarding.mode.read' &&
                        r.accountContext == null ||
                    r.name == 'account.offlineData.read' &&
                        r.accountContext == null,
              ),
              isTrue,
              reason: requests
                  .map((r) => '${r.messageType}:${r.name}')
                  .join(', '),
            );

            final originalPage = tester.element(
              find.byType(PersonalProfilePage),
            );
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -100),
            );
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
            expect(
              find.textContaining('Stored cold introduction'),
              findsOneWidget,
            );
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
            if (useBridgeMode) {
              expect(mode.allowsOnlineTraffic, isFalse);
              expect(mode.displayContinuity?.generation, 1);
              expect(heldModes, hasLength(1));
              expect(
                requests.where((r) => r.name == 'personalProfile.localRead'),
                isEmpty,
                reason:
                    'No private child read is admitted while mode is pending.',
              );
              expect(
                find.textContaining('Stored cold introduction'),
                findsOneWidget,
                reason: 'A verified materialized handoff remains readonly while mode rechecks.',
              );
              if (modeCase == 'bootstrap' || modeCase == 'duplicate') {
                await tester.runAsync(() async {
                  await pair.host.send(
                    BridgeEnvelope(
                      protocolVersion: 1,
                      messageType: 'event',
                      name: modeCase == 'bootstrap'
                          ? 'bootstrap.invalidated'
                          : 'account.changed',
                      sessionGeneration: 1,
                      sequence: prepared.sequence! + 2,
                      payload: const {'schemaVersion': 1},
                    ),
                  );
                });
                for (var attempt = 0; attempt < 5; attempt++) {
                  await tester.pump();
                  await tester.runAsync(
                    () => Future<void>.delayed(const Duration(milliseconds: 1)),
                  );
                }
                expect(
                  find.textContaining('Stored cold introduction'),
                  findsNothing,
                );
                expect(find.byKey(const Key('profile-edit')), findsNothing);
                expect(mode.displayContinuity, isNull);
                expect(
                  requests.where((r) => r.name == 'personalProfile.localRead'),
                  isEmpty,
                );
                return;
              }
              await tester.runAsync(() async {
                final request = heldModes.single;
                // Explicit mode scheduling fixture, not Native producer output.
                await pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: 1,
                    messageType: 'response',
                    name: request.name,
                    correlationId: request.correlationId,
                    sessionGeneration: request.sessionGeneration,
                    status: modeCase == 'failure' ? 'error' : 'ok',
                    payload: modeCase == 'failure'
                        ? const {}
                        : modeWire(
                            modeCase == 'offline' ? 'offline' : 'online',
                          ),
                    error: modeCase == 'failure'
                        ? const BridgeErrorBody(
                            code: 'onboarding.unavailable',
                            message: 'Synthetic mode fault',
                            retryable: true,
                          )
                        : null,
                  ),
                );
              });
              for (
                var attempt = 0;
                attempt < 10 && !mode.allowsOnlineTraffic;
                attempt++
              ) {
                await tester.pump();
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 1)),
                );
              }
              if (modeCase == 'offline' || modeCase == 'failure') {
                expect(mode.allowsOnlineTraffic, isFalse);
                expect(mode.failed, modeCase == 'failure');
                expect(
                  find.textContaining('Stored cold introduction'),
                  findsNothing,
                );
                expect(find.byKey(const Key('profile-edit')), findsNothing);
                expect(mode.displayContinuity, isNull);
                expect(
                  requests.where((r) => r.name == 'personalProfile.localRead'),
                  isEmpty,
                );
                return;
              }
              expect(mode.allowsOnlineTraffic, isTrue);
              for (
                var attempt = 0;
                attempt < 20 &&
                    (heldFresh.isEmpty ||
                        faultCase != 'fresh' && heldLocal.isEmpty);
                attempt++
              ) {
                await tester.pump();
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 1)),
                );
              }
              expect(
                heldFresh,
                isNotEmpty,
                reason: 'Fresh domain request actually reached the bridge.',
              );
              if (faultCase != 'fresh') expect(heldLocal, hasLength(1));
              expect(
                find.textContaining('Stored cold introduction'),
                findsOneWidget,
                reason: timeline.join('\n'),
              );
            }
            expect(
              find.textContaining('Stored cold introduction'),
              findsOneWidget,
            );
            expect(find.byKey(const Key('profile-edit')), findsNothing);
            await tester.runAsync(() async {
              freshReleased = true;
              faultDelivered = true;
              for (final request in heldLocal) {
                // Explicit synthetic domain fault. Native prepared/completed frames
                // stay byte-for-byte intact; this is not server/device fault evidence.
                await pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: 1,
                    messageType: 'response',
                    name: request.name,
                    correlationId: request.correlationId,
                    sessionGeneration: request.sessionGeneration,
                    accountContext: completed.accountContext,
                    status: 'error',
                    payload: const {},
                    error: BridgeErrorBody(
                      code: faultCase == 'transient'
                          ? 'personal_profile.read_transient'
                          : 'personal_profile.read_forbidden',
                      retryable: faultCase == 'transient',
                      message: 'Synthetic held local read fault',
                    ),
                  ),
                );
              }
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
            var departurePosition = position;
            if (faultCase != 'fresh') {
              expect(
                find.textContaining('Stored cold introduction'),
                faultCase == 'transient' ? findsOneWidget : findsNothing,
              );
              final displayed = tester.widget<PersonalProfilePage>(
                find.byType(PersonalProfilePage),
              );
              expect(displayed.module.projection.value.canEdit, isFalse);
              expect(
                displayed.module.projection.value.operation,
                PersonalProfileOperation.none,
              );
              expect(
                requests.where((r) => r.name == 'personalProfile.localRead'),
                hasLength(1),
              );
              final retry = find.byKey(
                Key(
                  faultCase == 'transient'
                      ? 'profile-sync-retry'
                      : 'profile-retry',
                ),
              );
              await tester.ensureVisible(retry);
              await tester.tap(retry);
              await tester.pump();
              departurePosition = tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .pixels;
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
                requests.where((r) => r.name == 'personalProfile.localRead'),
                hasLength(2),
              );
            }
            expect(
              online.projection.value.availability,
              PersonalProfileAvailability.available,
              reason:
                  '${online.projection.value.failureKey}; ${requests.map((r) => '${r.name}@${r.sessionGeneration}').join(', ')}',
            );
            expect(online.projection.value.about, 'Fresh after auth');
            expect(
              find.textContaining('Stored cold introduction'),
              findsNothing,
            );
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
              departurePosition,
              reason: timeline.join('\n'),
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
            expect(
              find.textContaining('Stored cold introduction'),
              findsNothing,
            );
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
              if (modes is ModePort) await (modes as ModePort).events.close();
            });
            startup.dispose();
          }
        },
        skip: _path.isEmpty,
      );
    }
  }
}
