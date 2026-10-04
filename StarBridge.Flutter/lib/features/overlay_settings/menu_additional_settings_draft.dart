import 'package:flutter/foundation.dart';

import '../../platform/window/menu_browser_resume.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../platform/window/menu_shortcut_settings.dart';

typedef MenuAdditionalEdits = ({
  MenuShortcutSettings? shortcut,
  bool? resume,
  MenuScreenshotDirectorySelection? directory,
  bool resetDirectory,
});

/// Stages local settings without registering keys, clearing URLs or moving files.
/// Each successful save is acknowledged separately; failed edits remain pending.
class MenuAdditionalSettingsDraft extends ChangeNotifier {
  MenuAdditionalSettingsDraft({
    this.shortcutPort,
    this.resumePort,
    this.directoryPort,
  });
  final MenuShortcutSettingsPort? shortcutPort;
  final MenuBrowserResumePort? resumePort;
  final MenuScreenshotDirectoryPort? directoryPort;
  MenuShortcutSettings? savedShortcut;
  MenuBrowserResume? _resume;
  MenuScreenshotDirectory? _directory;
  MenuAdditionalEdits _edits = empty;
  static const MenuAdditionalEdits empty = (
    shortcut: null,
    resume: null,
    directory: null,
    resetDirectory: false,
  );
  VoidCallback? beforeChange;
  bool busy = false, failed = false, _closed = false;
  MenuAdditionalEdits get edits => _edits;
  MenuShortcutSettings? get shortcut => _edits.shortcut ?? savedShortcut;
  MenuBrowserResume? get resume => _resume == null
      ? null
      : MenuBrowserResume(
          _resume!.revision,
          _edits.resume ?? _resume!.enabled,
          _resume!.url,
        );
  MenuScreenshotDirectory? get directory => _edits.directory == null
      ? _directory
      : MenuScreenshotDirectory(
          revision: _directory!.revision,
          directory: _edits.directory!.directory,
          isDefault: false,
        );
  bool get resetPending => _edits.resetDirectory;
  bool get shortcutDirty => _edits.shortcut != null;
  bool get resumeDirty => _edits.resume != null;
  bool get directoryDirty => _edits.directory != null || _edits.resetDirectory;
  bool get dirty => shortcutDirty || resumeDirty || directoryDirty;
  bool get clearsBrowserMemory =>
      _resume?.enabled == true && _edits.resume == false;
  bool get canChooseDirectory =>
      directoryPort is StagedMenuScreenshotDirectoryPort;

  void restore(MenuAdditionalEdits value) {
    if (_closed || busy) return;
    _edits = value;
    failed = false;
    notifyListeners();
  }

  void discard() => restore(empty);
  void _change(MenuAdditionalEdits value) {
    if (_closed || busy || value == _edits) return;
    beforeChange?.call();
    restore(value);
  }

  void changeShortcut({String? binding, bool? enabled, bool? closeWithHotkey}) {
    final old = shortcut;
    if (old == null) return;
    final next = MenuShortcutSettings(
      old.revision,
      binding ?? old.binding,
      enabled ?? old.enabled,
      closeWithHotkey ?? old.closeWithHotkey,
      old.state,
    );
    _change((
      shortcut: _sameShortcut(next, savedShortcut!) ? null : next,
      resume: _edits.resume,
      directory: _edits.directory,
      resetDirectory: _edits.resetDirectory,
    ));
  }

  void changeResume(bool enabled) {
    if (_resume == null) return;
    _change((
      shortcut: _edits.shortcut,
      resume: enabled == _resume!.enabled ? null : enabled,
      directory: _edits.directory,
      resetDirectory: _edits.resetDirectory,
    ));
  }

  Future<void> chooseDirectory() async {
    final port = directoryPort;
    if (port is! StagedMenuScreenshotDirectoryPort ||
        _directory == null ||
        busy ||
        _closed) {
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final selected = await port.chooseDraft(_directory!);
      if (_closed) return;
      busy = false;
      if (!selected.cancelled) {
        _change((
          shortcut: _edits.shortcut,
          resume: _edits.resume,
          directory: selected.directory == _directory!.directory
              ? null
              : selected,
          resetDirectory: false,
        ));
      }
    } on Object {
      if (!_closed) failed = true;
    } finally {
      if (!_closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void resetDirectory() {
    if (_directory == null) return;
    _change((
      shortcut: _edits.shortcut,
      resume: _edits.resume,
      directory: null,
      resetDirectory: !_directory!.isDefault,
    ));
  }

  Future<void> openDirectory() async {
    if (_closed || busy || directoryDirty || _directory == null) return;
    busy = true;
    notifyListeners();
    try {
      await directoryPort!.open(_directory!);
    } on Object {
      if (!_closed) failed = true;
    } finally {
      if (!_closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> reload() async {
    if (busy || dirty || _closed) return;
    busy = true;
    failed = false;
    notifyListeners();
    Future<void> read(Future<void> Function() action) async {
      try {
        await action();
      } on Object {
        if (!_closed) failed = true;
      }
    }

    await Future.wait([
      if (shortcutPort != null)
        read(() async {
          final v = await shortcutPort!.readShortcut();
          if (!_closed) savedShortcut = v;
        }),
      if (resumePort != null)
        read(() async {
          final v = await resumePort!.read();
          if (!_closed) _resume = v;
        }),
      if (directoryPort != null)
        read(() async {
          final v = await directoryPort!.read();
          if (!_closed) _directory = v;
        }),
    ]);
    if (!_closed) {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> save({required bool clearBrowserMemoryConfirmed}) async {
    if (_closed ||
        busy ||
        clearsBrowserMemory && !clearBrowserMemoryConfirmed) {
      return false;
    }
    busy = true;
    failed = false;
    notifyListeners();
    Future<void> commit(Future<void> Function() action) async {
      if (_closed) return;
      try {
        await action();
      } on Object {
        if (!_closed) failed = true;
      }
    }

    if (shortcutDirty) {
      await commit(() async {
        final latest = await shortcutPort!.readShortcut();
        if (_closed) return;
        final wanted = _edits.shortcut!;
        if (!_sameShortcut(latest, savedShortcut!) &&
            !_sameShortcut(latest, wanted)) {
          throw StateError('shortcut changed elsewhere');
        }
        final next = _sameShortcut(latest, wanted)
            ? latest
            : await shortcutPort!.saveShortcut(
                MenuShortcutSettings(
                  latest.revision,
                  wanted.binding,
                  wanted.enabled,
                  wanted.closeWithHotkey,
                  latest.state,
                ),
              );
        if (_closed) return;
        savedShortcut = next;
        _edits = (
          shortcut: null,
          resume: _edits.resume,
          directory: _edits.directory,
          resetDirectory: _edits.resetDirectory,
        );
      });
    }
    if (resumeDirty) {
      await commit(() async {
        final latest = await resumePort!.read();
        if (_closed) return;
        final wanted = _edits.resume!;
        // Remembering a newer URL is not a conflict with changing this permission.
        if (latest.enabled != _resume!.enabled && latest.enabled != wanted) {
          throw StateError('browser memory changed elsewhere');
        }
        final next = latest.enabled == wanted
            ? latest
            : await resumePort!.setEnabled(latest, wanted);
        if (_closed) return;
        _resume = next;
        _edits = (
          shortcut: _edits.shortcut,
          resume: null,
          directory: _edits.directory,
          resetDirectory: _edits.resetDirectory,
        );
      });
    }
    if (directoryDirty) {
      await commit(() async {
        final next = _edits.resetDirectory
            ? await directoryPort!.reset(_directory!)
            : await (directoryPort! as StagedMenuScreenshotDirectoryPort)
                  .commitDraft(_edits.directory!);
        if (_closed) return;
        _directory = next;
        _edits = (
          shortcut: _edits.shortcut,
          resume: _edits.resume,
          directory: null,
          resetDirectory: false,
        );
      });
    }
    if (_closed) return false;
    busy = false;
    notifyListeners();
    return !dirty && !failed;
  }

  @override
  void dispose() {
    _closed = true;
    _edits = empty;
    savedShortcut = null;
    _resume = null;
    _directory = null;
    super.dispose();
  }
}

bool _sameShortcut(MenuShortcutSettings a, MenuShortcutSettings b) =>
    a.binding == b.binding &&
    a.enabled == b.enabled &&
    a.closeWithHotkey == b.closeWithHotkey;
