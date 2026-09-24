import 'dart:io';

import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/friends/example_friends_adapter.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_message_bubble.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_avatar.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/example_room_chat.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_picker.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_colors.dart';
import 'package:starbridge_flutter/features/party_rooms/room_activity_page.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';

Widget app(Widget child, [AppearanceMode mode = AppearanceMode.dark]) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(mode),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(body: child),
    );
void size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_SOCIAL'] != '1') return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/reviews').create(recursive: true);
    await File('build/reviews/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> loadFonts() async {
  for (final font in {
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
    'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
  }.entries) {
    await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
  }
}

void main() {
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_CAPTURE_SOCIAL'] == '1') {
      await loadFonts();
    }
  });
  testWidgets(
    'notification actions stay inside cards at desktop and narrow widths',
    (tester) async {
      final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
      await module.selectPreviewScene('host');
      for (final width in [1200.0, 390.0]) {
        size(tester, Size(width, 800));
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(RoomActivityPage(module: module)),
          ),
        );
        await tester.pumpAndSettle();
        final actions = find.widgetWithText(OutlinedButton, '前往房间');
        expect(actions, findsNWidgets(2));
        for (final action in actions.evaluate()) {
          final button = find.byWidget(action.widget);
          final card = find.ancestor(of: button, matching: find.byType(Card));
          expect(card, findsOneWidget);
          expect(
            tester.getRect(card).contains(tester.getCenter(button)),
            isTrue,
          );
        }
        expect(
          find.ancestor(
            of: find.widgetWithText(TextButton, '刷新房间'),
            matching: find.byType(Card),
          ),
          findsNothing,
        );
        await capture(tester, key, 'notifications-contained-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
  testWidgets('friends left navigation, framed rows and direct open action', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          FriendsPage(
            createPort: ExampleFriendsAdapter.new,
            createChatPort: ExampleDirectMessages.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.byKey(const Key('friends-nav-friends')),
        card = find.byKey(const Key('friend-card-0'));
    expect(tester.getTopLeft(nav).dx, lessThan(tester.getTopLeft(card).dx));
    expect(
      (tester.widget<Container>(card).decoration! as BoxDecoration).border,
      isNotNull,
    );
    final message = find.byKey(const Key('friend-message-0'));
    expect(message.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(message).dx,
      greaterThan(tester.getTopRight(find.text('示例好友 (Example)')).dx),
    );
    final unread = find.descendant(
      of: message,
      matching: find.byType(AttentionCount),
    );
    expect(tester.widget<AttentionCount>(unread).count, 2);
    expect(tester.getRect(message).contains(tester.getCenter(unread)), isTrue);
    final incoming = find.byKey(const Key('friends-nav-incoming'));
    expect(
      tester
          .widget<AttentionCount>(
            find.descendant(
              of: incoming,
              matching: find.byType(AttentionCount),
            ),
          )
          .count,
      1,
    );
    final outgoing = find.byKey(const Key('friends-nav-outgoing'));
    expect(
      find.descendant(of: outgoing, matching: find.byType(AttentionCount)),
      findsNothing,
    );
    await capture(tester, key, 'friends-blue-layout');
    await tester.tap(find.byType(ChatAvatar).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '查看资料'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, '删除好友'), findsOneWidget);
    await capture(tester, key, 'friend-avatar-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(message);
    await tester.pumpAndSettle();
    expect(find.byType(DirectMessagesPage), findsOneWidget);
    expect(find.byType(ChatMessageBubble), findsWidgets);
    expect(find.text('这是会话历史示例 60'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'room chat shares private bubbles with avatar sides and attachment action',
    (tester) async {
      size(tester, const Size(1000, 720));
      final module = RoomChatModule(
        ExampleRoomChat(),
        interval: const Duration(hours: 1),
      );
      module.setRoom('example');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(RoomChatPanel(module: module)),
        ),
      );
      await tester.pumpAndSettle();
      final bubbles = tester
          .widgetList<ChatMessageBubble>(find.byType(ChatMessageBubble))
          .toList();
      expect(bubbles.map((b) => b.incoming), [true, false]);
      for (final b in bubbles) {
        final bubble = find.byKey(b.key!);
        final avatar = find.descendant(
          of: bubble,
          matching: find.byType(ChatAvatar),
        );
        final text = find.descendant(
          of: bubble,
          matching: find.byType(SelectableText),
        );
        expect(avatar, findsOneWidget);
        expect(
          tester.getCenter(avatar).dx < tester.getCenter(text).dx,
          b.incoming,
        );
      }
      await capture(tester, key, 'room-chat-blue-layout');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
  testWidgets(
    'tag picker is draft-only, hierarchical and independently colored',
    (tester) async {
      size(tester, const Size(1200, 800));
      Set<String>? result;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showRoomTagPicker(
                    context,
                    options: RoomTagCatalog.exampleOptions,
                    selected: {'combat'},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final id in ['combat', 'pve', 'pve_bounty']) {
        await tester.tap(find.byKey(ValueKey('browse-tag-$id')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('room-tag-add-current')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-tag-combat')), findsNothing);
      expect(find.byKey(const Key('selected-tag-pve_bounty')), findsOneWidget);
      final context = tester.element(find.byType(AlertDialog));
      expect(
        roomTagColors(context, 'pve_bounty').foreground,
        isNot(FutureRestraintStyle.resolve(AppearanceMode.dark).colors.accent),
      );
      expect(
        roomTagColors(context, 'industry').foreground,
        isNot(roomTagColors(context, 'pve_bounty').foreground),
      );
      await capture(tester, key, 'room-tag-picker');
      expect(result, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-tag-combat')), findsOneWidget);
      await tester.tap(find.byKey(const Key('room-tags-confirm')));
      await tester.pumpAndSettle();
      expect(result, {'combat'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('blue accent changes do not recolor semantic domains and meet text contrast', () {
    for (final mode in AppearanceMode.values) {
      final tokens = FutureRestraintStyle.resolve(mode), colors = tokens.colors;
      final a = colors.accent.computeLuminance(),
          b = colors.onAccent.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
        greaterThan(4.5),
      );
      expect(colors.accent, isNot(tokens.domainColors.airCombat.foreground));
      expect(colors.accent, isNot(colors.danger));
      expect(tokens.surfaces.selected.fill, colors.accentSoft);
    }
  });
}
