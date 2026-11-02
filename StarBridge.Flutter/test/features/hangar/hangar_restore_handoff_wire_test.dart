import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/hangar_feature.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_detail.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_details.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'hangar_reader_test.dart' as fixtures;
import '../onboarding/connection_mode_test.dart' show modeWire;

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  for (final hasModeOwner in [false, true]) {
    testWidgets(
      'actual restore proof preserves cached hangar and view until its qualified fresh inventory; mode: $hasModeOwner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1120, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        BridgeEnvelope native(String key) =>
            BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
        final prepared = native('prepared'), completed = native('completed');
        late InMemoryBridgePair pair;
        late BridgeClientSession session;
        late AccountModule account;
        ConnectionModeController? mode;
        var signedOut = false;
        late Future<AccountActionResult> pending;
        late StreamSubscription<BridgeEnvelope> subscription;
        final requests = <BridgeEnvelope>[],
            metadata = <BridgeEnvelope>[],
            fresh = <BridgeEnvelope>[],
            modeReads = <BridgeEnvelope>[];
        Future<void> reply(
          BridgeEnvelope r,
          Map<String, Object?> payload, {
          bool public = false,
        }) => pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            correlationId: r.correlationId,
            sessionGeneration: r.sessionGeneration,
            accountContext: public ? null : completed.accountContext,
            status: 'ok',
            payload: payload,
          ),
        );
        // Native restore fixture has no hangar rows. These inventory/domain inputs
        // are explicit synthetic fixtures, not claimed as Native/server evidence.
        Map<String, Object?> inventory(bool cached) => {
          'schemaVersion': 1,
          'revision': cached ? 7 : 1,
          'total': 16,
          'ships': List.generate(
            16,
            (i) => {
              'id': 'ship-$i',
              'title': '${cached ? 'Cached' : 'Fresh'} Ship $i',
            },
          ),
          'formerTotal': 0,
          'nextOffset': null,
          'savedAt': '2026-10-01T00:00:00Z',
        };
        Future<void> drain() async {
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            await tester.pump();
          }
        }

        await tester.runAsync(() async {
          pair = InMemoryBridgeConnection.createPair();
          var index = 0, roots = 0;
          session = BridgeClientSession(
            connection: pair.client,
            sessionGeneration: 0,
            correlationIdFactory: () =>
                index++ == 0 ? completed.correlationId! : 'hangar-ui-$index',
          );
          session.acceptHostCapabilities([
            'account.restoreDisplay',
            'profile.stagedRead',
            'hangar.localFavorites',
            if (hasModeOwner) 'onboarding.mode.v1',
          ]);
          account = createAccountModule(BridgeAccountAdapter(session));
          if (hasModeOwner) {
            mode = ConnectionModeController(
              BridgeConnectionModeAdapter(session),
            );
          }
          subscription = pair.host.incoming.listen((r) {
            requests.add(r);
            switch (r.name) {
              case 'account.getCurrent':
                if (roots++ == 0) break;
                final payload = {...completed.payload}
                  ..remove('restoreDisplayReadId');
                unawaited(
                  reply(
                    r,
                    signedOut
                        ? const {'schemaVersion': 1, 'state': 'signedOut'}
                        : payload,
                    public: signedOut,
                  ),
                );
              case 'account.offlineData.read':
                unawaited(reply(r, inventory(true), public: true));
              case 'profile.readDisplayCache':
                metadata.add(r);
              case 'hangarReader.inventory':
                fresh.add(r);
              case 'onboarding.mode.read':
                if (r.sessionGeneration == 0) {
                  unawaited(reply(r, modeWire('online'), public: true));
                } else {
                  modeReads.add(r);
                }
            }
          });
          pending = account.initialize();
          await Future<void>.delayed(Duration.zero);
          await mode?.refresh();
        });
        final feature = createHangarFeature(
          account,
          () => throw StateError('No scanner'),
          connectionMode: mode,
          localFactory: () => BridgeLocalHangar(
            session,
            displayHandoff: () => account.projection.value.hasDisplayHandoff
                ? account.projection.value.displayHandoff
                : null,
          ),
          retainedFactory: (id) => BridgeLocalHangar.retained(
            session,
            id,
            isCurrent: () =>
                account.projection.value.hasRetainedDisplayRead &&
                account.projection.value.retainedReadId == id,
          ),
        );
        var visible = true;
        late StateSetter navigate;
        try {
          await tester.pumpWidget(
            fixtures.app(
              StatefulBuilder(
                builder: (context, setState) {
                  navigate = setState;
                  return visible
                      ? feature.buildDestination(context)
                      : const SizedBox.shrink();
                },
              ),
            ),
          );
          await tester.runAsync(() => pair.host.send(prepared));
          await drain();
          expect(find.text('Cached Ship 0'), findsOneWidget);
          final original = tester.element(find.byType(LocalHangarPage));
          await tester.enterText(
            find.byKey(const Key('local-hangar-search')),
            'Ship',
          );
          await tester.tap(find.byKey(const Key('hangar-list')));
          await tester.pump();
          final viewport = find.byType(CustomScrollView).first;
          await tester.drag(viewport, const Offset(0, -300));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('local-hangar-ship-ship-0')),
          );
          await tester.tap(
            find.byKey(const ValueKey('local-hangar-ship-ship-0')),
          );
          await tester.pumpAndSettle();
          final inspector = tester.element(find.byType(LocalHangarDetail));
          final position = tester
              .widget<CustomScrollView>(viewport)
              .controller!
              .offset;
          expect(position, greaterThan(0));
          final readonlyCount = requests
              .where((r) => r.name == 'account.offlineData.read')
              .length;
          await tester.runAsync(() => pair.host.send(completed));
          await drain();
          expect(find.byType(LocalHangarPage), findsOneWidget);
          expect(tester.element(find.byType(LocalHangarPage)), same(original));
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('local-hangar-search')))
                .controller!
                .text,
            'Ship',
          );
          expect(
            tester.widget<CustomScrollView>(viewport).controller!.offset,
            position,
          );
          expect(
            tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).onRead,
            isNull,
          );
          expect(fresh, isEmpty);
          expect(
            tester.element(find.byType(LocalHangarDetail)),
            same(inspector),
          );
          await tester.runAsync(
            () => pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'account.changed',
                sessionGeneration: 1,
                sequence: prepared.sequence! + 1,
                payload: const {'schemaVersion': 1},
              ),
            ),
          );
          await drain();
          expect(tester.element(find.byType(LocalHangarPage)), same(original));
          expect(account.projection.value.retainedReadId, isNull);
          await tester.runAsync(() async {
            for (final r in metadata) {
              await reply(r, const {
                'schemaVersion': 1,
                'source': 'unavailable',
                'preferencesPolicy': {
                  'locales': [],
                  'timeZones': [],
                  'availableActions': [],
                },
              });
            }
          });
          await drain();
          expect(account.projection.value.isSignedIn, isTrue);
          if (hasModeOwner) {
            expect(mode!.allowsOnlineTraffic, isFalse);
            expect(fresh, isEmpty);
            expect(modeReads, hasLength(1));
            await tester.runAsync(
              () => reply(modeReads.single, modeWire('online'), public: true),
            );
            await drain();
          }
          expect(fresh, hasLength(1));
          expect(
            tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).onRead,
            isNull,
          );
          await tester.runAsync(() => reply(fresh.single, inventory(false)));
          await drain();
          expect(tester.element(find.byType(LocalHangarPage)), same(original));
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('local-hangar-ship-ship-0')),
              matching: find.text('Fresh Ship 0'),
            ),
            findsOneWidget,
          );
          expect(find.text('Cached Ship 0'), findsNothing);
          expect(
            tester.widget<CustomScrollView>(viewport).controller!.offset,
            position,
          );
          expect(
            tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).onRead,
            isNotNull,
          );
          expect(
            requests.where((r) => r.name == 'account.offlineData.read'),
            hasLength(readonlyCount),
          );
          expect(fresh.single.sessionGeneration, 1);
          expect(
            tester.element(find.byType(LocalHangarDetail)),
            same(inspector),
          );
          expect(
            tester
                .widget<LocalHangarShipDetails>(
                  find.byType(LocalHangarShipDetails),
                )
                .ship
                .title,
            'Fresh Ship 0',
          );
          Navigator.of(tester.element(find.byType(LocalHangarDetail))).pop();
          await tester.pumpAndSettle();
          // Closing the inspector restores input focus and can reveal the search
          // field. Navigation must preserve the actual position when leaving.
          await tester.drag(viewport, const Offset(0, -240));
          await tester.pumpAndSettle();
          final leavingPosition = tester
              .widget<CustomScrollView>(viewport)
              .controller!
              .offset;
          expect(leavingPosition, greaterThan(100));
          final readCount = requests.length;
          navigate(() => visible = false);
          await tester.pumpAndSettle();
          navigate(() => visible = true);
          await tester.pumpAndSettle();
          // Inspect retained state without revealing the offscreen toolbar:
          // doing so would change the scroll position we are verifying.
          expect(
            tester
                .widget<TextField>(
                  find.byKey(
                    const Key('local-hangar-search'),
                    skipOffstage: false,
                  ),
                )
                .controller!
                .text,
            'Ship',
          );
          expect(
            tester.widget<CustomScrollView>(viewport).controller!.offset,
            leavingPosition,
          );
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const Key('hangar-list'), skipOffstage: false),
                )
                .isSelected,
            isTrue,
          );
          expect(requests.length, readCount);
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
          });
          await drain();
          expect(find.text('Fresh Ship 0'), findsNothing);
          expect(find.byType(LocalHangarDetail), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            feature.onDispose?.call();
            mode?.dispose();
            account.dispose();
            await session.close();
            await pending;
            await subscription.cancel();
            await pair.host.close();
          });
        }
      },
      skip: _path.isEmpty,
    );
  }
}
