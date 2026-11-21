import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitation_card.dart';

import '../../support/standard_interaction.dart';
import 'room_lifecycle_widget_test.dart' show openExampleRooms;

// 0.7.3 default is scan (user: "把所有人的交互都换成扫描"): the key room flows
// work there too. Buttons are found by their label and checked through
// semantics, never by widget type.
void main() {
  testWidgets('scan: room code lookup asks, validates and requests to join', (
    tester,
  ) async {
    final composition = await openExampleRooms(
      tester,
      interaction: InteractionStyle.scan,
    );
    final enterCode = find.text('输入房间码');
    expectScanSuite(tester, enterCode);
    expectButtonState(tester, enterCode, enabled: true);
    await tester.tap(enterCode);
    await tester.pumpAndSettle();
    final lookUp = find.text('查找房间');
    expectButtonState(tester, lookUp, enabled: true);
    await tester.tap(lookUp);
    await tester.pumpAndSettle();
    expect(find.text('请输入房间码。'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'DEMO1234',
    );
    await tester.tap(find.text('查找房间'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要房主批准。'), findsOneWidget);
    // The dialog title repeats the label; the action is the last one.
    final request = find.text('申请加入').last;
    expectButtonState(tester, request, enabled: true);
    await tester.tap(request);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(composition.partyRooms.directory!.currentRoomId, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scan: invitation joins; host invites and revokes', (
    tester,
  ) async {
    final composition = await openExampleRooms(
      tester,
      interaction: InteractionStyle.scan,
    );
    final module = composition.partyRooms;
    await tester.tap(find.text('房间邀请 · 1'));
    await tester.pumpAndSettle();
    final card = find.byType(RoomInvitationCard);
    expect(card, findsOneWidget);
    final join = find.descendant(of: card, matching: find.text('加入房间'));
    expectScanSuite(tester, join);
    expectButtonState(tester, join, enabled: true);
    expectButtonState(
      tester,
      find.descendant(of: card, matching: find.text('拒绝')),
      enabled: true,
    );
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(module.directory!.currentRoomId, isNull, reason: 'asks first');
    await tester.tap(find.text('加入房间').last);
    await tester.pumpAndSettle();
    expect(module.directory!.currentRoomId, 'example-cargo');
    await module.selectPreviewScene('host');
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请好友'));
    await tester.pumpAndSettle();
    final invite = find.text('邀请');
    expectButtonState(tester, invite, enabled: true);
    await tester.tap(invite);
    await tester.pumpAndSettle();
    expect(module.directory!.sentInvitations, hasLength(1));
    final revoke = find.text('撤回');
    await tester.ensureVisible(revoke);
    expectButtonState(tester, revoke, enabled: true);
    await tester.tap(revoke);
    await tester.pumpAndSettle();
    expect(module.directory!.sentInvitations, isEmpty);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
