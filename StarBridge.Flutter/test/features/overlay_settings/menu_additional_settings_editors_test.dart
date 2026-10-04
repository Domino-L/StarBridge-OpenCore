import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_editors.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_hotkey_card.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'menu_browser_resume_settings_test.dart' show MemoryBrowserResume;
import 'menu_screenshot_directory_settings_test.dart' show DirectoryPort;
import 'menu_settings_workspace_test.dart' show Port;

class _ShortcutPort implements MenuShortcutSettingsPort {
  int writes = 0;
  @override
  Future<MenuShortcutSettings> readShortcut() async =>
      const MenuShortcutSettings(0, 'Alt+M', true, true, 'registered');
  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) async {
    writes++;
    return value;
  }
}

void main() {
  test(
    'folder opening remains available only for the committed destination',
    () async {
      final port = DirectoryPort()
        ..value = const MenuScreenshotDirectory(
          revision: 0,
          directory: r'C:\Synthetic\Custom',
          isDefault: false,
        );
      final draft = MenuAdditionalSettingsDraft(directoryPort: port);
      await draft.reload();
      await draft.openDirectory();
      expect(port.calls.where((c) => c == 'open').length, 1);
      draft.resetDirectory();
      await draft.openDirectory();
      expect(port.calls.where((c) => c == 'open').length, 1);
      draft.discard();
      await draft.openDirectory();
      expect(port.calls.where((c) => c == 'open').length, 2);
      draft.dispose();
    },
  );
  testWidgets(
    'shortcut and browser editors stage changes without local save controls',
    (tester) async {
      size(tester, const Size(900, 1000));
      final shortcut = _ShortcutPort(), resume = MemoryBrowserResume();
      final draft = MenuAdditionalSettingsDraft(
        shortcutPort: shortcut,
        resumePort: resume,
      );
      await draft.reload();
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: Column(
              children: [
                MenuAdditionalShortcutEditor(draft: draft),
                MenuAdditionalResumeEditor(draft: draft),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OverlayWorkspaceHotkeyCard>(
              find.byType(OverlayWorkspaceHotkeyCard),
            )
            .embedded,
        true,
      );
      await tester.tap(find.byKey(const Key('menu-shortcut-close')));
      await tester.tap(find.byKey(const Key('menu-browser-resume-toggle')));
      await tester.pump();
      expect(draft.shortcut!.closeWithHotkey, false);
      expect(draft.resume!.enabled, true);
      expect(shortcut.writes, 0);
      expect(resume.updates, 0);
      expect(find.byKey(const Key('menu-shortcut-save')), findsNothing);
      expect(find.text('已保存并启用。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );

  testWidgets(
    'pending reset hides old directory and never resets before page save',
    (tester) async {
      final port = DirectoryPort()
        ..value = const MenuScreenshotDirectory(
          revision: 0,
          directory: r'C:\Synthetic\Custom',
          isDefault: false,
        );
      final draft = MenuAdditionalSettingsDraft(directoryPort: port);
      await draft.reload();
      await tester.pumpWidget(app(MenuAdditionalDirectoryEditor(draft: draft)));
      await tester.pumpAndSettle();
      expect(find.text(r'C:\Synthetic\Custom'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('menu-screenshot-directory-reset')),
      );
      await tester.pump();
      expect(find.text(r'C:\Synthetic\Custom'), findsNothing);
      expect(find.text('默认目录（保存后恢复）'), findsOneWidget);
      expect(port.calls, ['read']);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );

  testWidgets(
    'cancel clearing browser memory writes no page changes; confirm saves both',
    (tester) async {
      final port = Port();
      final resume = MemoryBrowserResume()
        ..value = const MenuBrowserResume(0, true, 'https://example.test/');
      final additional = MenuAdditionalSettingsDraft(resumePort: resume);
      final draft = MenuSettingsDraft(port)..attachAdditional(additional);
      await draft.initialize();
      await additional.reload();
      draft.change({'showClock': false});
      additional.changeResume(false);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmMenuSettingsSave(context, draft),
              child: const Text('保存全部'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存全部'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不会关闭已经打开的网页'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(port.writes, 0);
      expect(resume.updates, 0);
      expect(draft.dirty, true);
      await tester.tap(find.text('保存全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除记忆并保存'));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(resume.updates, 1);
      expect(resume.value.url, null);
      expect(draft.dirty, false);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
}
