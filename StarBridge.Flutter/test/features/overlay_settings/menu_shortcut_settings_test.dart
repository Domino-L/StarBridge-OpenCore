import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_shortcut_settings_card.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Port implements MenuShortcutSettingsPort {
  MenuShortcutSettings value = const MenuShortcutSettings(
    4,
    'F9',
    true,
    true,
    'registered',
  );
  final writes = <MenuShortcutSettings>[];
  String? failure;
  Completer<MenuShortcutSettings>? pending;
  @override
  Future<MenuShortcutSettings> readShortcut() async =>
      pending == null ? value : await pending!.future;
  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings next) async {
    writes.add(next);
    if (failure case final code?) throw BridgeClientException(code);
    return value = MenuShortcutSettings(
      value.revision + 1,
      next.binding,
      next.enabled,
      next.closeWithHotkey,
      next.enabled ? 'registered' : 'disabled',
    );
  }
}

void main() {
  setUpAll(loadFonts);
  final save = find.byKey(const Key('menu-shortcut-save'));
  Future<void> show(WidgetTester tester, _Port port) async {
    await tester.pumpWidget(
      app(SingleChildScrollView(child: MenuShortcutSettingsCard(port: port))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edit is staged and explicit save persists both switches', (
    tester,
  ) async {
    final port = _Port();
    await show(tester, port);
    expect(find.text('F9'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pump();
    expect(port.writes, isEmpty);
    expect(find.textContaining('尚未保存'), findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(port.writes.single.revision, 4);
    expect(port.value.enabled, false);
    expect(port.value.closeWithHotkey, false);
    expect(find.text('快捷键已关闭，仍可通过按钮打开菜单。'), findsOneWidget);
  });
  testWidgets(
    'conflict keeps draft; reload updates revision without discarding draft',
    (tester) async {
      final port = _Port()..failure = 'menuHotkey.conflictWithInformation';
      await show(tester, port);
      await tester.tap(find.byKey(const Key('overlay-hotkey-reset')));
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-shortcut-error')), findsOneWidget);
      expect(port.value.binding, 'F9');
      expect(
        find.byKey(const ValueKey('overlay-hotkey-Alt+M')),
        findsOneWidget,
      );
      port.value = const MenuShortcutSettings(
        8,
        'F10',
        true,
        true,
        'registered',
      );
      await tester.tap(find.byKey(const Key('menu-shortcut-reload')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overlay-hotkey-Alt+M')),
        findsOneWidget,
      );
      port.failure = null;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(port.writes.last.revision, 8);
      expect(port.value.binding, 'Alt+M');
    },
  );
  testWidgets('shared recorder captures F8 and Escape cancels capture', (
    tester,
  ) async {
    final port = _Port();
    await show(tester, port);
    await tester.tap(find.byKey(const Key('overlay-hotkey-record')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('F9'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const Key('overlay-hotkey-record')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(find.text('F8'), findsOneWidget);
    expect(port.writes, isEmpty);
  });
  testWidgets('late old provider read cannot replace current settings', (
    tester,
  ) async {
    final old = _Port()..pending = Completer<MenuShortcutSettings>();
    await show(tester, old);
    final current = _Port()
      ..value = const MenuShortcutSettings(2, 'F7', false, false, 'disabled');
    await show(tester, current);
    old.pending!.complete(old.value);
    await tester.pumpAndSettle();
    expect(find.text('F7'), findsOneWidget);
    expect(find.text('F9'), findsNothing);
  });
  for (final width in [320.0, 760.0, 1040.0]) {
    testWidgets('shortcut settings fit width $width', (tester) async {
      size(tester, Size(width, 900));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: SingleChildScrollView(
              child: MenuShortcutSettingsCard(port: _Port()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-shortcut-${width.toInt()}');
    });
  }
}
