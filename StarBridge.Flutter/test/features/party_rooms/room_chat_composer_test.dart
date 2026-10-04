import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_composer.dart';
import '../friends/social_layout_test.dart' show app, size;

void main() {
  for (final width in [320.0, 500.0, 700.0]) {
    testWidgets('shared room composer fits $width and submits once', (tester) async {
      size(tester, Size(width, 400));
      final text = TextEditingController(text: 'test');
      var sends = 0;
      await tester.pumpWidget(app(RoomChatComposer(
        controller: text, onChanged: (_) {}, onSend: () => sends++,
        leadingAction: TextButton(onPressed: () {}, child: const Text('分享浮层预设')),
        attachment: const Text('预设附件草稿'),
      )));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, 300);
      expect(field.minLines, 1);
      expect(field.maxLines, 3);
      expect(field.decoration!.helperText, isNotEmpty);
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sends, 1);
      expect(find.text('分享浮层预设'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      text.dispose();
    });
  }
}
