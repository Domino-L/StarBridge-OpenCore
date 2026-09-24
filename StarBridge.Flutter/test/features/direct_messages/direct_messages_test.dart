import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_avatar.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import '../friends/friends_test.dart' as fixtures;

class Pending implements DirectMessagesPort {
  final events = StreamController<void>.broadcast();
  final reads = <Completer<DirectPage>>[];
  final cursors = <(String, int, int)>[];
  Completer<List<Conversation>>? directoryReply;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() =>
      directoryReply?.future ?? ExampleDirectMessages().directory();
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) {
    cursors.add((ref, before, after));
    final reply = Completer<DirectPage>();
    reads.add(reply);
    return reply.future;
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

Widget app(Locale locale, DirectMessagesPort Function() factory) {
  final base = fixtures.page(locale, UnavailableFriendsPort.new) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    theme: base.theme,
    home: Scaffold(
      body: DirectMessagesPage(createPort: factory, onBack: () {}),
    ),
  );
}

void main() {
  test('opening friend supersedes background refresh without restoring a late list', () async {
    final port = Pending();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final friend = module.rows.first;
    port.directoryReply = Completer<List<Conversation>>();
    final refresh = module.refresh(retainDirectory: true);
    expect(module.rows.first.unread, 2);
    final opening = module.openFriend(friend);
    port.reads.single.complete(
      await ExampleDirectMessages().history(friend.ref),
    );
    await opening;
    port.directoryReply!.complete(const []);
    await refresh;
    expect(module.selected, friend);
    expect(module.messages, isNotEmpty);
    expect(module.rows, [friend]);
  });
  testWidgets('avatars render inline pixels and reject untrusted peer URLs', (
    tester,
  ) async {
    final source = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xff258080), BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = await picture.toImage(8, 8);
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final value =
          'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}';
      bitmap.dispose();
      picture.dispose();
      return value;
    });
    final base =
        app(const Locale('zh', 'CN'), ExampleDirectMessages.new) as MaterialApp;
    await tester.pumpWidget(
      MaterialApp(
        theme: base.theme,
        locale: base.locale,
        supportedLocales: base.supportedLocales,
        localizationsDelegates: base.localizationsDelegates,
        home: Scaffold(
          body: Row(
            children: [
              ChatAvatar(label: '有头像', source: source),
              const ChatAvatar(
                label: '不可信链接',
                source: 'https://untrusted.example/avatar',
              ),
              const ChatAvatar(
                label: '损坏头像',
                source: 'data:image/png;base64,%%%',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('initial history, before cursor, incremental cursor and unread stay authoritative', () async {
    final module = DirectMessagesModule(ExampleDirectMessages());
    addTearDown(module.dispose);
    await module.refresh();
    expect(module.rows, hasLength(2));
    expect(module.visible, hasLength(1));
    await module.open(module.visible.single);
    expect(module.messages, hasLength(50));
    expect(module.messages.first.sequence, 11);
    expect(module.hasOlder, isTrue);
    await module.load(older: true);
    expect(module.messages, hasLength(60));
    expect(module.hasOlder, isFalse);
    await module.load(newer: true);
    expect(module.messages, hasLength(60));
    expect(module.rows.first.unread, 2);
    module.group(true);
    expect(module.visible.single.state, 'request_incoming');
    expect(module.messages, isEmpty);
  });
  test('changing target or account never restores delayed history', () async {
    final port = Pending();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final first = module.rows.first;
    final second = module.rows.last;
    final a = module.open(first);
    final b = module.open(second);
    port.reads[0].complete(await ExampleDirectMessages().history(first.ref));
    await a;
    expect(module.messages, isEmpty);
    port.events.add(null);
    await Future<void>.delayed(Duration.zero);
    port.reads[1].complete(await ExampleDirectMessages().history(second.ref));
    await b;
    expect(module.selected, isNull);
    expect(module.messages, isEmpty);
  });
  test('failed page keeps history, revoked permission clears it, duplicates are rejected', () async {
    final port = Pending();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final row = module.rows.first;
    final initial = await ExampleDirectMessages().history(row.ref);
    final open = module.open(row);
    port.reads[0].complete(initial);
    await open;
    final older = module.load(older: true);
    expect(port.cursors.last.$2, 11);
    port.reads[1].completeError(const DirectReadFailure('unavailable'));
    await older;
    expect(module.messages, hasLength(50));
    expect(module.error, 'unavailable');
    final bad = module.load(older: true);
    port.reads[2].complete(initial);
    await bad;
    expect(module.messages, hasLength(50));
    expect(module.error, 'data_invalid');
    final revoked = module.load(newer: true);
    expect(port.cursors.last.$3, 60);
    port.reads[3].completeError(const DirectReadFailure('forbidden'));
    await revoked;
    expect(module.messages, isEmpty);
    expect(module.error, 'forbidden');
  });
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('narrow conversation flow with composer $locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(locale, ExampleDirectMessages.new));
      await tester.pumpAndSettle();
      expect(find.text('示例好友 (Example)'), findsOneWidget);
      await tester.tap(find.text('示例好友 (Example)'));
      await tester.pumpAndSettle();
      expect(find.text('这是会话历史示例 60'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChatAvatar), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(
          TextButton,
          AppStrings.resolve(locale).text('direct.backList'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(AppStrings.resolve(locale).text('direct.requests')),
      );
      await tester.pumpAndSettle();
      expect(find.text('示例用户 (Example_Request)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'history visual review and older paging preserves scroll anchor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final font in {
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(const Locale('zh', 'CN'), ExampleDirectMessages.new),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例好友 (Example)'));
      await tester.pumpAndSettle();
      if (Platform.environment['STARBRIDGE_CAPTURE_DIRECT'] == '1') {
        await tester.runAsync(() async {
          final bitmap =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/reviews').create(recursive: true);
          await File('build/reviews/direct-messages.png')
              .writeAsBytes(data!.buffer.asUint8List());
          bitmap.dispose();
        });
      }
      final list = find.byType(ListView).last;
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final position = scrollable.position.pixels;
      await tester.tap(find.text('加载更早消息'));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(position, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
