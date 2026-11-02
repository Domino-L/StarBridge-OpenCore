import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_action_validation.dart';

import '../../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;

void main() {
  test(
    'friends forwards only exact bounded resumeOnline without visibility value',
    () {
      const good = {
        'opening': 7,
        'action': 'resumeOnline',
        'key': 'self1',
        'value': '',
      };
      expect(validMenuFriendsAction(good, 7), true);
      for (final bad in [
        {'opening': 6},
        {'action': 'resumeOnline.extra'},
        {'value': 'online'},
        {'key': 7},
        {'key': 'x' * 65},
      ]) {
        expect(validMenuFriendsAction({...good, ...bad}, 7), false);
      }
    },
  );

  test('one primary restore remains busy over generation change; no presence write', () async {
    final port = ModePort()..current = modeFact('offline');
    final mode = ConnectionModeController(port);
    final source = ValueNotifier(
      const ManualPresenceSnapshot(scope: 7, canChange: true),
    );
    var writes = 0, restores = 0;
    final control = ManualPresenceController(
      source: source,
      connectionMode: mode,
      write: (_, _) async {
        writes++;
      },
    );
    addTearDown(() async {
      control.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    });
    await mode.refresh();
    final pending = Completer<bool>();
    final release = control.bindOnlineRestore(() {
      restores++;
      return pending.future;
    });
    expect(control.canRestoreOnline, true);
    final restoring = control.restoreOnline();
    expect(restores, 1);
    source.value = const ManualPresenceSnapshot(scope: 8, canChange: true);
    expect(control.busy, true);
    expect(control.canRestoreOnline, false);
    expect(await control.restoreOnline(), false);
    pending.complete(true);
    expect(await restoring, true);
    expect(writes, 0);
    expect(port.writes, isEmpty);
    release();
    expect(control.canRestoreOnline, false);
  });

  test(
    'restore captures original handler before listener can replace it',
    () async {
      final port = ModePort()..current = modeFact('offline');
      final mode = ConnectionModeController(port);
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
      final control = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      addTearDown(() async {
        control.dispose();
        source.dispose();
        mode.dispose();
        await port.events.close();
      });
      await mode.refresh();
      var first = 0, second = 0, replaced = false;
      final release = control.bindOnlineRestore(() async {
        first++;
        return true;
      });
      control.addListener(() {
        if (control.busy && !replaced) {
          replaced = true;
          control.bindOnlineRestore(() async {
            second++;
            return true;
          });
        }
      });
      expect(await control.restoreOnline(), true);
      expect(first, 1);
      expect(second, 0);
      release();
      expect(control.canRestoreOnline, true);
    },
  );
}
