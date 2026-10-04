import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/app/routing/room_invitation_destination.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitation_dialog.dart';

import 'party_rooms_test.dart' show room, wire, ready;
import 'room_management_test.dart' show InvitationPort;
import '../friends/social_layout_test.dart' show app;

void main() {
  test(
    'room invitation navigation rejects unrelated or ambiguous destinations',
    () {
      for (final route in [
        '/rooms/invitations',
        '/rooms/invitations?invitation=synthetic-invite',
      ]) {
        expect(isRoomInvitationDestination(route), isTrue);
      }
      for (final route in [
        '/rooms',
        'https://other.test/rooms/invitations',
        '//other.test/rooms/invitations',
        '/rooms/invitations?invitation=short',
        '/rooms/invitations?invitation=synthetic-invite&account=private',
        '/rooms/invitations?invitation=synthetic-invite&invitation=another-invite',
        '/rooms/invitations#extra',
      ]) {
        expect(isRoomInvitationDestination(route), isFalse, reason: route);
      }
    },
  );

  for (final scenario in ['current', 'expired', 'missing', 'joined']) {
    testWidgets(
      'targeted invitation $scenario is view-only until explicit confirmation',
      (tester) async {
        Map<String, Object?> invite(String id, String title) => {
          'invitationId': id,
          'roomId': 'a',
          'roomTitle': title,
          'inviterCallsign': '合成房主',
          'inviterGameId': '',
          'recipientCallsign': '合成成员',
          'recipientGameId': '',
          'expiresAt': DateTime.now()
              .add(Duration(days: scenario == 'expired' ? -1 : 1))
              .toIso8601String(),
        };
        final data =
            wire(current: scenario == 'joined' ? 'a' : null, rooms: [room('a')])
              ..['receivedInvitations'] = [
                if (scenario != 'missing') invite('synthetic-invite', '目标邀请'),
                invite('unrelated-invite', '其他邀请'),
              ];
        final port = InvitationPort()..result = ready(data);
        final module = PartyRoomsModule(port);
        await module.refresh();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomInvitations(
                  context,
                  module,
                  invitationId: 'synthetic-invite',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('invitation-card-unrelated-invite')),
          findsNothing,
        );
        expect(port.calls, 0);
        if (scenario == 'missing') {
          expect(find.textContaining('邀请已失效或已处理'), findsOneWidget);
          expect(find.widgetWithText(FilledButton, '加入房间'), findsNothing);
        } else {
          expect(
            find.byKey(const ValueKey('invitation-card-synthetic-invite')),
            findsOneWidget,
          );
          expect(find.text('测试房间 a'), findsOneWidget);
          final join = find.widgetWithText(FilledButton, '加入房间');
          expect(
            tester.widget<FilledButton>(join).onPressed != null,
            scenario == 'current',
          );
          if (scenario == 'current') {
            await tester.tap(join);
            await tester.pumpAndSettle();
            expect(port.calls, 0);
            await tester.tap(find.widgetWithText(TextButton, '取消'));
            await tester.pumpAndSettle();
          } else {
            expect(
              find.text(scenario == 'expired' ? '邀请已过期。' : '你已在此房间中。'),
              findsOneWidget,
            );
          }
        }
        expect(port.calls, 0);
        await tester.pumpWidget(const SizedBox());
        module.dispose();
      },
    );
  }
}
