import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/party_rooms/room_feedback.dart';

import 'room_lifecycle_widget_test.dart' show openExampleRooms;

void main() {
  test('room feedback separates completion, uncertainty and failure', () {
    for (final code in [
      'joined',
      'left',
      'closed',
      'updated',
      'approved',
      'declined',
      'invited',
      'revoked',
    ]) {
      expect(roomFeedbackTone(code), ActionTone.success);
    }
    for (final code in [
      'outcomeUnknown',
      'refreshRequired',
      'contextChanged',
      'presetImportUnknown',
    ]) {
      expect(roomFeedbackTone(code), ActionTone.warning);
    }
    expect(roomFeedbackTone('unavailable'), ActionTone.danger);
    expect(roomFeedbackTone('pending'), ActionTone.info);
  });

  testWidgets(
    'room actions expose semantic colors without bypassing confirmation',
    (tester) async {
      final composition = await openExampleRooms(tester);
      await composition.partyRooms.selectPreviewScene('host');
      await tester.pumpAndSettle();
      final disband = find.widgetWithText(OutlinedButton, '解散房间');
      final colors = tester.element(disband).tokens.colors;
      expect(
        tester
            .widget<OutlinedButton>(disband)
            .style!
            .foregroundColor!
            .resolve({}),
        colors.danger,
      );
      final applications = find.widgetWithText(OutlinedButton, '加入申请 · 2');
      expect(
        tester
            .widget<OutlinedButton>(applications)
            .style!
            .foregroundColor!
            .resolve({}),
        colors.info,
      );
      final invitations = find.widgetWithText(OutlinedButton, '房间邀请 · 1');
      final leave = find.widgetWithText(OutlinedButton, '退出房间');
      expect(
        tester
            .widget<OutlinedButton>(invitations)
            .style!
            .foregroundColor!
            .resolve({}),
        colors.info,
      );
      expect(
        tester
            .widget<OutlinedButton>(leave)
            .style!
            .foregroundColor!
            .resolve({}),
        colors.warning,
      );
      expect(colors.info, isNot(colors.warning));
      await tester.tap(applications);
      await tester.pumpAndSettle();
      final approve = find
          .byWidgetPredicate(
            (widget) =>
                widget is FilledButton &&
                widget.key.toString().contains('approve-'),
          )
          .first;
      final decline = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextButton &&
                widget.key.toString().contains('decline-'),
          )
          .first;
      expect(
        tester
            .widget<FilledButton>(approve)
            .style!
            .backgroundColor!
            .resolve({}),
        colors.success,
      );
      expect(
        tester.widget<TextButton>(decline).style!.foregroundColor!.resolve({}),
        colors.danger,
      );
      Navigator.of(tester.element(approve)).pop();
      await tester.pumpAndSettle();
      final roomId = composition.partyRooms.directory!.currentRoomId;
      await tester.tap(disband);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, '解散房间');
      expect(
        tester
            .widget<FilledButton>(confirm)
            .style!
            .backgroundColor!
            .resolve({}),
        colors.danger,
      );
      expect(composition.partyRooms.directory!.currentRoomId, roomId);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(composition.partyRooms.directory!.currentRoomId, roomId);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
