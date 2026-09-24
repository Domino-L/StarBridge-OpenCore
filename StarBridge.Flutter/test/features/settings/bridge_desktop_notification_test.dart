import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';

void main() {
  test(
    'desktop diagnostics reject unknown native text and stale activations',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      session.acceptHostCapabilities([
        'notificationSettings.testDesktop',
        'notificationSettings.consumeActivation',
      ]);
      var reason = 'doNotDisturb';
      final requests = <BridgeEnvelope>[];
      final sub = pair.host.incoming.listen((request) {
        requests.add(request);
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
              'submitted': false,
              'reason': reason,
              'destination': 'roomReminders',
            },
          ),
        );
      });
      final port = BridgeDesktopNotificationPort(session);
      expect((await port.testDesktop()).reason, 'doNotDisturb');
      reason = 'private error with a path';
      expect((await port.testDesktop()).reason, 'unavailable');
      expect(
        await port.consume(DesktopReminderActivation('a' * 32, 3)),
        isTrue,
      );
      final count = requests.length;
      session.advanceGeneration(4);
      expect(
        await port.consume(DesktopReminderActivation('a' * 32, 3)),
        isFalse,
      );
      expect(requests.length, count);
      await sub.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  test(
    'native output sends only Host tickets, never display text or account',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      session.acceptHostCapabilities([
        'notificationSettings.presentDesktop',
        'notificationSettings.testDesktop',
        'notificationSettings.clearDesktop',
      ]);
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 3,
            status: 'ok',
            payload: {'schemaVersion': 1, 'submitted': true},
          ),
        );
      });
      final port = BridgeDesktopNotificationPort(session);
      expect(await port.show('ignored', 'not sent'), isFalse);
      expect(requests, isEmpty);
      expect(await port.show('ignored', 'not sent', test: true), isTrue);
      expect(requests.last.payload, {'schemaVersion': 1});
      expect(requests.last.accountContext, isNull);
      final ticket = 'a' * 32;
      expect(await port.show('ignored', 'not sent', ticket: ticket), isTrue);
      expect(requests.last.payload, {'schemaVersion': 1, 'ticket': ticket});
      await port.clear();
      expect(requests.last.name, 'notificationSettings.clearDesktop');
      session.acceptHostCapabilities([]);
      expect(await port.show('', '', test: true), isFalse);
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    },
  );

  test(
    'reminder ticket survives projection; malformed ticket is rejected',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      final adapter = BridgeNotificationSettingsAdapter(session);
      final seen = <LocalRoomReminder?>[];
      final sub = adapter.reminders.listen(seen.add);
      final data = {
        'schemaVersion': 1,
        'revision': 0,
        'invitations': 1,
        'applications': 0,
        'desktopEligible': true,
        'desktopTicket': 'a' * 32,
      };
      adapter.onRoomReminder(data);
      expect(seen.single!.desktopTicket, 'a' * 32);
      adapter.onRoomReminder({...data, 'desktopTicket': '../invalid'});
      expect(seen, hasLength(1));
      await sub.cancel();
      await adapter.close();
      await session.close();
      await pair.host.close();
    },
  );
}
