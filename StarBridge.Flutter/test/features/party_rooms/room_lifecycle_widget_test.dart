import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

Future<AppComposition> openExampleRooms(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forShellReview(
    windowChrome: InMemoryWindowChrome(),
  );
  await tester.pumpWidget(StarBridgeApp(composition: composition));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('/rooms')));
  await tester.pumpAndSettle();
  return composition;
}

void main() {
  testWidgets('example create validates then enters and confirms leaving', (
    tester,
  ) async {
    final composition = await openExampleRooms(tester);
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    expect(find.text('名称需要 2–32 个字符。'), findsOneWidget);
    expect(composition.partyRooms.directory!.currentRoomId, isNull);
    await tester.enterText(
      find.byKey(const Key('room-create-title')),
      '验收测试房间',
    );
    await tester.enterText(
      find.byKey(const Key('room-create-goal')),
      '确认创建与退出流程',
    );
    final tags = find.byKey(const Key('room-choose-tags'));
    await tester.ensureVisible(tags);
    await tester.tap(tags);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-catalog-search')), '不知道玩啥');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-tag-undecided')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-tags-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(composition.partyRooms.directory!.currentRoomId, 'example-created');
    expect(composition.partyRooms.selectedRoom!.title, '验收测试房间');
    expect(composition.partyRooms.selectedRoom!.admissionMode, 'direct');
    expect(composition.partyRooms.selectedRoom!.tags.single.id, 'undecided');
    await tester.tap(find.widgetWithText(OutlinedButton, '退出房间'));
    await tester.pumpAndSettle();
    expect(find.textContaining('自动移交房主'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(composition.partyRooms.directory!.currentRoomId, 'example-created');
    await tester.tap(find.widgetWithText(OutlinedButton, '退出房间'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出房间'));
    await tester.pumpAndSettle();
    expect(composition.partyRooms.directory!.currentRoomId, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'room code resolve requires confirmation and approval remains pending',
    (tester) async {
      final composition = await openExampleRooms(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '输入房间码'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '查找房间'));
      await tester.pumpAndSettle();
      expect(find.text('请输入房间码。'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'DEMO1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '查找房间'));
      await tester.pumpAndSettle();
      expect(composition.partyRooms.directory!.currentRoomId, isNull);
      expect(find.textContaining('需要房主批准。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '申请加入'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(composition.partyRooms.directory!.currentRoomId, isNull);
      expect(find.text('申请已提交，等待房主批准。'), findsOneWidget);
      final join = find.descendant(
        of: find.byKey(const Key('room-example-exploration')),
        matching: find.widgetWithText(OutlinedButton, '加入房间'),
      );
      await tester.ensureVisible(join);
      await tester.pumpAndSettle();
      expect(join.hitTestable(), findsOneWidget);
      await tester.tap(join);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '加入房间'));
      await tester.pumpAndSettle();
      expect(
        composition.partyRooms.directory!.currentRoomId,
        'example-exploration',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
