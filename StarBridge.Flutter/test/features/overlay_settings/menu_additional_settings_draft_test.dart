import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

class _Shortcut implements MenuShortcutSettingsPort {
  MenuShortcutSettings value = const MenuShortcutSettings(
    3,
    'Alt+M',
    true,
    true,
    'registered',
  );
  int reads = 0;
  final writes = <MenuShortcutSettings>[];
  bool fail = false;
  Completer<MenuShortcutSettings>? pendingRead;
  @override
  Future<MenuShortcutSettings> readShortcut() async {
    reads++;
    return pendingRead == null ? value : await pendingRead!.future;
  }

  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings next) async {
    writes.add(next);
    if (fail) throw StateError('synthetic shortcut save failure');
    expect(next.revision, value.revision);
    return value = MenuShortcutSettings(
      value.revision + 1,
      next.binding,
      next.enabled,
      next.closeWithHotkey,
      'registered',
    );
  }
}

class _Resume implements MenuBrowserResumePort {
  MenuBrowserResume value = const MenuBrowserResume(
    7,
    true,
    'https://example.invalid/retained',
  );
  final writes = <(MenuBrowserResume, bool)>[];
  Completer<MenuBrowserResume>? pendingRead;
  @override
  Future<MenuBrowserResume> read() async =>
      pendingRead == null ? value : await pendingRead!.future;
  @override
  Future<MenuBrowserResume> setEnabled(
    MenuBrowserResume saved,
    bool enabled,
  ) async {
    writes.add((saved, enabled));
    expect(saved.revision, value.revision);
    return value = MenuBrowserResume(
      value.revision + 1,
      enabled,
      enabled ? value.url : null,
    );
  }

  @override
  Future<MenuBrowserResume> remember(MenuBrowserResume saved, String url) =>
      throw StateError('settings must not remember pages');
}

class _Directory implements StagedMenuScreenshotDirectoryPort {
  MenuScreenshotDirectory value = const MenuScreenshotDirectory(
    revision: 11,
    directory: r'C:\synthetic\screenshots',
    isDefault: true,
  );
  final commits = <MenuScreenshotDirectorySelection>[];
  int chooses = 0, resets = 0;
  bool fail = false, cancelled = false;
  Completer<MenuScreenshotDirectory>? pendingRead;
  Completer<MenuScreenshotDirectorySelection>? pendingChoice;
  @override
  Future<MenuScreenshotDirectory> read() async =>
      pendingRead == null ? value : await pendingRead!.future;
  @override
  Future<MenuScreenshotDirectorySelection> chooseDraft(
    MenuScreenshotDirectory saved,
  ) async {
    chooses++;
    if (pendingChoice != null) return pendingChoice!.future;
    return MenuScreenshotDirectorySelection(
      revision: saved.revision,
      directory: cancelled ? saved.directory : r'C:\synthetic\chosen',
      token: cancelled ? null : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      cancelled: cancelled,
    );
  }

  @override
  Future<MenuScreenshotDirectory> commitDraft(
    MenuScreenshotDirectorySelection selection,
  ) async {
    commits.add(selection);
    if (fail) throw StateError('synthetic directory save failure');
    expect(selection.revision, value.revision);
    return value = MenuScreenshotDirectory(
      revision: value.revision + 1,
      directory: selection.directory,
      isDefault: false,
    );
  }

  @override
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved) async {
    resets++;
    return value = MenuScreenshotDirectory(
      revision: value.revision + 1,
      directory: r'C:\synthetic\screenshots',
      isDefault: true,
    );
  }

  @override
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved) =>
      throw StateError('immediate chooser must not be used');
  @override
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved) =>
      throw StateError('not an editing operation');
}

class _Window implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = MenuWindowPreferences.defaults;
  final writes = <MenuWindowPreferences>[];
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes.add(next);
    expect(next.revision, value.revision);
    return value = MenuWindowPreferences(
      value.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class _Fixture {
  final shortcut = _Shortcut(),
      resume = _Resume(),
      directory = _Directory(),
      window = _Window();
  late final additional = MenuAdditionalSettingsDraft(
    shortcutPort: shortcut,
    resumePort: resume,
    directoryPort: directory,
  );
  late final draft = MenuSettingsDraft(window)..attachAdditional(additional);
  Future<void> load() async {
    await draft.initialize();
    await additional.reload();
  }

  void dispose() => draft.dispose();
  void expectNoWrites() {
    expect(shortcut.writes, isEmpty);
    expect(resume.writes, isEmpty);
    expect(directory.commits, isEmpty);
    expect(directory.resets, 0);
    expect(window.writes, isEmpty);
  }
}

void main() {
  test(
    'all additional edits and native chooser stay staged until Save',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.draft.change({'showClock': false});
      f.additional.changeShortcut(binding: 'Ctrl+M');
      f.additional.changeResume(false);
      await f.additional.chooseDirectory();
      expect(f.directory.chooses, 1);
      expect(f.additional.directory!.directory, r'C:\synthetic\chosen');
      expect(f.directory.value.directory, r'C:\synthetic\screenshots');
      expect(f.additional.resume!.enabled, isFalse);
      expect(f.resume.value.enabled, isTrue);
      expect(f.draft.dirty, isTrue);
      f.expectNoWrites();
    },
  );

  test(
    'one undo redo and discard history spans visual and additional settings',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.draft.change({'showClock': false});
      f.additional.changeShortcut(binding: 'Ctrl+M');
      f.additional.changeResume(false);
      await f.additional.chooseDirectory();
      f.draft.undo();
      expect(f.additional.directoryDirty, isFalse);
      f.draft.undo();
      expect(f.additional.resumeDirty, isFalse);
      f.draft.undo();
      expect(f.additional.shortcutDirty, isFalse);
      f.draft.undo();
      expect(f.draft.dirty, isFalse);
      expect(f.draft.settings['showClock'], isTrue);
      for (var i = 0; i < 4; i++) {
        f.draft.redo();
      }
      expect(f.draft.settings['showClock'], isFalse);
      expect(f.additional.shortcut!.binding, 'Ctrl+M');
      expect(f.additional.resume!.enabled, isFalse);
      expect(f.additional.directoryDirty, isTrue);
      f.draft.discard();
      expect(f.draft.dirty, isFalse);
      expect(f.draft.canUndo, isFalse);
      expect(f.draft.canRedo, isFalse);
      expect(f.additional.shortcut!.binding, 'Alt+M');
      expect(f.additional.resume!.enabled, isTrue);
      expect(f.additional.directory!.directory, r'C:\synthetic\screenshots');
      f.expectNoWrites();
    },
  );

  test(
    'browser-memory confirmation gates every write including ordinary settings',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.draft.change({'showClock': false});
      f.additional.changeShortcut(binding: 'Ctrl+M');
      f.additional.changeResume(false);
      await f.additional.chooseDirectory();
      expect(f.draft.clearsBrowserMemory, isTrue);
      expect(await f.draft.save(), isFalse);
      expect(
        await f.additional.save(clearBrowserMemoryConfirmed: false),
        isFalse,
      );
      f.expectNoWrites();
      expect(f.resume.value.url, isNotNull);
      expect(await f.draft.save(clearBrowserMemoryConfirmed: true), isTrue);
      expect(f.window.writes, hasLength(1));
      expect(f.shortcut.writes, hasLength(1));
      expect(f.directory.commits, hasLength(1));
      expect(f.resume.writes, hasLength(1));
      expect(f.resume.value.enabled, isFalse);
      expect(f.resume.value.url, isNull);
      expect(f.draft.dirty, isFalse);
    },
  );

  test(
    'chooser cancellation preserves existing draft and reset is also deferred',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      await f.additional.chooseDirectory();
      final selected = f.additional.edits.directory;
      f.directory.cancelled = true;
      await f.additional.chooseDirectory();
      expect(f.additional.edits.directory, same(selected));
      f.additional.discard();
      f.expectNoWrites();
      f.directory.value = const MenuScreenshotDirectory(
        revision: 12,
        directory: r'C:\synthetic\custom',
        isDefault: false,
      );
      await f.additional.reload();
      f.additional.resetDirectory();
      expect(f.additional.resetPending, isTrue);
      expect(f.directory.resets, 0);
      expect(await f.draft.save(), isTrue);
      expect(f.directory.resets, 1);
      expect(f.additional.directory!.isDefault, isTrue);
    },
  );

  test(
    'partial save retains failed items and never repeats successful writes',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.draft.change({'showClock': false});
      f.additional.changeShortcut(binding: 'Ctrl+M');
      f.additional.changeResume(false);
      await f.additional.chooseDirectory();
      f.shortcut.fail = f.directory.fail = true;
      expect(await f.draft.save(clearBrowserMemoryConfirmed: true), isFalse);
      expect(f.draft.failed, isTrue);
      expect(f.draft.dirty, isTrue);
      expect(f.additional.shortcutDirty, isTrue);
      expect(f.additional.directoryDirty, isTrue);
      expect(f.additional.resumeDirty, isFalse);
      expect(f.resume.value.url, isNull);
      expect(f.window.value.settings['showClock'], isFalse);
      f.shortcut.fail = f.directory.fail = false;
      expect(await f.draft.save(), isTrue);
      expect(f.window.writes, hasLength(1));
      expect(f.resume.writes, hasLength(1));
      expect(f.shortcut.writes, hasLength(2));
      expect(f.directory.commits, hasLength(2));
      expect(f.draft.dirty, isFalse);
      expect(f.draft.failed, isFalse);
    },
  );

  test(
    'shortcut save rereads latest revision while preserving chosen edits',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.additional.changeShortcut(binding: 'Ctrl+M', closeWithHotkey: false);
      f.shortcut.value = const MenuShortcutSettings(
        20,
        'Alt+M',
        true,
        true,
        'registered',
      );
      expect(await f.draft.save(), isTrue);
      expect(f.shortcut.reads, 2);
      expect(f.shortcut.writes.single.revision, 20);
      expect(f.shortcut.writes.single.binding, 'Ctrl+M');
      expect(f.shortcut.writes.single.closeWithHotkey, isFalse);
    },
  );

  test(
    'conflicting external shortcut changes keep local draft without overwrite',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.load();
      f.additional.changeShortcut(binding: 'Ctrl+M');
      f.shortcut.value = const MenuShortcutSettings(
        20,
        'Alt+K',
        true,
        true,
        'registered',
      );
      expect(await f.draft.save(), isFalse);
      expect(f.shortcut.writes, isEmpty);
      expect(f.additional.shortcut!.binding, 'Ctrl+M');
      expect(f.draft.dirty, isTrue);
    },
  );

  test('disposal invalidates all late initial reads', () async {
    final f = _Fixture();
    f.shortcut.pendingRead = Completer();
    f.resume.pendingRead = Completer();
    f.directory.pendingRead = Completer();
    final additional = f.additional;
    final loading = additional.reload();
    additional.dispose();
    f.shortcut.pendingRead!.complete(f.shortcut.value);
    f.resume.pendingRead!.complete(f.resume.value);
    f.directory.pendingRead!.complete(f.directory.value);
    await loading;
    expect(additional.savedShortcut, isNull);
    expect(additional.resume, isNull);
    expect(additional.directory, isNull);
    expect(additional.dirty, isFalse);
    f.expectNoWrites();
  });

  test(
    'dispose while chooser is open discards late selection and never commits',
    () async {
      final f = _Fixture();
      await f.load();
      f.directory.pendingChoice = Completer();
      final choosing = f.additional.chooseDirectory();
      f.dispose();
      f.directory.pendingChoice!.complete(
        const MenuScreenshotDirectorySelection(
          revision: 11,
          directory: r'C:\synthetic\chosen',
          token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          cancelled: false,
        ),
      );
      await choosing;
      expect(f.additional.dirty, isFalse);
      expect(f.additional.directory, isNull);
      f.expectNoWrites();
    },
  );
}
