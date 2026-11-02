import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_native_overlay_observation.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_observation.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> observationWire({int count = 0, String? outcome}) => {
  'schemaVersion': 1,
  'runtimeId': '11111111111111111111111111111111',
  'appliedRevision': 2,
  'windowState': 'closed',
  'nativeWindowVisible': false,
  'firstFrameCommitted': false,
  'hotkey': <String, Object?>{
    'state': 'registered',
    'binding': 'Alt+F10',
    'configurationRevision': 1,
    'acceptedInputCount': count,
    'lastOutcome': outcome,
  },
  'preview': <String, Object?>{
    'sessionId': null,
    'appliedRevision': null,
    'nativeWindowVisible': false,
    'firstFrameCommitted': false,
  },
};

void main() {
  test('registration is not input; accepted input may still fail', () {
    final baseline = NativeOverlayObservationWire.parse(observationWire(), 3);
    final registered = NativeOverlayObservationWire.parse(observationWire(), 3);
    expect(registered.acceptedHotkeyInputSince(baseline), false);
    final failed = NativeOverlayObservationWire.parse(
      observationWire(count: 1, outcome: 'failed'),
      3,
    );
    expect(failed.acceptedHotkeyInputSince(baseline), true);
    expect(failed.hotkey.lastOutcome, 'failed');
    expect(failed.nativeWindowVisible, false);
    expect(failed.firstFrameCommitted, false);
  });
  test('baselines do not cross instances, Host generations, chords or configuration epochs', () {
    final baseline = NativeOverlayObservationWire.parse(observationWire(), 3);
    final raw = observationWire(count: 1, outcome: 'open');
    expect(
      NativeOverlayObservationWire.parse(
        raw,
        4,
      ).acceptedHotkeyInputSince(baseline),
      false,
    );
    expect(
      NativeOverlayObservationWire.parse({
        ...raw,
        'runtimeId': '22222222222222222222222222222222',
      }, 3).acceptedHotkeyInputSince(baseline),
      false,
    );
    for (final change in <Map<String, Object?>>[
      {'binding': 'Alt+F11'},
      {'configurationRevision': 2},
      {'acceptedInputCount': 0, 'lastOutcome': null},
    ]) {
      expect(
        NativeOverlayObservationWire.parse({
          ...raw,
          'hotkey': {...raw['hotkey'] as Map<String, Object?>, ...change},
        }, 3).acceptedHotkeyInputSince(baseline),
        false,
      );
    }
  });
  test(
    'preview frame and HWND facts stay separate from normal overlay visibility',
    () {
      final raw = observationWire();
      raw['preview'] = <String, Object?>{
        'sessionId': '33333333333333333333333333333333',
        'appliedRevision': 0,
        'nativeWindowVisible': true,
        'firstFrameCommitted': true,
      };
      final observation = NativeOverlayObservationWire.parse(raw, 3);
      expect(observation.preview.nativeWindowVisible, true);
      expect(observation.nativeWindowVisible, false);
      expect(observation.hotkey.acceptedInputCount, 0);
    },
  );
  test(
    'strict finite projections reject missing, extra and fabricated facts',
    () {
      for (final change in <Map<String, Object?>>[
        {'schemaVersion': true},
        {'windowState': 'ready'},
        {'runtimeId': 'path'},
        {'appliedRevision': -1},
        {'appliedRevision': 1.5},
        {'nativeWindowVisible': 'true'},
        {'ready': true},
        {'hotkey': null},
      ]) {
        expect(
          () => NativeOverlayObservationWire.parse({
            ...observationWire(),
            ...change,
          }, 3),
          throwsFormatException,
        );
      }
      for (final change in <Map<String, Object?>>[
        {'state': 'ready'},
        {'binding': 'Alt\nF10'},
        {'configurationRevision': -1},
        {'acceptedInputCount': 9007199254740992},
        {'lastOutcome': 'open'},
        {'acceptedInputCount': 1},
        {'verified': true},
      ]) {
        final raw = observationWire();
        raw['hotkey'] = {...raw['hotkey'] as Map<String, Object?>, ...change};
        expect(
          () => NativeOverlayObservationWire.parse(raw, 3),
          throwsFormatException,
        );
      }
      for (final change in <Map<String, Object?>>[
        {'nativeWindowVisible': true},
        {'firstFrameCommitted': true},
        {'sessionId': '33333333333333333333333333333333'},
        {'appliedRevision': 1},
        {'sessionId': 'path'},
      ]) {
        final raw = observationWire();
        raw['preview'] = {...raw['preview'] as Map<String, Object?>, ...change};
        expect(
          () => NativeOverlayObservationWire.parse(raw, 3),
          throwsFormatException,
        );
      }
      final raw = observationWire()..remove('preview');
      expect(
        () => NativeOverlayObservationWire.parse(raw, 3),
        throwsFormatException,
      );
    },
  );
  test(
    'subset capability sends one exact accountless read and no commands',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final value = await f.adapter.read();
      expect(value!.hotkey.acceptedInputCount, 0);
      expect(
        f.requests.single.name,
        BridgeNativeOverlayObservation.readRequest,
      );
      expect(f.requests.single.accountContext, null);
      expect(f.requests.single.payload, {'schemaVersion': 1});
      f.session.acceptHostCapabilities([]);
      expect(await f.adapter.read(), null);
      expect(f.requests, hasLength(1));
    },
  );
  test(
    'invalidation rejects an in-flight observation even without a UI listener',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final entered = Completer<BridgeEnvelope>();
      f.onRequest = (request) async => entered.complete(request);
      final pending = f.adapter.read();
      final request = await entered.future;
      await f.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'onboarding.changed',
          sequence: 1,
          correlationId: 'synthetic-event',
          sessionGeneration: 3,
          status: 'ok',
          payload: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final rejected = expectLater(pending, throwsStateError);
      await f.respond(request);
      await rejected;
    },
  );
  test('newer reads and disposal reject delayed responses; borrowed session survives', () async {
    final f = Fixture();
    addTearDown(f.close);
    final entered = Completer<BridgeEnvelope>();
    f.onRequest = (request) async => entered.complete(request);
    final old = f.adapter.read();
    final request = await entered.future;
    f.onRequest = null;
    expect(await f.adapter.read(), isNotNull);
    final rejected = expectLater(old, throwsStateError);
    await f.respond(request);
    await rejected;
    final later = Completer<BridgeEnvelope>();
    f.onRequest = (request) async => later.complete(request);
    final pending = f.adapter.read();
    final delayed = await later.future;
    await f.adapter.dispose();
    final disposed = expectLater(pending, throwsStateError);
    await f.respond(delayed);
    await disposed;
    await expectLater(f.adapter.read(), throwsStateError);
    f.onRequest = null;
    await f.session.request(
      BridgeNativeOverlayObservation.readRequest,
      payload: const {'schemaVersion': 1},
    );
  });
  test(
    'bad projection and transport failure cannot supply a saved observation',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      var invalidations = 0;
      final subscription = f.adapter.invalidations.listen(
        (_) => invalidations++,
      );
      addTearDown(subscription.cancel);
      f.payload = {...observationWire(), 'firstFrameCommitted': 'true'};
      await expectLater(f.adapter.read(), throwsFormatException);
      expect(invalidations, 1);
      f.payload = null;
      expect(await f.adapter.read(), isNotNull);
      await f.pair.host.close();
      await expectLater(f.adapter.read(), throwsA(isA<Object>()));
      expect(invalidations, 2);
    },
  );
}

class Fixture {
  Fixture() {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 3)
      ..acceptHostCapabilities([BridgeNativeOverlayObservation.capability]);
    adapter = BridgeNativeOverlayObservation(session);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (onRequest != null) {
        await onRequest!(request);
      } else {
        await respond(request);
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeNativeOverlayObservation adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Future<void> Function(BridgeEnvelope)? onRequest;
  Map<String, Object?>? payload;
  Future<void> respond(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      status: 'ok',
      payload: payload ?? observationWire(),
    ),
  );
  Future<void> close() async {
    await adapter.dispose();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
