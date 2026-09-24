import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_composer.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_message_bubble.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/design_system/styles/menu_bridge_palette.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import 'menu_comms_channels_test.dart' show channel;
import 'menu_comms_maturity_test.dart' show fixture;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

void main() {
  setUpAll(loadFonts);
  for (final width in [900.0, 340.0]) {
    testWidgets('channel preserves right send and adapts portraits at $width', (
      tester,
    ) async {
      size(tester, Size(width, 740));
      final boundary = GlobalKey();
      final data = channel();
      ((data['chat'] as Map)['messages'] as List).first.addAll({
        'role': '舰队指挥官',
        'roleColor': '#FFD240',
      });
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: Theme(
              data: buildMenuOverlayTheme(const Locale('zh')),
              child: ColoredBox(
                color: BridgeInk.window,
                child: MenuChannelPanel(
                  view: MenuFeatureView.parse(data),
                  active: false,
                  onAction: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-channel-draft')),
        '准备出发',
      );
      await tester.pumpAndSettle();
      final input = tester.getRect(
        find.byKey(const ValueKey('menu-channel-draft')),
      );
      final send = tester.getRect(
        find.byKey(const ValueKey('menu-channel-send')),
      );
      expect(send.right, closeTo(input.right, 1));
      expect(send.center.dx, greaterThan(input.center.dx));
      expect(find.text('舰队指挥官'), findsOneWidget);
      final bubbles = tester.widgetList<ChatMessageBubble>(
        find.byType(ChatMessageBubble),
      );
      expect(bubbles.every((b) => b.compact == (width < 380)), isTrue);
      final fills = find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Container),
      );
      final colors = tester
          .widgetList<Container>(fills)
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => (c.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toSet();
      expect(colors.length, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'menu-chat-channel-$width');
    });
  }
  testWidgets(
    'private composer sends from right without changing draft protocol',
    (tester) async {
      size(tester, const Size(760, 350));
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          MenuCommsComposer(
            view: fixture(),
            onCompose: (a, key, text, revision) => actions.add('$a:$text'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-message-draft')),
        '确认',
      );
      await tester.pump();
      final input = tester.getRect(
        find.byKey(const ValueKey('menu-message-draft')),
      );
      final send = tester.getRect(
        find.byKey(const ValueKey('menu-message-send')),
      );
      expect(send.right, closeTo(input.right, 1));
      await tester.tap(find.byKey(const ValueKey('menu-message-send')));
      expect(actions, ['edit:确认', 'send:确认']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('channel rejects malformed role colors but accepts cached rows without them', () {
    expect(MenuFeatureView.parse(channel()).state, 'ready');
    final data = channel();
    ((data['chat'] as Map)['messages'] as List).first['roleColor'] = 'invalid';
    expect(MenuFeatureView.parse(data).state, 'unavailable');
  });
  test('menu matches client dark colors, surfaces and semantic states', () {
    final theme = buildMenuOverlayTheme(const Locale('zh'));
    final tokens = theme.extension<StarBridgeTokens>()!;
    final original = FutureRestraintStyle.resolve(AppearanceMode.dark);
    double contrast(Color text, Color background) =>
        (text.computeLuminance() + .05) / (background.computeLuminance() + .05);
    for (final surface in SurfaceRole.values) {
      final fill = tokens.surfaces.resolve(surface).fill;
      expect(fill, original.surfaces.resolve(surface).fill);
      expect(
        tokens.surfaces.resolve(surface).border,
        original.surfaces.resolve(surface).border,
      );
      expect(
        contrast(tokens.colors.textPrimary, fill),
        greaterThanOrEqualTo(7),
      );
      expect(
        contrast(tokens.colors.textSecondary, fill),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(tokens.colors.success, original.colors.success);
    expect(tokens.colors.warning, original.colors.warning);
    expect(tokens.colors.danger, original.colors.danger);
    expect(tokens.colors.info, original.colors.info);
    expect(tokens.colors, same(original.colors));
    expect(BridgeInk.text, original.colors.textPrimary);
    expect(BridgeInk.muted, original.colors.textSecondary);
    expect(BridgeInk.blue, original.colors.accent);
    expect(BridgeInk.green, original.colors.success);
    expect(BridgeInk.amber, original.colors.warning);
    expect(BridgeInk.danger, original.colors.danger);
    expect(BridgeInk.ground, original.surfaces.ground.fill);
    expect(BridgeInk.divider, original.surfaces.ground.border);
    expect(BridgeInk.line, original.surfaces.panel.border);
    expect(BridgeInk.selected, original.surfaces.selected.fill);
    expect(BridgeInk.window.withValues(alpha: 1), original.surfaces.panel.fill);
    expect(BridgeInk.panel.withValues(alpha: 1), original.surfaces.panel.fill);
    final button = theme.filledButtonTheme.style!;
    expect(button.backgroundColor!.resolve({}), original.colors.accent);
    expect(
      (button.side!.resolve({WidgetState.focused})!).color,
      original.colors.focusRing,
    );
  });
}
