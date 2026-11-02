import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> wire() => {
  'schemaVersion': 1,
  'stateKey': 'fixture-state-key-01',
  'facts': <String, Object?>{
    'eligibility': 'firstUse',
    'available': true,
    'canSave': true,
    'sourceKey': 'fixture-source-live-1',
    'evidenceKey': 'fixture-evidence-0001',
    'version': 'LIVE',
    'logReady': true,
    'evidence': 'candidate',
    'origin': 'current',
    'handle': 'Pilot-Example',
    'observedAt': '2026-01-01T12:00:00Z',
    'scopeChecked': true,
    'requiresFreshEvidence': false,
    'localIdentityConfirmed': false,
    'localSettingsReady': false,
    'signedIn': false,
    'onlineIdentityMatched': false,
    'onlineChoicesReviewed': false,
    'activeMode': 'local',
    'publicationSuspended': true,
    'onlineSetupPending': false,
  },
  'restored': null,
  'saved': null,
  'completed': null,
};
OnboardingCheckpoint checkpoint() => const OnboardingCheckpoint(
  step: OnboardingStep.identity,
  mode: OnboardingMode.local,
  sourceKey: 'fixture-source-live-1',
  evidenceKey: 'fixture-evidence-0001',
);

void main() {
  test(
    'device exceptions are exact; other business calls still need an account',
    () {
      for (final name in [
        'onboarding.read',
        'onboarding.startup.read',
        'onboarding.execute',
        'onboarding.saveProgress',
        'onboarding.finish',
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(name, null),
          returnsNormally,
        );
      }
      for (final name in [
        'onboarding.delete',
        'onboarding.startup.finish',
        'onboarding.executeAnything',
        'friends.read',
        'gameLog.read',
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(name, null),
          throwsA(isA<BridgeAccountContextRequiredException>()),
        );
      }
    },
  );
  test('strict Host facts parse without inferred readiness', () {
    final reply = OnboardingWire.parse(wire()).$2;
    expect(reply.facts.hasCandidate, true);
    expect(reply.facts.localIdentityConfirmed, false);
    expect(reply.facts.signedIn, false);
    expect(reply.completed, null);
  });

  test('confirmed local receipt is distinct from live identity and SCM', () {
    final value = wire();
    final raw = value['facts']! as Map<String, Object?>;
    raw.addAll({'origin': 'confirmedLocal', 'scopeChecked': false});
    final facts = OnboardingWire.parse(value).$2.facts;
    expect(facts.origin, OnboardingEvidenceOrigin.confirmedLocal);
    expect(facts.hasCandidate, true);
    expect(facts.localIdentityConfirmed, false);
    expect(facts.signedIn, false);
    expect(facts.onlineIdentityMatched, false);
    raw['requiresFreshEvidence'] = true;
    expect(() => OnboardingWire.parse(value), throwsFormatException);
  });

  for (final field in [
    'available',
    'canSave',
    'logReady',
    'scopeChecked',
    'requiresFreshEvidence',
    'localIdentityConfirmed',
    'localSettingsReady',
    'signedIn',
    'onlineIdentityMatched',
    'onlineChoicesReviewed',
    'publicationSuspended',
  ]) {
    test('missing or non-boolean $field is rejected', () {
      for (final bad in [null, 1, 'true']) {
        final value = wire();
        (value['facts']! as Map<String, Object?>)[field] = bad;
        expect(() => OnboardingWire.parse(value), throwsFormatException);
      }
      final value = wire();
      (value['facts']! as Map<String, Object?>).remove(field);
      expect(() => OnboardingWire.parse(value), throwsFormatException);
    });
  }

  test(
    'unknown versions, enums, fields and private-looking tokens fail closed',
    () {
      for (final override in [
        {'schemaVersion': 2},
        {'schemaVersion': 1.0},
        {'stateKey': 'C:/User/Game.log'},
        {'stateKey': null},
        {'unexpected': true},
      ]) {
        expect(
          () => OnboardingWire.parse({...wire(), ...override}),
          throwsFormatException,
        );
      }
      for (final override in [
        {'eligibility': 'newVersion'},
        {'evidence': 'ready'},
        {'origin': 'launcher'},
        {'sourceKey': 'C:/User/Game.log'},
        {'handle': 'manual handle'},
        {'observedAt': 'not-a-time'},
        {'observedAt': '2026-01-01T12:00:00'},
        {'observedAt': '2026-02-31T12:00:00Z'},
        {'observedAt': '2026-01-01T24:00:00Z'},
        {'observedAt': '2099-01-01T12:00:00Z'},
        {'sourceKey': null},
        {'origin': null},
        {'handle': null},
        {'onlineIdentityMatched': true},
        {'unexpected': true},
      ]) {
        final value = wire();
        (value['facts']! as Map<String, Object?>).addAll(override);
        expect(() => OnboardingWire.parse(value), throwsFormatException);
      }
    },
  );

  test(
    'old Host remains unavailable and receives no first-use request',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.close);
      fixture.session.acceptHostCapabilities([]);
      final reply = await fixture.adapter.read();
      expect(reply.facts.available, false);
      expect(reply.facts.eligibility, OnboardingEligibility.unknown);
      expect(fixture.requests, isEmpty);
      expect(() => fixture.adapter.save(checkpoint()), throwsStateError);
    },
  );

  test(
    'commands carry only opaque observation and UI intent, not an account',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.close);
      await fixture.adapter.read();
      await fixture.adapter.save(checkpoint());
      final request = fixture.requests.last;
      expect(request.name, 'onboarding.saveProgress');
      expect(request.accountContext, null);
      expect(
        request.payload.keys,
        unorderedEquals(['schemaVersion', 'expectedStateKey', 'checkpoint']),
      );
      expect(request.payload['expectedStateKey'], 'fixture-state-key-01');
      expect(request.payload.toString(), isNot(contains('Pilot-Example')));
      expect(
        () => fixture.adapter.save(const OnboardingCheckpoint()),
        throwsStateError,
      );
    },
  );

  test(
    'invalidation rejects a late response and requires a fresh read',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.close);
      final seen = Completer<BridgeEnvelope>();
      fixture.onRequest = (request) async {
        seen.complete(request);
      };
      final events = fixture.adapter.invalidations.listen((_) {});
      addTearDown(events.cancel);
      final read = fixture.adapter.read();
      final failed = expectLater(read, throwsStateError);
      final request = await seen.future;
      await fixture.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'onboarding.changed',
          sessionGeneration: 3,
          sequence: 1,
          payload: const {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await fixture.respond(request);
      await failed;
      expect(() => fixture.adapter.finish(checkpoint()), throwsStateError);
      fixture.onRequest = null;
      expect((await fixture.adapter.read()).facts.hasCandidate, true);
    },
  );

  test(
    'failed and malformed replies clear the prior write observation',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.close);
      await fixture.adapter.read();
      fixture.onRequest = (request) =>
          fixture.respond(request, payload: const {});
      await expectLater(fixture.adapter.read(), throwsFormatException);
      expect(() => fixture.adapter.save(checkpoint()), throwsStateError);
    },
  );
  test('transport failure clears the prior write observation', () async {
    final fixture = Fixture();
    addTearDown(fixture.close);
    await fixture.adapter.read();
    await fixture.session.close();
    await expectLater(
      fixture.adapter.read(),
      throwsA(isA<BridgeDisconnectedException>()),
    );
    expect(() => fixture.adapter.save(checkpoint()), throwsStateError);
  });
  test('Native generation handoff preserves the guide observation without granting an account', () async {
    final fixture = Fixture();
    addTearDown(fixture.close);
    fixture.onRequest = (request) => fixture.respond(request, payload: {...wire(), 'controlGeneration': 5});
    final reply = await fixture.adapter.read();
    expect(fixture.session.activeGeneration, 5);
    expect(reply.facts.signedIn, false);
    await fixture.adapter.save(checkpoint());
    expect(fixture.requests.last.sessionGeneration, 5);
    expect(fixture.requests.last.accountContext, isNull);
  });
  test('invalid generation cannot replace the current guide observation', () async {
    final fixture = Fixture();
    addTearDown(fixture.close);
    fixture.onRequest = (request) => fixture.respond(request, payload: {...wire(), 'controlGeneration': 2});
    await expectLater(fixture.adapter.read(), throwsFormatException);
    expect(fixture.session.activeGeneration, 3);
    expect(() => fixture.adapter.save(checkpoint()), throwsStateError);
  });
}

class Fixture {
  Fixture() {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    session.acceptHostCapabilities([BridgeOnboardingAdapter.capability]);
    adapter = BridgeOnboardingAdapter(session);
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
  late final BridgeOnboardingAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Future<void> Function(BridgeEnvelope)? onRequest;
  Future<void> respond(
    BridgeEnvelope request, {
    Map<String, Object?>? payload,
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      status: 'ok',
      payload: payload ?? wire(),
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
