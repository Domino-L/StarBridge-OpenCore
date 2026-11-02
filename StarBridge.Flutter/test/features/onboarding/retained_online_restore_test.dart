import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/retained_online_restore.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'online_review_test_support.dart';
import 'retained_online_review_test.dart' show retainedWire, retainedReview;

void main() {
  for (final scenario in [
    'exited',
    'live',
    'lost',
    'local-origin',
    'sealed-live',
    'revision',
  ]) {
    test(
      'pending retained recovery requires Native exit receipt: $scenario',
      () async {
        final f = OnlineBridgeFixture(retainedProtocol: true);
        addTearDown(f.close);
        f.session.acceptHostCapabilities([
          BridgeOnlineReviewAdapter.retainedCapability,
          BridgeOnlineInstallationAdapter.capability,
        ]);
        var current = true;
        f.onRequest = (request) async {
          final value = switch (request.name.split('.').last) {
            'read' =>
              scenario == 'local-origin'
                  ? {
                      ...onlineWire(state: 'recoveryRequired'),
                      'schemaVersion': 2,
                      'retainsSession': false,
                    }
                  : scenario == 'sealed-live'
                  ? {
                      ...retainedWire(state: 'recoveryRequired'),
                      'identity': {
                        ...onlineWire(state: 'recoveryRequired')['identity']
                            as Map<String, Object?>,
                        'localHandle': 'Pilot-Example',
                      },
                    }
                  : retainedWire(state: 'recoveryRequired'),
            'cancel' =>
              scenario == 'live'
                  ? retainedWire(
                      mode: 'recoveryRequired',
                      state: 'recoveryRequired',
                    )
                  : retainedWire(
                      mode: 'offline',
                      state: 'notStarted',
                      revision: scenario == 'revision' ? 7 : 8,
                    ),
            'begin' => retainedWire(revision: 9),
            'resume' => {...retainedReview(), 'revision': 9},
            'confirm' => {...retainedReview(confirmed: true), 'revision': 9},
            _ => throw StateError('Unexpected recovery route'),
          };
          if (request.name.endsWith('.cancel') && scenario == 'lost') {
            current = false;
          }
          await f.respond(request, value: value);
        };
        expect(
          await restoreRetainedOnline(
            review: f.adapter,
            installation: BridgeOnlineInstallationAdapter(f.session),
            originalHandle: null,
            current: () => current,
          ),
          scenario == 'exited' ? 9 : null,
        );
        expect(
          f.requests.map((r) => r.name.split('.').last),
          switch (scenario) {
            'exited' => ['read', 'cancel', 'begin', 'resume', 'confirm'],
            'local-origin' || 'sealed-live' => ['read'],
            _ => ['read', 'cancel'],
          },
        );
        expect(f.requests.every((r) => r.accountContext == null), true);
      },
    );
  }
  for (final scenario in [
    'same',
    'expired',
    'mismatch',
    'changed',
    'local',
    'unknown',
    'lost',
  ]) {
    test('explicit retained restore uses Native receipts: $scenario', () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
        BridgeOnlineInstallationAdapter.capability,
      ]);
      var current = true;
      f.onRequest = (request) async {
        final value = switch (request.name.split('.').last) {
          'read' =>
            scenario == 'local'
                ? {
                    ...onlineWire(mode: 'local', state: 'notStarted'),
                    'schemaVersion': 2,
                    'retainsSession': false,
                  }
                : retainedWire(mode: 'offline', state: 'notStarted'),
          'begin' => retainedWire(),
          'resume' =>
            scenario == 'expired'
                ? retainedWire(state: 'sessionExpired')
                : scenario == 'mismatch'
                ? retainedWire(state: 'mismatch')
                : retainedReview(),
          'confirm' => retainedReview(confirmed: true),
          _ => throw StateError('Unexpected route'),
        };
        if (request.name.endsWith('.resume')) {
          if (scenario == 'lost') current = false;
          if (scenario == 'changed') f.session.advanceGeneration(8);
        }
        await f.respond(request, value: value);
      };
      Future<int?> restore() => restoreRetainedOnline(
        review: f.adapter,
        installation: BridgeOnlineInstallationAdapter(f.session),
        originalHandle: scenario == 'unknown' ? null : 'Pilot-Example',
        current: () => current,
      );
      if (scenario == 'changed') {
        await expectLater(
          restore(),
          throwsA(isA<BridgeStaleGenerationException>()),
        );
      } else {
        expect(
          await restore(),
          ['same', 'unknown'].contains(scenario) ? 7 : null,
        );
      }
      expect(
        f.requests.any(
          (r) => r.name.endsWith('.login') || r.name.endsWith('.reauthorize'),
        ),
        false,
      );
      expect(
        f.requests.where((r) => r.name.endsWith('.confirm')).length,
        ['same', 'unknown'].contains(scenario) ? 1 : 0,
      );
      expect(f.requests.every((r) => r.accountContext == null), true);
      if (scenario == 'same') {
        expect(f.requests.map((r) => r.name.split('.').last), [
          'read',
          'begin',
          'resume',
          'confirm',
        ]);
        expect(
          f.requests.last.payload['confirmationKey'],
          '11111111111111111111111111111111',
        );
      }
    });
  }
  test('another Handle is not automatically confirmed', () async {
    final f = OnlineBridgeFixture(retainedProtocol: true);
    addTearDown(f.close);
    f.onRequest = (request) => f.respond(
      request,
      value: request.name.endsWith('.read')
          ? retainedWire(mode: 'offline', state: 'notStarted')
          : request.name.endsWith('.begin')
          ? retainedWire()
          : retainedReview(),
    );
    expect(
      await restoreRetainedOnline(
        review: f.adapter,
        installation: BridgeOnlineInstallationAdapter(f.session),
        originalHandle: 'Different-Pilot',
        current: () => true,
      ),
      null,
    );
    expect(f.requests.any((r) => r.name.endsWith('.confirm')), false);
  });
}
