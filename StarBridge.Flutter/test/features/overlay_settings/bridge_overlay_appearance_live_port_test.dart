import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_appearance_live_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';

import 'overlay_appearance_live_session_test.dart' show frame, flush;

const sessionId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final class Harness {
  Harness({bool supported = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(
      supported
          ? {BridgeOverlayAppearanceLivePort.capability}
          : {'overlay.appearancePreview'},
    );
    port = BridgeOverlayAppearanceLivePort(session);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (holdOpen && request.name.endsWith('.open')) {
        pendingOpen = request;
        return;
      }
      final payload =
          responseOverride ??
          switch (request.name.split('.').last) {
            'open' => {'schemaVersion': 1, 'sessionId': sessionId},
            'update' || 'protect' || 'renew' => {
              'schemaVersion': 1,
              'revision': request.payload['revision'],
            },
            'close' => {'schemaVersion': 1, 'closed': true},
            'playback' => {
              'schemaVersion': 1,
              'revision': request.payload['revision'],
              'accepted': true,
            },
            _ => throw StateError('unknown route'),
          };
      await respond(request, payload);
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeOverlayAppearanceLivePort port;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  bool holdOpen = false;
  BridgeEnvelope? pendingOpen;
  Map<String, Object?>? responseOverride;
  String? responseName;
  Future<void> respond(BridgeEnvelope request, Map<String, Object?> payload) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: responseName ?? request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          payload: payload,
          status: 'ok',
        ),
      );
  Future<void> ownerEvent() => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: session.activeGeneration,
      sequence: 1,
      payload: const {},
    ),
  );
  Future<void> close() async {
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }
}

void main() {
  for (final reason in ['interaction-space', 'observation-only']) {
    test(
      'visible decoration feedback $reason is bounded read-only metadata',
      () async {
        final h = Harness();
        h.responseOverride = {
          'schemaVersion': 1,
          'sessionId': sessionId,
          'placementStates': [
            {'slotId': 'slot0', 'reason': reason},
          ],
        };
        final live = OverlayAppearanceLiveSession(h.port);
        await live.open(frame());
        expect(live.placementStates, {'slot0': reason});
        expect(h.requests.last.payload['frame'], frame().toMap());
        h.responseOverride = null;
        await live.close();
        expect(live.placementStates, isEmpty);
        live.dispose();
        await h.close();
      },
    );
  }
  test(
    'placement feedback is finite, latest-frame only and cannot mutate options',
    () async {
      final h = Harness();
      h.responseOverride = {
        'schemaVersion': 1,
        'sessionId': sessionId,
        'placementStates': [
          {'slotId': 'slot0', 'reason': 'screen-edge'},
        ],
      };
      final live = OverlayAppearanceLiveSession(h.port);
      await live.open(frame());
      expect(live.placementStates, {'slot0': 'screen-edge'});
      expect(
        () => live.placementStates['other'] = 'placed',
        throwsUnsupportedError,
      );
      h.responseOverride = {
        'schemaVersion': 1,
        'revision': 1,
        'placementStates': [
          {'slotId': 'slot0', 'reason': 'placed'},
        ],
      };
      live.update(frame());
      expect(live.placementStates, isEmpty);
      await flush();
      expect(live.placementStates, {'slot0': 'placed'});
      final sent = h.requests.last;
      expect(sent.payload['frame'], frame().toMap());
      for (final rows in [
        null,
        [
          {'slotId': 'slot0', 'reason': 'execute'},
        ],
        [
          {'slotId': 'slot0', 'reason': 'placed', 'command': 'wake'},
        ],
        [
          {'slotId': 'slot0', 'reason': 'placed'},
          {'slotId': 'slot0', 'reason': 'screen-edge'},
        ],
      ]) {
        h.responseOverride = {
          'schemaVersion': 1,
          'revision': 2,
          'placementStates': rows,
        };
        await expectLater(
          h.port.updateLivePreview(sessionId, 2, frame()),
          throwsFormatException,
        );
        expect(h.port.placementStates, {'slot0': 'placed'});
      }
      h.responseOverride = null;
      await live.close();
      expect(live.placementStates, isEmpty);
      live.dispose();
      await h.close();
    },
  );
  test(
    'finite renewal wire contains no frame clock account or pet command',
    () async {
      final h = Harness();
      expect(await h.port.renewLivePreview(sessionId, 1), 1);
      expect(h.requests.single.name, 'overlay.appearanceLivePreview.renew');
      expect(h.requests.single.accountContext, isNull);
      expect(h.requests.single.payload, {
        'schemaVersion': 1,
        'sessionId': sessionId,
        'revision': 1,
      });
      h.responseOverride = {'schemaVersion': 1, 'revision': 1};
      await expectLater(
        h.port.renewLivePreview(sessionId, 2),
        throwsFormatException,
      );
      h.responseOverride = {
        'schemaVersion': 1,
        'revision': 3,
        'petAction': 'wake',
      };
      await expectLater(
        h.port.renewLivePreview(sessionId, 3),
        throwsFormatException,
      );
      await expectLater(
        h.port.renewLivePreview(sessionId, 0),
        throwsFormatException,
      );
      await expectLater(
        h.port.renewLivePreview('bad-session', 1),
        throwsFormatException,
      );
      expect(h.requests, hasLength(3));
      await h.close();
    },
  );

  test(
    'finite playback wire contains only session revision and a normal example',
    () async {
      final h = Harness();
      final live = OverlayAppearanceLiveSession(h.port);
      await live.open(frame());
      for (final action in OverlayAppearancePreviewPlayback.values) {
        expect(await live.play(action), isTrue);
        final request = h.requests.last;
        expect(
          request.name,
          '${BridgeOverlayAppearanceLivePort.capability}.playback',
        );
        expect(request.payload.keys.toSet(), {
          'schemaVersion',
          'sessionId',
          'revision',
          'action',
        });
        expect(request.payload['action'], action.wireName);
        expect(request.accountContext, isNull);
      }
      h.responseOverride = {
        'schemaVersion': 1,
        'revision': OverlayAppearancePreviewPlayback.values.length + 1,
        'accepted': false,
      };
      expect(
        await live.play(OverlayAppearancePreviewPlayback.barrage),
        isFalse,
      );
      h.responseOverride = {
        'schemaVersion': 1,
        'revision': OverlayAppearancePreviewPlayback.values.length + 2,
        'accepted': true,
        'petAction': 'wake',
      };
      await expectLater(
        live.play(OverlayAppearancePreviewPlayback.noticeShow),
        throwsFormatException,
      );
      expect(live.playbackBusy, isFalse);
      h.responseOverride = null;
      await live.close();
      live.dispose();
      await h.close();
    },
  );
  test('control protection carries normalized rectangles only, not HWND or screen origin', () async {
    final h = Harness();
    final live = OverlayAppearanceLiveSession(h.port);
    await live.open(frame());
    await live.protectControls([const OverlayPreviewControlArea(.8, 0, .2, 1)]);
    expect(h.requests.last.payload, {
      'schemaVersion': 1,
      'sessionId': sessionId,
      'revision': 1,
      'areas': [
        {'x': .8, 'y': 0.0, 'width': .2, 'height': 1.0},
      ],
    });
    await expectLater(
      h.port.protectLivePreviewControls(sessionId, 2, [
        const OverlayPreviewControlArea(0, 0, 2, 1),
      ]),
      throwsFormatException,
    );
    await live.close();
    live.dispose();
    await h.close();
  });
  test(
    'old capability does not start carrier or pretend to support updates',
    () async {
      final h = Harness(supported: false);
      expect(h.port.supported, isFalse);
      await expectLater(h.port.openLivePreview(frame()), throwsStateError);
      expect(h.requests, isEmpty);
      await h.close();
    },
  );
  test(
    'actual Bridge session serializes only finite frame and session revisions',
    () async {
      final h = Harness();
      final live = OverlayAppearanceLiveSession(h.port);
      await live.open(frame());
      live.update(frame('Verdict', true));
      await Future<void>.delayed(Duration.zero);
      await flush();
      expect(live.appliedRevision, 1);
      await live.close();
      expect(h.requests.map((r) => r.name), [
        'overlay.appearanceLivePreview.open',
        'overlay.appearanceLivePreview.update',
        'overlay.appearanceLivePreview.close',
      ]);
      final open = h.requests.first;
      expect(open.accountContext, isNull);
      expect(open.payload.keys.toSet(), {'schemaVersion', 'frame'});
      expect((open.payload['frame'] as Map).keys.toSet(), {
        'appearanceId',
        'settings',
        'layout',
        'appearanceOptions',
        'language',
        'reduceMotion',
      });
      final update = h.requests[1];
      expect(update.payload['revision'], 1);
      expect((update.payload['frame'] as Map)['appearanceId'], 'Verdict');
      expect(h.requests.last.payload, {
        'schemaVersion': 1,
        'sessionId': sessionId,
      });
      live.dispose();
      await h.close();
    },
  );
  test(
    'unexpected response fields are rejected, not successful open',
    () async {
      final h = Harness()
        ..responseOverride = {
          'schemaVersion': 1,
          'sessionId': sessionId,
          'entitlement': true,
        };
      await expectLater(h.port.openLivePreview(frame()), throwsFormatException);
      await h.close();
    },
  );
  test('wrong response route and revision cannot advance preview', () async {
    final h = Harness()..responseName = 'overlay.runtime.open';
    await expectLater(h.port.openLivePreview(frame()), throwsFormatException);
    h.responseName = null;
    h.responseOverride = {'schemaVersion': 1, 'revision': 2};
    await expectLater(
      h.port.updateLivePreview(sessionId, 1, frame()),
      throwsFormatException,
    );
    await h.close();
  });
  test('invalid ID/revision rejected before sending to Host', () async {
    final h = Harness();
    await expectLater(
      h.port.updateLivePreview('not-session', 1, frame()),
      throwsFormatException,
    );
    await expectLater(
      h.port.updateLivePreview(sessionId, 0, frame()),
      throwsFormatException,
    );
    await expectLater(
      h.port.closeLivePreview('not-session'),
      throwsFormatException,
    );
    expect(h.requests, isEmpty);
    await h.close();
  });
  test('account ownership event closes one native session and blocks further edits', () async {
    final h = Harness();
    final live = OverlayAppearanceLiveSession(h.port);
    await live.open(frame());
    h.session.advanceGeneration(2);
    await h.ownerEvent();
    await Future<void>.delayed(Duration.zero);
    await flush();
    expect(live.phase, OverlayAppearanceLivePhase.closed);
    expect(h.requests.last.name, 'overlay.appearanceLivePreview.close');
    expect(h.requests.last.sessionGeneration, 2);
    expect(() => live.update(frame()), throwsStateError);
    live.dispose();
    await h.close();
  });
  test('pending former-generation open cannot revive preview on owner change', () async {
    final h = Harness()..holdOpen = true;
    final live = OverlayAppearanceLiveSession(h.port);
    final opening = live.open(frame());
    await Future<void>.delayed(Duration.zero);
    expect(h.pendingOpen, isNotNull);
    h.session.advanceGeneration(2);
    await h.ownerEvent();
    await opening;
    await h.respond(h.pendingOpen!, {
      'schemaVersion': 1,
      'sessionId': sessionId,
    });
    await Future<void>.delayed(Duration.zero);
    await flush();
    expect(live.phase, OverlayAppearanceLivePhase.closed);
    expect(live.hasSession, isFalse);
    expect(h.requests.where((r) => r.name.endsWith('.update')), isEmpty);
    // The discarded response has no usable ID in this transport; the real
    // Native scope watchdog independently cleans it (covered in Native tests).
    live.dispose();
    await h.close();
  });
}
