import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_overlay_settings.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_shortcut_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_shortcut_summary.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Port implements MenuLiveWindowPort {
  final pending = Completer<bool>();
  int demoCalls = 0, liveCalls = 0;
  @override
  bool liveAvailable = true;
  @override
  Future<bool> open({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) async {
    demoCalls++;
    return true;
  }

  @override
  Future<bool> openLive({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) {
    liveCalls++;
    expect(contextLabel, '菜单浮层');
    return pending.future;
  }

  @override
  void dispose() {}
}

class _ShortcutPort extends _Port
    implements MenuShortcutSettingsProvider, MenuShortcutSettingsPort {
  MenuShortcutSettings saved = const MenuShortcutSettings(
    1,
    'Alt+K',
    true,
    true,
    'registered',
  );
  int reads = 0;
  @override
  MenuShortcutSettingsPort get shortcutSettings => this;
  @override
  Future<MenuShortcutSettings> readShortcut() async {
    reads++;
    return saved;
  }

  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) async =>
      saved = value;
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'menu header reads actual shortcut and follows successful saves',
    (tester) async {
      final port = _ShortcutPort();
      await tester.pumpWidget(app(MenuOverlaySettings(preview: port)));
      await tester.pumpAndSettle();
      OverlayShortcutSummary summary() =>
          tester.widget(find.byKey(const Key('menu-header-shortcut')));
      expect(summary().binding, 'Alt+K');
      expect(port.reads, 1);
      final editor = tester.widget<MenuShortcutSettingsCard>(
        find.byType(MenuShortcutSettingsCard),
      );
      await editor.port.saveShortcut(
        const MenuShortcutSettings(2, 'Alt+J', false, true, 'disabled'),
      );
      await tester.pump();
      expect(summary().binding, 'Alt+J');
      expect(summary().enabled, isFalse);
      await tester.pumpWidget(
        app(
          MenuOverlaySettings(
            preview: _ShortcutPort()
              ..saved = const MenuShortcutSettings(
                3,
                'Alt+L',
                true,
                true,
                'registered',
              ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(summary().binding, 'Alt+L');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'product entry has one real action with busy and failure states',
    (tester) async {
      final port = _Port();
      await tester.pumpWidget(app(MenuOverlaySettings(preview: port)));
      await tester.pumpAndSettle();
      expect(find.textContaining('功能验收'), findsNothing);
      expect(find.textContaining('演示'), findsNothing);
      expect(find.byKey(const Key('menu-overlay-open-preview')), findsNothing);
      expect(port.liveCalls, 0);
      final button = find.byKey(const Key('menu-overlay-open-live'));
      await tester.tap(button);
      await tester.pump();
      expect(port.liveCalls, 1);
      expect(port.demoCalls, 0);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      port.pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('未能显示菜单浮层，请重试。'), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    },
  );
  testWidgets('unavailable live mode never opens demo', (tester) async {
    final port = _Port()..liveAvailable = false;
    await tester.pumpWidget(app(MenuOverlaySettings(preview: port)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('menu-overlay-open-live')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('menu-overlay-open-failed')), findsOneWidget);
    expect(port.demoCalls, 0);
    expect(port.liveCalls, 0);
  });
  for (final width in [1040.0, 760.0, 320.0]) {
    testWidgets('product page layout at $width', (tester) async {
      size(tester, Size(width, 760));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: MenuOverlaySettings(preview: _Port()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-product-${width.toInt()}');
    });
  }
}
