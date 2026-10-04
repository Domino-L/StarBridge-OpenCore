import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';

import 'menu_additional_settings_draft.dart';

import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/menu_image_preferences.dart';
import '../../platform/window/menu_screenshot_preferences.dart';

import '../../platform/window/menu_window_preferences.dart';

/// One page-owned draft. No automatic writes, retries or cross-account cache.
class MenuSettingsDraft extends ChangeNotifier {
  MenuSettingsDraft(this.port);
  final MenuWindowPreferencesPort port;
  MenuWindowPreferences? _base;
  Map<String, Object?> _patch = {};
  final _undo = <(Map<String, Object?>, MenuAdditionalEdits?)>[],
      _redo = <(Map<String, Object?>, MenuAdditionalEdits?)>[];
  MenuAdditionalSettingsDraft? additional;
  void attachAdditional(MenuAdditionalSettingsDraft value) {
    additional?.removeListener(_additionalChanged);
    additional?.dispose();
    _clearHistory();
    additional = value..beforeChange = _record;
    value.addListener(_additionalChanged);
  }

  void _additionalChanged() {
    if (!_disposed) notifyListeners();
  }

  void _record() {
    _undo.add((Map.of(_patch), additional?.edits));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool _busy = false, _failed = false, _disposed = false, _started = false;
  bool conflict = false;
  bool get busy => _busy || (additional?.busy ?? false);
  bool get failed => _failed || (additional?.failed ?? false);
  bool get clearsBrowserMemory => additional?.clearsBrowserMemory ?? false;
  bool get ready => _base != null;
  bool get dirty => _patch.isNotEmpty || (additional?.dirty ?? false);
  Map<String, Object?> get settings => {...?_base?.settings, ..._patch};
  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    await reload();
  }

  void change(Map<String, Object?> patch) {
    if (!ready || busy || _disposed) return;
    final next = {..._patch, ...patch};
    final baseline = _normalized(_base!.settings);
    next.removeWhere((key, value) => _same(value, baseline[key]));
    if (_same(next, _patch)) return;
    _record();
    _patch = next;
    _failed = false;
    notifyListeners();
  }

  void undo() {
    if (busy || _disposed || !canUndo) return;
    _redo.add((Map.of(_patch), additional?.edits));
    final previous = _undo.removeLast();
    _patch = previous.$1;
    if (previous.$2 != null) additional?.restore(previous.$2!);
    _failed = false;
    notifyListeners();
  }

  void redo() {
    if (busy || _disposed || !canRedo) return;
    _undo.add((Map.of(_patch), additional?.edits));
    final next = _redo.removeLast();
    _patch = next.$1;
    if (next.$2 != null) additional?.restore(next.$2!);
    _failed = false;
    notifyListeners();
  }

  void _clearHistory() {
    _undo.clear();
    _redo.clear();
  }

  void discard() {
    if (busy || _disposed) return;
    final needsReload = failed;
    _patch = {};
    additional?.discard();
    _clearHistory();
    _failed = false;
    conflict = false;
    notifyListeners();
    if (needsReload) {
      reload();
      additional?.reload();
    }
  }

  // Reload never silently rebases edits over unseen external changes.
  Future<void> reload() async {
    if (_busy || dirty || _disposed) return;
    _busy = true;
    _failed = false;
    conflict = false;
    notifyListeners();
    try {
      final next = await port.read();
      if (!_disposed) {
        _base = next;
        _clearHistory();
      }
    } on Object {
      if (!_disposed) _failed = true;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save({bool clearBrowserMemoryConfirmed = false}) async {
    if (!ready ||
        busy ||
        !dirty ||
        _disposed ||
        clearsBrowserMemory && !clearBrowserMemoryConfirmed) {
      return false;
    }
    _busy = true;
    _failed = false;
    conflict = false;
    notifyListeners();
    try {
      if (_patch.isNotEmpty) {
        final latest = await port.read();
        if (_disposed) return false;
        final baseline = _normalized(_base!.settings);
        final remote = _normalized(latest.settings);
        final merged = <String, Object?>{};
        for (final entry in _patch.entries) {
          merged[entry.key] = _merge(
            baseline[entry.key],
            entry.value,
            remote[entry.key],
          );
        }
        final next = await port.save(latest.withSettingsPatch(merged));
        if (_disposed) return false;
        _base = next;
        _patch = {};
      }
      if (additional?.dirty == true) {
        await additional!.save(
          clearBrowserMemoryConfirmed: clearBrowserMemoryConfirmed,
        );
        if (_disposed) return false;
      }
      _clearHistory();
      return !dirty && !failed;
    } on Object catch (error) {
      if (!_disposed) {
        _failed = true;
        conflict =
            error is _SettingsConflict ||
            error is BridgeClientException &&
                error.code == 'menuPreferences.revision_conflict';
      }
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _base = null;
    _patch = {};
    additional?.removeListener(_additionalChanged);
    additional?.dispose();
    _clearHistory();
    super.dispose();
  }
}

class _SettingsConflict implements Exception {}

Object? _merge(Object? base, Object? local, Object? remote) {
  if (_same(local, base)) return remote;
  if (_same(remote, base) || _same(remote, local)) return local;
  if (base is Map && local is Map && remote is Map) {
    return <String, Object?>{
      for (final key in {...base.keys, ...local.keys, ...remote.keys})
        key as String: _merge(base[key], local[key], remote[key]),
    };
  }
  throw _SettingsConflict();
}

Map<String, Object?> _normalized(Map<String, Object?> settings) => {
  ...settings,
  ...?MenuDisplayPreferences.fromSettings(settings)?.toSettingsPatch(),
  ...?MenuRestorePreferences.fromSettings(settings)?.toSettingsPatch(),
  ...?MenuSocialPreferences.fromSettings(settings)?.toSettingsPatch(),
  ...?MenuBrowserPreferences.fromSettings(settings)?.toSettingsPatch(),
  ...?MenuImagePreferences.fromSettings(settings)?.toSettingsPatch(),
  ...?MenuScreenshotPreferences.fromSettings(settings)?.toSettingsPatch(),
  'toolbar': MenuToolbarPreferences.parse(settings['toolbar'])?.toMap(),
};

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}
