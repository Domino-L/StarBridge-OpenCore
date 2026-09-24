import 'package:flutter/material.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/presence_color.dart';
import 'package:starbridge_flutter/app/tray/tray_presence_status.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

import 'tray_quick_panel_test.dart' show app;

void main() {
  testWidgets('running process without projection never implies online', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        TrayQuickPanel(
          state: const TrayQuickPanelState(
            runtime: TrayRuntimeState.background,
          ),
          onDismiss: () {},
        ),
      ),
    );
    expect(find.text('后台运行中'), findsOneWidget);
    expect(find.text('连接待确认'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });

  testWidgets('live avatar projection drives status and shared palette', (
    tester,
  ) async {
    final source = InMemoryShellChrome();
    await tester.pumpWidget(
      app(TrayPresenceStatus(projection: source.projection)),
    );
    for (final entry in {
      'offline': '离线',
      'online': AppStrings.resolve(const Locale('zh', 'CN'))
          .text('presence.online'),
      'away': '暂离',
      'inGame': '游戏中',
      'unknown': '连接待确认',
      'unexpected-private-value': '连接待确认',
    }.entries) {
      source.replace(
        source.projection.value.copyWith(presenceKey: 'presence.${entry.key}'),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      final context = tester.element(find.byType(TrayPresenceStatus));
      final box = tester.widget<DecoratedBox>(
        find.byKey(const Key('tray-presence-dot')),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        presenceColor(context.tokens.colors, 'presence.${entry.key}'),
      );
    }
    await tester.pumpWidget(const SizedBox());
    source.replace(InMemoryShellChrome.connectedProjection);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacement projection detaches old account source', (
    tester,
  ) async {
    final old = InMemoryShellChrome(
      initial: InMemoryShellChrome.connectedProjection,
    );
    final next = InMemoryShellChrome();
    await tester.pumpWidget(
      app(TrayPresenceStatus(projection: old.projection)),
    );
    expect(
      find.text(
        AppStrings.resolve(const Locale('zh', 'CN')).text('presence.online'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(
      app(TrayPresenceStatus(projection: next.projection)),
    );
    old.replace(old.projection.value.copyWith(presenceKey: 'presence.away'));
    await tester.pump();
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('暂离'), findsNothing);
  });

  for (final entry in {
    const Locale('zh', 'TW'): '連線待確認',
    const Locale('en'): 'Connection unconfirmed',
  }.entries) {
    testWidgets('localized status ${entry.key}', (tester) async {
      await tester.pumpWidget(
        app(
          const SizedBox(width: 300, child: TrayPresenceStatus()),
          locale: entry.key,
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
