import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import '../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets('offstage conversation is not read until its view is active', (
    tester,
  ) async {
    size(tester, const Size(1200, 800));
    final port = ExampleDirectMessages();
    final friend = (await port.directory()).first;
    Widget view(bool enabled) => app(
      TickerMode(
        enabled: enabled,
        child: DirectMessagesPage(
          createPort: () => port,
          onBack: () {},
          initialConversation: friend,
        ),
      ),
    );
    await tester.pumpWidget(view(false));
    await tester.pumpAndSettle();
    expect((await port.directory()).first.unread, 2);
    await tester.pumpWidget(view(true));
    await tester.pumpAndSettle();
    expect((await port.directory()).first.unread, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'compact badge is at upper right without shifting the centered icon',
    (tester) async {
      size(tester, const Size(200, 100));
      final count = ValueNotifier<int>(1);
      final imageKey = GlobalKey();
      addTearDown(count.dispose);
      var tapped = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: imageKey,
            child: Center(
              child: SizedBox(
                width: 56,
                child: ShellNavigationItem(
                  descriptor: FeatureDescriptor(
                    id: 'room',
                    route: '/rooms',
                    labelKey: 'navigation.rooms',
                    descriptionKey: 'navigation.rooms.description',
                    icon: StarBridgeIconSemantic.account,
                    navigationRegion: NavigationRegion.primary,
                    order: 0,
                    buildDestination: (_) => const SizedBox(),
                    attentionCount: count,
                  ),
                  mode: ShellLayoutMode.iconOnly,
                  selected: true,
                  onPressed: () => tapped++,
                  onKeyboardPressed: () {},
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final icon = tester.getRect(find.byType(StarBridgeIcon));
      await capture(tester, imageKey, 'compact-unread-right');
      final badge = tester.getRect(find.byType(AttentionCount));
      expect(badge.center.dx, greaterThan(icon.center.dx));
      expect(badge.center.dy, lessThan(icon.center.dy));
      final button = tester.getRect(find.byType(InkWell));
      expect(icon.center.dx, closeTo(button.center.dx, 0.1));
      expect(icon.center.dy, closeTo(button.center.dy, 0.1));
      expect(button.contains(badge.topLeft), isTrue);
      expect(button.contains(badge.bottomRight - const Offset(.1, .1)), isTrue);
      await tester.tapAt(badge.center);
      expect(tapped, 1);
      count.value = 120;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final largeBadge = tester.getRect(find.byType(AttentionCount));
      expect(
        button.contains(largeBadge.bottomRight - const Offset(.1, .1)),
        isTrue,
      );
      expect(
        largeBadge.center.dx,
        greaterThan(tester.getRect(find.byType(StarBridgeIcon)).center.dx),
      );
      expect(tester.getRect(find.byType(StarBridgeIcon)), icon);
      expect(largeBadge.center.dy, lessThan(icon.center.dy));
    },
  );
  testWidgets(
    'viewed conversation clears unread and stays read after refresh',
    (tester) async {
      size(tester, const Size(1200, 800));
      final port = ExampleDirectMessages();
      await tester.pumpWidget(
        app(DirectMessagesPage(createPort: () => port, onBack: () {})),
      );
      await tester.pumpAndSettle();
      expect((await port.directory()).first.unread, 2);
      await tester.tap(find.text('示例好友 (Example)'));
      await tester.pumpAndSettle();
      expect(find.text('这是会话历史示例 59'), findsOneWidget);
      expect((await port.directory()).first.unread, 0);
      expect((await port.directory()).last.unread, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(DirectMessagesPage(createPort: () => port, onBack: () {})),
      );
      await tester.pumpAndSettle();
      expect((await port.directory()).first.unread, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
