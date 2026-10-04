import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_transfer.dart';
import 'package:starbridge_flutter/features/party_rooms/room_members_panel.dart';

import 'party_rooms_test.dart' show wire, ready;
import 'room_management_test.dart' show ManagementPort;
import 'room_member_removal_test.dart' show removalRoom;
import '../friends/social_layout_test.dart' show app, loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final supported in [false, true]) {
    testWidgets(
      'transfer menu follows explicit service capability $supported',
      (tester) async {
        final port = ManagementPort()
          ..result = ready(
            wire(current: 'a', rooms: [removalRoom()])
              ..['supportsHostTransfer'] = supported,
          );
        final module = PartyRoomsModule(port);
        await module.refresh();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => RoomMembersPanel(
                room: module.selectedRoom!,
                serverTime: module.directory!.serverTime,
                onRemove: (_) {},
                onTransfer: module.canTransferHost
                    ? (member) => transferRoomHost(context, module, member)
                    : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(RoomMemberMenu),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is StandardIcon &&
                  widget.semantic == StandardIconSemantic.moreHoriz,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('移出房间'), findsNothing);
        await tester.tap(find.byType(RoomMemberMenu));
        await tester.pumpAndSettle();
        expect(find.text('转移房主'), supported ? findsOneWidget : findsNothing);
        if (supported) {
          await tester.tap(find.text('转移房主'));
          await tester.pumpAndSettle();
          expect(find.textContaining('合成成员'), findsWidgets);
          expect(find.textContaining('待处理邀请将失效'), findsOneWidget);
          expect(port.calls, 0);
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          expect(port.calls, 0);
          await tester.tap(find.byType(RoomMemberMenu));
          await tester.pumpAndSettle();
          await tester.tap(find.text('转移房主'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '转移房主'));
          await tester.pump();
          expect(port.calls, 1);
          port.pendingCommand.complete(const RoomCommandResult('transferred'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        module.dispose();
      },
    );
  }
  testWidgets(
    'host loss while transfer confirmation is open prevents execution',
    (tester) async {
      final port = ManagementPort()
        ..result = ready(
          wire(current: 'a', rooms: [removalRoom()])
            ..['supportsHostTransfer'] = true,
        );
      final module = PartyRoomsModule(port);
      await module.refresh();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => transferRoomHost(
                context,
                module,
                module.selectedRoom!.members.last,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      port.result = ready(
        wire(current: 'a', rooms: [removalRoom(host: false)])
          ..['supportsHostTransfer'] = true,
      );
      await module.refresh();
      await tester.tap(find.widgetWithText(FilledButton, '转移房主'));
      await tester.pumpAndSettle();
      expect(port.calls, 0);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
}
