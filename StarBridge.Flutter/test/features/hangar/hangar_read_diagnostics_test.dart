import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/hangar_read_diagnostics.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'bridge_local_hangar_test.dart' show LocalConnection;

void main() {
  tearDown(HangarReadDiagnostics.clear);

  test('diagnostics are disabled in ordinary builds', () {
    expect(HangarReadDiagnostics.enabled, isFalse);
  });

  test('failure classification never includes arbitrary error content', () {
    final report = HangarReadDiagnostics.formatFailure(
      HangarReadStage.inventory,
      const LocalHangarFailure('private-account-and-token'),
      DateTime.utc(2026, 9, 25),
    );
    expect(report, contains('inventory'));
    expect(report, contains('unclassified'));
    expect(report, isNot(contains('private-account')));
    expect(report, contains('2026-09-25T00:00:00.000Z'));
    expect(
      HangarReadDiagnostics.formatFailure(
        HangarReadStage.bind,
        StateError('private-account-and-token'),
        DateTime.utc(2026),
      ),
      isNot(contains('private-account')),
    );
  });

  test('bounded capture preserves the original exception', () async {
    const failure = LocalHangarFailure('hangar.account_changed');
    for (var i = 0; i < 20; i++) {
      await expectLater(
        HangarReadDiagnostics.capture(
          HangarReadStage.bind,
          () async => throw failure,
          enabled: true,
        ),
        throwsA(same(failure)),
      );
    }
    expect(HangarReadDiagnostics.entries, hasLength(8));
    expect(
      HangarReadDiagnostics.entries.last,
      contains('hangar.account_changed'),
    );
  });

  test('disabled capture emits nothing even on failure', () async {
    await expectLater(
      HangarReadDiagnostics.capture(
        HangarReadStage.bind,
        () async => throw const LocalHangarFailure('hangar.account_changed'),
      ),
      throwsA(isA<LocalHangarFailure>()),
    );
    expect(HangarReadDiagnostics.entries, isEmpty);
  });

  test(
    'optional legacy display absence emits no read failure diagnostics',
    () async {
      final connection = LocalConnection()
        ..legacy = true
        ..emptyRevision = 0
        ..profileHasHangar = false;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      final snapshot = await BridgeLocalHangar(
        session,
        diagnosticCapture: true,
      ).read();
      expect(snapshot.revision, 0);
      expect(snapshot.fromLegacyProfile, isFalse);
      expect(HangarReadDiagnostics.entries, isEmpty);
      expect(connection.requests.map((r) => r.name), [
        'account.getCurrent',
        'hangarReader.inventory',
        'personalProfile.getSelf',
      ]);
    },
  );

  test(
    'malformed legacy display still identifies the failing projection',
    () async {
      final connection = LocalConnection()
        ..legacy = true
        ..emptyRevision = 0
        ..profilePayload = {
          'schemaVersion': 1,
          'profile': {
            'hangar': {'ships': 'malformed'},
          },
        };
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeLocalHangar(session, diagnosticCapture: true).read(),
        throwsA(isA<LocalHangarFailure>()),
      );
      expect(
        HangarReadDiagnostics.entries.single,
        contains('legacyProjection localHangar hangar.legacy_unavailable'),
      );
      expect(connection.requests.map((r) => r.name), [
        'account.getCurrent',
        'hangarReader.inventory',
        'personalProfile.getSelf',
      ]);
    },
  );
}
