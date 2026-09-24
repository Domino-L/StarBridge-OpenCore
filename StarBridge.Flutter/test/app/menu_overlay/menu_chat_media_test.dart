import 'package:flutter/material.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_inline_avatar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';

import 'menu_comms_channels_test.dart' show channel;
import '../../features/friends/social_layout_test.dart' show app, size;

const photo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

void main() {
  testWidgets('loading animates only when motion is enabled', (tester) async {
    await tester.pumpWidget(app(const MenuLoading()));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(
      app(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MenuLoading(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .5,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('right thumb drags history in a separate avatar gutter', (
    tester,
  ) async {
    size(tester, const Size(900, 740));
    final data = channel();
    data['rows'] = [
      for (var i = 0; i < 40; i++)
        {'title': 'Sender', 'detail': 'Message $i', 'avatar': photo},
    ];
    data['chat'] = {
      'status': 'idle',
      'revision': 0,
      'receipts': {},
      'messages': [
        for (var i = 0; i < 40; i++)
          {'self': true, 'time': '2026-09-23T18:20:00Z'},
      ],
    };
    await tester.pumpWidget(
      app(
        MenuChannelPanel(
          view: MenuFeatureView.parse(data),
          active: false,
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('menu-chat-scrollbar')),
    );
    final rect = tester.getRect(
      find.byKey(const ValueKey('menu-chat-scrollbar')),
    );
    final listRect = tester.getRect(
      find.byKey(const ValueKey('menu-channel-history')),
    );
    expect(rect.right - listRect.right, 16);
    expect(scroll.controller!.offset, 0);
    await tester.dragFrom(
      Offset(rect.right - 4, rect.bottom - 24),
      const Offset(0, -140),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));
    (data['rows'] as List).add({
      'title': 'Sender',
      'detail': 'New arrival',
      'avatar': photo,
    });
    ((data['chat'] as Map)['messages'] as List).add({
      'self': false,
      'time': '2026-09-23T18:21:00Z',
    });
    await tester.pumpWidget(
      app(
        MenuChannelPanel(
          view: MenuFeatureView.parse(data),
          active: false,
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));
    expect(
      find.byKey(const ValueKey('menu-channel-new-messages')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('menu-channel-new-messages')));
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('channel shows supplied sender portraits', (tester) async {
    size(tester, const Size(900, 740));
    final data = channel();
    for (final row in data['rows'] as List) {
      row['avatar'] = photo;
    }
    await tester.pumpWidget(
      app(
        MenuChannelPanel(
          view: MenuFeatureView.parse(data),
          active: false,
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widgetList<MenuInlineAvatar>(find.byType(MenuInlineAvatar))
          .where((a) => a.source == photo)
          .length,
      2,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('refresh retains history with progress and draggable scrollbar', (
    tester,
  ) async {
    size(tester, const Size(900, 740));
    final data = channel()..addAll({'refreshing': true, 'notice': '正在更新消息…'});
    await tester.pumpWidget(
      app(
        MenuChannelPanel(
          view: MenuFeatureView.parse(data),
          active: false,
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('menu-chat-scrollbar')),
    );
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(find.byKey(const ValueKey('menu-channel-history')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
