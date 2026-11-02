import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/hangar_display_session.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'hangar_reader_test.dart' as fixtures;

const _path = String.fromEnvironment('STARBRIDGE_HANGAR_READ_FAILURE_WIRE');
const _id = '0123456789abcdef0123456789abcdef';

// This cache selection and authentication projection are explicit scheduling
// fixtures. Inventory and fault responses below are actual saved Host output;
// this is not a new Native account-restore or real-account acceptance claim.
AccountProjection _account(
  int generation,
  DateTime at, {
  bool retained = false,
  bool signedIn = false,
  AccountDisplayHandoff? proof,
}) => AccountProjection(
  generation: generation,
  sessionState: signedIn
      ? AccountSessionState.signedIn
      : AccountSessionState.loading,
  operation: signedIn ? AccountOperation.none : AccountOperation.refreshing,
  profileFreshness: AccountProfileFreshness.cached,
  cachedAt: at,
  preparingDisplay: true,
  retainedReadId: retained ? _id : null,
  displayHandoff: proof,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

class _MaterializedCache implements LocalHangarPort {
  _MaterializedCache(this.snapshot);
  final LocalHangarSnapshot snapshot;
  int reads = 0;
  @override
  Future<LocalHangarSnapshot> read() async {
    ++reads;
    return snapshot;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => Future.error(const LocalHangarFailure('account.local_mode'));
}

void main() {
  for (final fault in [
    'busy',
    'malformed',
    'ownerMismatch',
    'integrity',
    'permission',
    'fileKind',
    'directoryKind',
    'retiredDuringRead',
    'storageOwnerRetired',
  ]) {
    testWidgets(
      'actual Host $fault preserves cached hangar only for classified read contention',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1120, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        BridgeEnvelope native(String key) =>
            BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
        final success = native('success'),
            failure = native(fault),
            owner = success.accountContext!;
        final at = DateTime.parse(success.payload['savedAt']! as String);
        final snapshot = LocalHangarSnapshot(
          revision: success.payload['revision']! as int,
          savedAt: at,
          inventorySavedAt: DateTime.parse(
            success.payload['inventorySavedAt']! as String,
          ),
          ships: (success.payload['ships']! as List)
              .cast<Map>()
              .map(
                (ship) => LocalHangarShip(
                  id: ship['id']! as String,
                  title: ship['title']! as String,
                ),
              )
              .toList(),
        );
        final cached = _MaterializedCache(snapshot);
        final generation = success.sessionGeneration;
        final proof = AccountDisplayHandoff(
          displayKey: _id,
          sourceGeneration: generation - 1,
          route: AccountRoute(
            environment: owner.environment,
            authority: owner.authority,
            subject: owner.subject,
          ),
        );
        final account = ValueNotifier(
          _account(generation - 1, at, retained: true),
        );
        late InMemoryBridgePair pair;
        late BridgeClientSession bridge;
        late StreamSubscription<BridgeEnvelope> subscription;
        late HangarDisplaySession display;
        final requests = <BridgeEnvelope>[];
        var replyKind = fault;
        await tester.runAsync(() async {
          pair = InMemoryBridgeConnection.createPair();
          bridge = BridgeClientSession(
            connection: pair.client,
            sessionGeneration: generation,
          );
          bridge.acceptHostCapabilities(['hangar.localFavorites']);
          subscription = pair.host.incoming.listen((request) {
            requests.add(request);
            if (request.name == 'account.getCurrent') {
              // Synthetic hot-root fixture; it does not impersonate a real login.
              unawaited(
                pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: 1,
                    messageType: 'response',
                    name: request.name,
                    correlationId: request.correlationId,
                    sessionGeneration: generation,
                    accountContext: owner,
                    status: 'ok',
                    payload: const {'schemaVersion': 1, 'state': 'signedIn'},
                  ),
                ),
              );
            } else if (request.name == 'hangarReader.inventory') {
              final response = native(replyKind);
              // Only the request correlation is rebound; Native payload, owner,
              // generation, status and error/retryable remain exactly unchanged.
              unawaited(
                pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: response.protocolVersion,
                    messageType: response.messageType,
                    name: response.name,
                    correlationId: request.correlationId,
                    sessionGeneration: response.sessionGeneration,
                    accountContext: response.accountContext,
                    status: response.status,
                    payload: response.payload,
                    error: response.error,
                  ),
                ),
              );
            }
          });
          final source = CachedLocalHangar(
            BridgeLocalHangar(
              bridge,
              displayHandoff: () => account.value.hasDisplayHandoff
                  ? account.value.displayHandoff
                  : null,
            ),
            isCurrent: () =>
                account.value.isSignedIn &&
                account.value.generation == generation,
          );
          display = HangarDisplaySession(
            account: account,
            retainedFactory: (_) => cached,
            localFactory: () => source,
          );
        });
        Future<void> drain() async {
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            await tester.pump();
          }
        }

        try {
          await tester.pumpWidget(
            fixtures.app(LocalHangarPage(port: display, onRead: null)),
          );
          await drain();
          expect(find.text(snapshot.ships.single.title), findsOneWidget);
          await tester.runAsync(() async {
            account.value = _account(generation - 1, at, proof: proof);
            account.value = _account(
              generation,
              at,
              signedIn: true,
              proof: proof,
            );
          });
          await drain();
          expect(display.failed, isTrue);
          expect(display.confirmed, isFalse);
          expect(display.favoritesAvailable, isFalse);
          expect(
            requests.where((r) => r.name == 'hangarReader.inventory'),
            hasLength(1),
            reason:
                'No automatic replay or polling after a classified failure.',
          );
          expect(cached.reads, 1);
          final recoverable = fault == 'busy';
          expect(failure.error?.retryable, recoverable);
          expect(display.snapshot != null, recoverable);
          final probe = tester.widget<LoadingContentProbe>(
            find.byType(LoadingContentProbe),
          );
          expect(
            probe.status,
            recoverable
                ? LoadingContentStatus.partial
                : LoadingContentStatus.failed,
          );
          expect(
            find.text(snapshot.ships.single.title),
            recoverable ? findsOneWidget : findsNothing,
          );
          if (recoverable) {
            replyKind = 'recovered';
            await tester.tap(find.byKey(const Key('local-hangar-retry')));
            await drain();
            expect(display.failed, isFalse);
            expect(display.confirmed, isTrue);
            expect(display.favoritesAvailable, isTrue);
            expect(display.snapshot!.savedAt, snapshot.savedAt);
            expect(
              requests.where((r) => r.name == 'account.getCurrent'),
              hasLength(2),
            );
            expect(
              requests.where((r) => r.name == 'hangarReader.inventory'),
              hasLength(2),
            );
          }
          expect(
            requests.every(
              (r) =>
                  r.name == 'account.getCurrent' ||
                  r.name == 'hangarReader.inventory',
            ),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            display.dispose();
            account.dispose();
            await bridge.close();
            await subscription.cancel();
            await pair.host.close();
          });
        }
      },
      skip: _path.isEmpty,
    );
  }
}
