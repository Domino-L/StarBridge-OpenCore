import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_shortcut_summary_state.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';

const original = MenuShortcutSettings(1, 'Alt+M', true, true, 'registered');
const changed = MenuShortcutSettings(2, 'Alt+K', true, true, 'registered');

class Port implements MenuShortcutSettingsPort {
  Completer<MenuShortcutSettings> pending = Completer();
  int reads = 0;
  bool failSave = false;
  @override
  Future<MenuShortcutSettings> readShortcut() {
    reads++;
    return pending.future;
  }

  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) async {
    if (failSave) throw StateError('synthetic failure');
    return value;
  }
}

void main() {
  test(
    'coalesces concurrent reads and does not overwrite save with stale read',
    () async {
      final port = Port();
      final shared = MenuShortcutSummaryState(port);
      final a = shared.readShortcut(), b = shared.readShortcut();
      expect(port.reads, 1);
      await shared.saveShortcut(changed);
      port.pending.complete(original);
      await Future.wait([a, b]);
      expect(shared.value, changed);
      shared.dispose();
    },
  );
  test(
    'failed save retains saved binding; failed read does not claim ready',
    () async {
      final port = Port();
      final shared = MenuShortcutSummaryState(port);
      final read = shared.readShortcut();
      port.pending.complete(original);
      await read;
      port.failSave = true;
      await expectLater(shared.saveShortcut(changed), throwsStateError);
      expect(shared.value, original);
      port.pending = Completer();
      final failed = shared.readShortcut();
      port.pending.completeError(StateError('synthetic failure'));
      await expectLater(failed, throwsStateError);
      expect(shared.value, isNull);
      shared.dispose();
    },
  );
  test('late read cannot revive disposed account state', () async {
    final port = Port();
    final shared = MenuShortcutSummaryState(port);
    var notifications = 0;
    shared.addListener(() => notifications++);
    final read = shared.readShortcut();
    shared.dispose();
    port.pending.complete(original);
    await read;
    expect(shared.value, isNull);
    expect(notifications, 0);
  });
}
