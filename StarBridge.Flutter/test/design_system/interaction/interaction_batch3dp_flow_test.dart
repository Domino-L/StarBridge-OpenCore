import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/community_sharing_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../../app/community_sharing_flow_test.dart' as flow;
import '../../features/settings/community_join_hangar_choice_test.dart'
    as hangar;
import '../../features/settings/community_sharing_test.dart' as privacy;
import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_test.dart';

class GatedPrivacy extends privacy.SharingFixture {
  Completer<bool>? gate;
  int started = 0;
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings value) async {
    started++;
    await gate?.future;
    return super.save(value);
  }
}

class GatedHangar extends hangar.JoinHangarFixture {
  Completer<bool>? gate;
  int started = 0;
  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> refs, {
    bool includeImages = false,
  }) async {
    started++;
    await gate?.future;
    return super.saveHangarSharing(editRef, refs, includeImages: includeImages);
  }
}

// Own this single-subscription test transport from construction; never cancel
// and re-subscribe another fixture's stream to intercept a response.
class GatedEvents {
  GatedEvents(this.gate) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities(const ['eventSharing.settings']);
    subscription = connection.incoming.listen(
      (request) => unawaited(reply(request)),
    );
  }
  final Completer<bool>? gate;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  int started = 0;
  Map<String, Object?> snapshot = {
    'schemaVersion': 1,
    'revision': 0,
    'operationId': null,
    'appliedAt': null,
    'publicationEnabled': false,
    'settings': null,
  };
  Future<void> reply(BridgeEnvelope request) async {
    if (request.name == 'eventSharing.save') {
      started++;
      await gate?.future;
      snapshot = {
        'schemaVersion': 1,
        'revision': (request.payload['expectedRevision'] as int) + 1,
        'operationId': request.payload['operationId'],
        'appliedAt': '2026-10-16T00:00:00Z',
        'publicationEnabled': request.payload['publicationEnabled'],
        'settings': request.payload['settings'],
      };
    }
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: const BridgeAccountContext(
          environment: 'test',
          authority: 'scm',
          subject: 'synthetic-owner',
        ),
        status: 'ok',
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedIn'}
            : request.name == 'privacy.communityTargets'
            ? {
                'schemaVersion': 2,
                'primaryFleetCode': null,
                'communities': [
                  for (final code in ['A', 'B'])
                    {
                      'code': code,
                      'name': code,
                      'joinedAt': privacy.membershipTime,
                    },
                ],
              }
            : {'snapshot': snapshot, 'state': 'inactive'},
      ),
    );
  }

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final stage in [0, 1, 2]) {
      testWidgets(
        '${suite.name} real flow invalidation at stage $stage preserves unrelated top route and stops continuation',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final gate = Completer<bool>();
          final port = GatedPrivacy()
            ..gate = stage == 2 ? gate : null
            ..settings = LocalPrivacySettings.editorDefaults.copyWith(
              publicationEnabled: true,
              communities: [privacy.target('A').choice(fields: 1)],
            )
            ..targets = CommunitySharingTargets(
              primaryFleetCode: 'A',
              communities: [privacy.target('A'), privacy.target('B')],
            );
          final p = GatedHangar()..gate = stage == 0 ? gate : null;
          final events = GatedEvents(stage == 1 ? gate : null);
          final controller = LocalPrivacyController(port);
          final queue = StartupPromptQueue();
          final key = GlobalKey<NavigatorState>();
          final base =
              fixture.scopedApp(const SizedBox(), suite) as MaterialApp;
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: key,
              navigatorObservers: [queue],
              locale: base.locale,
              supportedLocales: base.supportedLocales,
              localizationsDelegates: base.localizationsDelegates,
              theme: base.theme,
              builder: base.builder,
              home: const Scaffold(),
            ),
          );
          await t.pumpAndSettle();
          final h = flow.Harness(
            port,
            controller,
            queue,
            key,
            p,
            events.session,
          );
          try {
            await controller.refresh();
            await h.settle(t);
            final route = ModalRoute.of(
              t.element(find.byType(CommunitySharingDialog)),
            )!;
            await submit(t, 'pointer');
            // The in-memory bridge completes via microtasks, not real network I/O.
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 20));
              if ((stage == 0 && p.started == 1) ||
                  (stage == 1 && events.started == 1) ||
                  (stage == 2 && port.started == 1)) {
                break;
              }
            }
            expect(
              [p.started, events.started, port.started],
              [1, stage > 0 ? 1 : 0, stage > 1 ? 1 : 0],
            );
            key.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Unrelated manual route')),
              ),
            );
            await t.pump();
            h.ready = false;
            port.events.add(null);
            await t.pump();
            await t.pump();
            expect(route.isActive, isFalse);
            gate.complete(true);
            await h.settle(t);
            expect(find.text('Unrelated manual route'), findsOneWidget);
            expect(
              [p.started, events.started, port.started],
              [1, stage > 0 ? 1 : 0, stage > 1 ? 1 : 0],
            );
            expect(port.applies, 0);
            expect(t.takeException(), isNull);
          } finally {
            if (!gate.isCompleted) gate.complete(false);
            await h.dispose(t);
            await t.runAsync(events.close);
            await p.events.close();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
    testWidgets(
      '${suite.name} same organization code with new joinedAt retires old membership prompt',
      (t) async {
        fixture.size(t, const Size(960, 900));
        final h = await flow.Harness.create(t);
        final base = fixture.scopedApp(const SizedBox(), suite) as MaterialApp;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: h.key,
            navigatorObservers: [h.queue],
            locale: base.locale,
            supportedLocales: base.supportedLocales,
            localizationsDelegates: base.localizationsDelegates,
            theme: base.theme,
            builder: base.builder,
            home: const Scaffold(),
          ),
        );
        await t.pumpAndSettle();
        await h.controller.refresh();
        await h.settle(t);
        final oldRoute = ModalRoute.of(
          t.element(find.byType(CommunitySharingDialog)),
        )!;
        h.key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Manual task')),
          ),
        );
        h.port.targets = CommunitySharingTargets(
          primaryFleetCode: 'A',
          communities: [
            privacy.target('A'),
            CommunitySharingTarget(
              code: 'B',
              name: 'New membership',
              joinedAt: '2026-10-16T00:00:00Z',
            ),
          ],
        );
        await h.controller.refreshCommunityTargets();
        await h.settle(t);
        expect(oldRoute.isActive, isFalse);
        expect(find.text('Manual task'), findsOneWidget);
        expect(h.port.writes, 0);
        await h.dispose(t);
      },
    );
  }
}
