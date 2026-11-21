import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';

void main() {
  test(
    'announcement click accepts only the current Host page reference',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      session.acceptHostCapabilities([
        'notificationSettings.consumeActivation',
      ]);
      String? destination = 'communityAnnouncements';
      Object? ref = 'a' * 32;
      var calls = 0;
      final sub = pair.host.incoming.listen((request) {
        calls++;
        expect(request.accountContext, isNull);
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 3,
            status: 'ok',
            payload: {
              'schemaVersion': 1,
              'destination': destination,
              'ref': ref,
            },
          ),
        );
      });
      final port = BridgeDesktopNotificationPort(session);
      addTearDown(() async {
        await sub.cancel();
        await session.close();
        await pair.host.close();
      });
      final activation = DesktopReminderActivation('b' * 32, 3);
      expect(await port.consumeTarget(activation), (
        destination: 'communityAnnouncements',
        ref: 'a' * 32,
      ));
      for (final invalid in [
        null,
        '',
        'announcementRef',
        'a' * 64,
        'officialFleet:7',
      ]) {
        ref = invalid;
        expect(await port.consumeTarget(activation), isNull);
      }
      destination = 'officialFleetAnnouncements';
      ref = 'officialFleet:7';
      expect(await port.consumeTarget(activation), (
        destination: 'officialFleetAnnouncements',
        ref: 'officialFleet:7',
      ));
      ref = 'officialFleet:0';
      expect(await port.consumeTarget(activation), isNull);
      destination = null;
      expect(await port.consumeTarget(activation), isNull);
      final before = calls;
      session.advanceGeneration(4);
      expect(await port.consumeTarget(activation), isNull);
      expect(calls, before);
    },
  );
}
