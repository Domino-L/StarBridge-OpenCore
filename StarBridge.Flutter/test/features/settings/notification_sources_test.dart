import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'local_privacy_page_test.dart' show app, viewport;

Map<String, Object?> data() => {
  'schemaVersion': 1,
  'revision': 0,
  'roomMode': 'normal',
  'friendMode': 'normal',
  'directMessageMode': 'normal',
  'sources': <Object>[],
};

class Fake implements NotificationSourcesPort {
  final changes = StreamController<void>.broadcast();
  var value = BridgeNotificationSources.parse(data());
  int writes = 0, reads = 0;
  bool fail = false;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<NotificationSourcesValue> read() async {
    reads++;
    return value;
  }

  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) async {
    writes++;
    if (fail) throw StateError('unconfirmed');
    return value = NotificationSourcesValue(original.revision + 1, [
      for (final source in original.sources)
        source.copyWith(mode: modes[source.sourceRef]),
    ]);
  }

  @override
  void dispose() {
    changes.close();
  }
}

void main() {
  testWidgets(
    'narrow source dropdown discards without a write or stale visual value',
    (tester) async {
      viewport(tester, const Size(390, 1000));
      final port = Fake();
      await tester.pumpWidget(
        app(
          NotificationEditorFrame(
            owner: Object(),
            child: SingleChildScrollView(
              child: NotificationSourcesConnectedPanel(port: port),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find
          .byType(DropdownButtonFormField<NotificationSourceMode>)
          .first;
      tester
          .widget<DropdownButtonFormField<NotificationSourceMode>>(selector)
          .onChanged!(NotificationSourceMode.doNotDisturb);
      await tester.pumpAndSettle();
      expect(port.writes, 0);
      await tester.tap(find.byKey(const Key('notification-discard')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<NotificationSourceMode>>(selector)
            .initialValue,
        NotificationSourceMode.normal,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      port.dispose();
    },
  );
  test('missing and unknown modes cannot silently become normal', () {
    for (final field in ['roomMode', 'friendMode', 'directMessageMode']) {
      expect(
        () => BridgeNotificationSources.parse(data()..remove(field)),
        throwsA(isA<BridgeFormatException>()),
      );
      expect(
        () => BridgeNotificationSources.parse(data()..[field] = 'future'),
        throwsA(isA<BridgeFormatException>()),
      );
    }
    final source = {
      'sourceRef': 'organization:${'a' * 64}',
      'kind': 'community',
      'displayName': 'Organization',
      'mode': 'normal',
    };
    expect(
      () => BridgeNotificationSources.parse(
        data()..['sources'] = [source, source],
      ),
      throwsA(isA<BridgeFormatException>()),
    );
  });
  test(
    'uncertain retry reuses operation and old lease cannot write twice',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'account.getCurrent',
        'notificationPolicies.read',
        'notificationPolicies.save',
      ]);
      const owner = BridgeAccountContext(
        environment: 'fixture',
        authority: 'fixture',
        subject: 'owner',
      );
      final requests = <BridgeEnvelope>[];
      var fail = true;
      final sub = pair.host.incoming.listen((r) {
        final saving = r.name.endsWith('.save');
        if (saving) requests.add(r);
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            correlationId: r.correlationId,
            sessionGeneration: 1,
            accountContext: owner,
            status: saving && fail ? 'error' : 'ok',
            error: saving && fail
                ? const BridgeErrorBody(
                    code: 'unconfirmed',
                    message: 'unconfirmed',
                    retryable: true,
                  )
                : null,
            payload: r.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'signedIn'}
                : {
                    ...data(),
                    if (saving) ...{
                      'revision': 1,
                      'operationId': r.payload['operationId'],
                      'roomMode': 'doNotDisturb',
                    },
                  },
          ),
        );
      });
      final port = BridgeNotificationSources(session);
      final notifications = BridgeNotificationSettingsAdapter(session);
      final clears = <Object?>[];
      final clearSubscription = notifications.reminders.listen(clears.add);
      final saved = await port.read();
      expect(clears, isEmpty);
      final next = {
        ...saved.modes,
        'room': NotificationSourceMode.doNotDisturb,
      };
      await expectLater(
        port.save(saved, next),
        throwsA(isA<BridgeClientException>()),
      );
      fail = false;
      expect(
        (await port.save(saved, next)).modes['room'],
        NotificationSourceMode.doNotDisturb,
      );
      expect(
        requests[0].payload['operationId'],
        requests[1].payload['operationId'],
      );
      await expectLater(
        port.save(saved, next),
        throwsA(isA<BridgeClientException>()),
      );
      expect(requests.length, 2);
      final lease = await port.read();
      session.advanceGeneration(2);
      await expectLater(
        port.save(lease, lease.modes),
        throwsA(isA<BridgeClientException>()),
      );
      expect(requests.length, 2);
      port.dispose();
      expect(clears.length, greaterThanOrEqualTo(2));
      await clearSubscription.cancel();
      await notifications.close();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  testWidgets('source changes share footer save, retain failure and discard', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final port = Fake();
    await tester.pumpWidget(
      app(
        NotificationEditorFrame(
          owner: Object(),
          child: SingleChildScrollView(
            child: NotificationSourcesConnectedPanel(port: port),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void change(NotificationSourceMode mode) => tester
        .widget<SegmentedButton<NotificationSourceMode>>(
          find.byKey(const Key('notification-source-mode-room')),
        )
        .onSelectionChanged!({mode});
    change(NotificationSourceMode.doNotDisturb);
    await tester.pumpAndSettle();
    expect(port.writes, 0);
    port.fail = true;
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(port.writes, 1);
    expect(
      tester
          .widget<SegmentedButton<NotificationSourceMode>>(
            find.byKey(const Key('notification-source-mode-room')),
          )
          .onSelectionChanged,
      isNull,
    );
    port.fail = false;
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(port.writes, 2);
    expect(port.value.modes['room'], NotificationSourceMode.doNotDisturb);
    change(NotificationSourceMode.normal);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-discard')));
    await tester.pumpAndSettle();
    expect(port.writes, 2);
    expect(
      tester
          .widget<SegmentedButton<NotificationSourceMode>>(
            find.byKey(const Key('notification-source-mode-room')),
          )
          .selected,
      {NotificationSourceMode.doNotDisturb},
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    port.dispose();
  });
}
