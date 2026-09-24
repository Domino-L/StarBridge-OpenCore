import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_composer.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';

import '../friends/social_layout_test.dart' show app;
import '../party_rooms/room_chat_test.dart' as room;
import 'direct_message_send_test.dart' as direct;

void main() {
  for (final privateChat in [true, false]) {
    testWidgets(
      '${privateChat ? 'private' : 'room'} IME, Shift+Enter and pending-send protection',
      (tester) async {
        late Widget child;
        late int Function() writes;
        late VoidCallback dispose;
        if (privateChat) {
          final port = direct.Sender();
          final module = await direct.opened(port);
          child = ListenableBuilder(
            listenable: module,
            builder: (_, _) => DirectMessageComposer(module),
          );
          writes = () => port.writes.length;
          dispose = module.dispose;
        } else {
          final port = room.ChatPort()
            ..sending = () => Completer<RoomChatMessage>().future;
          final module = RoomChatModule(port)..setRoom('one');
          await tester.pump();
          child = RoomChatPanel(module: module);
          writes = () => port.sends;
          dispose = module.dispose;
        }
        await tester.pumpWidget(app(child));
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: privateChat
              ? find.byType(TextFormField)
              : find.byKey(const Key('room-chat-draft')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(field, '中文');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '中文',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(writes(), 0, reason: 'IME candidate confirmation is not a send');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '中文',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          handled,
          isFalse,
          reason: 'Shift+Enter stays available to native multiline input',
        );
        expect(writes(), 0);
        // Windows text input supplies the newline after the unhandled key.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '中文\n第二行',
            selection: TextSelection.collapsed(offset: 6),
          ),
        );
        await tester.pump();
        expect(tester.widget<EditableText>(field).controller.text, '中文\n第二行');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(writes(), 1, reason: 'No held-key or pending duplicate send');
        await tester.pumpWidget(const SizedBox());
        dispose();
      },
    );
  }
}
