import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets('global bell destination is a unified inbox, not room activity', (
    tester,
  ) async {
    final requests = ValueNotifier<OpenDestinationIntent?>(null);
    final composition = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    await tester.pumpWidget(
      StarBridgeApp(composition: composition, navigationRequests: requests),
    );
    await tester.pumpAndSettle();
    requests.value = const OpenDestinationIntent('/notifications');
    await tester.pumpAndSettle();
    expect(find.byType(NotificationInboxPage), findsOneWidget);
    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('未读'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    requests.dispose();
  });
  test('read categories and counts; opening does not write; failed mark does not clear unread', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities([
      'notificationInbox.read',
      'notificationInbox.markRead',
    ]);
    const owner = BridgeAccountContext(
      environment: 'test',
      authority: 'starbridge-relay-test',
      subject: 'test',
    );
    var posts = 0;
    var reads = 0;
    var now = DateTime.utc(2026, 1, 1);
    var signedOut = false;
    final subscription = pair.host.incoming.listen((r) {
      final write = r.name == 'notificationInbox.markRead';
      if (write) posts++;
      if (r.name == 'notificationInbox.read') reads++;
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: 1,
          accountContext: owner,
          status: 'ok',
          payload: r.name == 'account.getCurrent'
              ? {
                  'schemaVersion': 1,
                  'state': signedOut ? 'signedOut' : 'legacySignedIn',
                }
              : write
              ? {'schemaVersion': 1, 'confirmed': false}
              : {
                  'schemaVersion': 1,
                  'unreadCount': 2,
                  'items': [
                    for (final category in ['system', 'fleet'])
                      {
                        'reference': category == 'system' ? 'a' * 32 : 'b' * 32,
                        'category': category,
                        'priority': 'action_required',
                        'title': category,
                        'body': 'Test',
                        'createdAt': '2026-09-15T00:00:00Z',
                        'read': false,
                        'actionTarget': '',
                        'actionLabel': '',
                        'isAvailable': true,
                      },
                  ],
                },
        ),
      );
    });
    final c = NotificationInboxController(session, now: () => now);
    addTearDown(() async {
      c.dispose();
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
    expect(await c.refresh(), isTrue);
    expect(c.items.map((x) => x.category), ['system', 'fleet']);
    expect(c.unread.value, 2);
    expect(posts, 0);
    for (var i = 0; i < 10; i++) {
      expect(await c.refresh(reuseFresh: true), isTrue);
    }
    expect(reads, 1);
    expect(await c.refresh(), isTrue);
    expect(reads, 2);
    now = now.add(const Duration(seconds: 15));
    expect(await c.refresh(reuseFresh: true), isTrue);
    expect(reads, 3);
    expect(await c.markRead(c.items), isFalse);
    expect(posts, 1);
    expect(c.unread.value, 2);
    expect(c.error, 'write');
    expect(await c.refresh(reuseFresh: true), isTrue);
    expect(reads, 4, reason: 'errors must never be reused');
    final invalidated = Future<void>(() async {
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 1,
          sequence: 1,
          payload: const {},
        ),
      );
    });
    signedOut = true;
    await invalidated;
    for (var i = 0; i < 20 && c.error != 'signedOut'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.items, isEmpty);
    expect(c.unread.value, 0);
    expect(c.error, 'signedOut');
  });
}
