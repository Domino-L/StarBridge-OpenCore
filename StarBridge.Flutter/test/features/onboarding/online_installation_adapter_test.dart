import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'online_review_test_support.dart';

Map<String, Object?> installationWire({
  String phase = 'completed',
  String state = 'online',
  int generation = 8,
  int modeRevision = 4,
}) => {
  'schemaVersion': 1,
  'revision': 3,
  'phase': phase,
  'controlGeneration': generation,
  'modeRevision': modeRevision,
  'modeState': state,
};

OnlineBridgeFixture installationFixture() {
  final f = OnlineBridgeFixture(capability: false);
  f.session.acceptHostCapabilities([
    BridgeOnlineInstallationAdapter.capability,
  ]);
  f.payload = installationWire();
  return f;
}

void main() {
  test(
    'failed original installation accepts only bounded diagnostic facts',
    () {
      final raw = {
        ...installationWire(state: 'offline'),
        'failure': {'stage': 'configureBusiness', 'kind': 'storage'},
      };
      final value = OnlineInstallationWire.parse(raw, 3, 7);
      expect(value.online, isFalse);
      expect(value.failure!.code, 'configureBusiness/storage');
      expect(
        OnlineInstallationWire.parse(
          installationWire(state: 'offline'),
          3,
          7,
        ).failure,
        isNull,
      );
      for (final invalid in [
        {...raw, 'modeState': 'online'},
        {...raw, 'phase': 'running'},
        {...raw, 'failure': null},
        {
          ...raw,
          'failure': {'stage': 'private path', 'kind': 'storage'},
        },
        {
          ...raw,
          'failure': {'stage': 'configureBusiness', 'kind': 'raw exception'},
        },
        {
          ...raw,
          'failure': {
            'stage': 'configureBusiness',
            'kind': 'storage',
            'message': 'private',
          },
        },
      ]) {
        expect(
          () => OnlineInstallationWire.parse(invalid, 3, 7),
          throwsFormatException,
        );
      }
    },
  );
  test('only the two exact installation routes are accountless', () {
    for (final action in ['read', 'install']) {
      expect(
        () => BridgeRequestPolicy.requireAccountContext(
          'onboarding.onlineInstallation.$action',
          null,
        ),
        returnsNormally,
      );
    }
    for (final name in [
      'onboarding.onlineInstallation.install.extra',
      'onboarding.onlineInstallation.finish',
      'friends.read',
      'presence.set',
    ]) {
      expect(
        () => BridgeRequestPolicy.requireAccountContext(name, null),
        throwsA(isA<BridgeAccountContextRequiredException>()),
      );
    }
  });

  test(
    'original receipt advances transport only; no fabricated account or finish',
    () async {
      final f = installationFixture();
      addTearDown(f.close);
      final port = BridgeOnlineInstallationAdapter(f.session);
      final observed = await port.install(3);
      expect(observed.online, true);
      expect(f.session.activeGeneration, 8);
      expect(f.requests, hasLength(1));
      expect(f.requests.single.accountContext, isNull);
      expect(f.requests.single.sessionGeneration, 7);
      expect(f.requests.single.payload, {'schemaVersion': 1, 'revision': 3});
      await port.read(3);
      expect(f.requests.last.sessionGeneration, 8);
      expect(f.requests.map((r) => r.name), [
        'onboarding.onlineInstallation.install',
        'onboarding.onlineInstallation.read',
      ]);
    },
  );

  test('running and completed local recovery are not online', () async {
    final f = installationFixture();
    addTearDown(f.close);
    final port = BridgeOnlineInstallationAdapter(f.session);
    for (final state in ['local', 'offline', 'recoveryRequired']) {
      f.payload = installationWire(state: state);
      final result = await port.read(3);
      expect(result.phase, OnlineInstallationPhase.completed);
      expect(result.online, false);
    }
    f.payload = installationWire(phase: 'running', state: 'switching');
    expect((await port.read(3)).online, false);
    expect(f.requests.every((r) => r.name.endsWith('.read')), true);
  });

  final malformed = <Map<String, Object?>>[
    {'schemaVersion': 2},
    {'schemaVersion': 1.0},
    {'revision': 3.0},
    {'revision': 4},
    {'phase': 'finished'},
    {'controlGeneration': 6},
    {'controlGeneration': 8.0},
    {'modeRevision': -1},
    {'modeRevision': 4.0},
    {'modeState': 'invented'},
    {'modeState': 'switching'},
    {'modeRevision': 3},
    {'accountReady': true},
    {'phase': 'idle', 'modeRevision': 4},
  ];
  for (var index = 0; index < malformed.length; index++) {
    test('malformed observation $index cannot advance transport', () async {
      final f = installationFixture();
      addTearDown(f.close);
      f.payload = {...installationWire(), ...malformed[index]};
      final port = BridgeOnlineInstallationAdapter(f.session);
      await expectLater(port.read(3), throwsFormatException);
      expect(f.session.activeGeneration, 7);
    });
  }
  for (final change in ['generation', 'capability', 'dispose']) {
    test('held receipt cannot cross $change replacement', () async {
      final f = installationFixture();
      addTearDown(f.close);
      final port = BridgeOnlineInstallationAdapter(f.session);
      final entered = Completer<BridgeEnvelope>();
      f.onRequest = (request) async {
        entered.complete(request);
      };
      final reading = port.read(3);
      final rejected = expectLater(
        reading,
        throwsA(anyOf(isA<StateError>(), isA<Exception>())),
      );
      final original = await entered.future;
      switch (change) {
        case 'generation':
          f.session.advanceGeneration(9);
        case 'capability':
          f.session.acceptHostCapabilities([]);
        case 'dispose':
          port.dispose();
      }
      await f.respond(original);
      await rejected;
      expect(f.session.activeGeneration, change == 'generation' ? 9 : 7);
    });
  }
  test('unsupported and invalid revisions never dispatch', () async {
    final f = OnlineBridgeFixture(capability: false);
    addTearDown(f.close);
    final port = BridgeOnlineInstallationAdapter(f.session);
    await expectLater(port.install(3), throwsStateError);
    f.session.acceptHostCapabilities([
      BridgeOnlineInstallationAdapter.capability,
    ]);
    await expectLater(port.read(-1), throwsStateError);
    port.dispose();
    await expectLater(port.read(3), throwsStateError);
    expect(f.requests, isEmpty);
  });
}
