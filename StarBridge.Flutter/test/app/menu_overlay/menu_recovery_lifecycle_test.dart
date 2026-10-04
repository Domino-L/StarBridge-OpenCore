import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_recovery.dart';
import 'package:starbridge_flutter/platform/window/menu_recovery_lifecycle.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import 'menu_recovery_window_test.dart' show Recovery, Preferences;

class _PendingRecovery extends Recovery {
  final pending = Completer<MenuRecoverySession>();
  @override
  Future<MenuRecoverySession> begin() => pending.future;
}

Preferences preferences(String mode) =>
    Preferences()
      ..value = MenuWindowPreferences(
        3,
        const {
          'version': 1,
          'panels': [
            {
              'id': 'browser',
              'bounds': [20, 40, 500, 350],
            },
          ],
          'open': ['friends', 'browser'],
        },
        {
          ...MenuWindowPreferences.defaults.settings,
          'restoreDesktop': true,
          'restoreAfterRestart': true,
          'crashRecovery': mode,
        },
      );

Future<MenuRecoveryOpening> prepare(
  MenuRecoveryLifecycle lifecycle,
  Preferences store,
  Recovery recovery, {
  bool Function()? current,
}) => lifecycle.prepare(
  live: true,
  preferences: store.value,
  preferencesPort: store,
  recovery: recovery,
  isCurrent: current ?? () => true,
);

void main() {
  for (final mode in ['ask', 'restore', 'startClean']) {
    for (final interrupted in [false, true]) {
      test(
        '$mode with verified interrupted=$interrupted consumes only allowed layout',
        () async {
          final store = preferences(mode),
              recovery = Recovery()..interrupted = interrupted;
          final lifecycle = MenuRecoveryLifecycle();
          final original = store.value;
          final result = await prepare(lifecycle, store, recovery);
          final clean = interrupted && mode == 'startClean';
          expect(result.pending, interrupted && mode == 'ask');
          expect(result.failed, false);
          expect(
            result.presentation.layout['open'],
            clean || result.pending ? isEmpty : ['friends', 'browser'],
          );
          expect(store.saved, hasLength(clean ? 1 : 0));
          expect(
            result.preferences!.layout['panels'],
            original.layout['panels'],
          );
          expect(result.preferences!.settings, original.settings);
          expect(recovery.finished, 0);
          lifecycle.visible(live: true, pending: result.pending);
          if (!result.pending) {
            final reopened = await prepare(lifecycle, store, recovery);
            expect(reopened.pending, false);
            expect(store.saved, hasLength(clean ? 1 : 0));
          }
          await lifecycle.finish();
          expect(recovery.finished, 1);
        },
      );
    }
    test(
      '$mode never treats unknown marker as permission to restore or delete',
      () async {
        final store = preferences(mode), recovery = Recovery()..fail = true;
        final original = store.value;
        final result = await prepare(MenuRecoveryLifecycle(), store, recovery);
        expect(result.pending, true);
        expect(result.failed, true);
        expect(result.presentation.layout['open'], isEmpty);
        expect(result.preferences, same(original));
        expect(store.saved, isEmpty);
      },
    );
  }
  test(
    'automatic clean failure preserves original and retries with CAS',
    () async {
      final store = preferences('startClean')..fail = true;
      final recovery = Recovery(), lifecycle = MenuRecoveryLifecycle();
      final original = store.value;
      final failed = await prepare(lifecycle, store, recovery);
      expect(failed.pending, true);
      expect(failed.preferences, same(original));
      expect(store.saved, isEmpty);
      store.fail = false;
      final retried = await prepare(lifecycle, store, recovery);
      expect(retried.pending, false);
      expect(retried.preferences!.layout['open'], isEmpty);
      expect(store.saved, hasLength(1));
    },
  );
  test(
    'late marker after owner change neither writes nor completes old session',
    () async {
      final store = preferences('startClean'), recovery = _PendingRecovery();
      final lifecycle = MenuRecoveryLifecycle();
      var current = true;
      final task = prepare(lifecycle, store, recovery, current: () => current);
      current = false;
      recovery.pending.complete(MenuRecoverySession('b' * 32, true));
      final result = await task;
      expect(result.presentation.layout['open'], isEmpty);
      expect(store.saved, isEmpty);
      await lifecycle.finish();
      expect(recovery.finished, 0);
    },
  );
  test(
    'revision changes during automatic clean cannot erase new layout',
    () async {
      final store = preferences('startClean')..blocked = Completer<void>();
      final lifecycle = MenuRecoveryLifecycle();
      final task = prepare(lifecycle, store, Recovery());
      await Future<void>.delayed(Duration.zero);
      store.value = MenuWindowPreferences(9, const {
        'version': 1,
        'panels': [],
        'open': ['rooms'],
      }, store.value.settings);
      store.blocked!.complete();
      final result = await task;
      expect(result.pending, true);
      expect(result.failed, true);
      expect(store.value.layout['open'], ['rooms']);
      expect(store.saved, isEmpty);
    },
  );
}
