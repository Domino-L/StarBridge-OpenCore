import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence_widgets.dart';
import 'package:starbridge_flutter/app/presence/projected_connection_mode.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import '../app/tray_quick_panel_test.dart' show app;

void main() {
  testWidgets('primary and tray choices offer offline and resume', (
    tester,
  ) async {
    final source = ValueNotifier(
      const ManualPresenceSnapshot(
        scope: 7,
        confirmedMode: PresenceVisibility.online,
        automaticKey: 'presence.online',
        canChange: true,
      ),
    );
    final modeSource = ValueNotifier(modeFact('online'));
    var writes = 0;
    final mode = ProjectedConnectionMode(
      source: modeSource,
      write: (_) async {
        writes++;
        modeSource.value = modeFact('offline');
      },
    );
    final presence = ManualPresenceController(
      source: source,
      connectionMode: mode,
      write: (_, _) async {},
    );
    final release = presence.bindOnlineRestore(() async => false);
    await tester.pumpWidget(app(ManualPresenceChoices(controller: presence)));
    expect(find.byKey(const Key('manual-presence-offline')), findsOneWidget);
    expect(find.text('恢复在线'), findsNothing);
    expect(presence.canEnterOffline, true);
    await tester.tap(find.byKey(const Key('manual-presence-offline')));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(presence.isOffline, true);
    expect(presence.selfKey, 'presence.manualOffline');
    expect(find.text('恢复在线'), findsOneWidget);
    expect(presence.canRestoreOnline, true);
    release();
    await tester.pumpWidget(const SizedBox());
    presence.dispose();
    mode.dispose();
    source.dispose();
    modeSource.dispose();
  });
  for (final state in ['offline', 'signInRequired', 'recoveryRequired']) {
    test('startup reads a saved $state mode without rewriting it', () async {
      final port = ModePort()..current = modeFact(state);
      final mode = ConnectionModeController(port);
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
      final presence = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      var restoreCalls = 0;
      final release = presence.bindOnlineRestore(() async {
        restoreCalls++;
        return true;
      });
      await mode.refresh();
      expect(port.reads, 1);
      expect(mode.snapshot.state.name, state);
      expect(
        mode.allowsOnlineTraffic,
        false,
        reason: 'a saved offline or unfinished mode pauses online traffic',
      );
      expect(presence.isOffline, state == 'offline');
      expect(
        presence.selfKey,
        state == 'offline' ? 'presence.manualOffline' : 'presence.unknown',
        reason: 'never fabricate online identity',
      );
      expect(await presence.selectOffline(), false);
      expect(presence.canRestoreOnline, true);
      expect(await presence.restoreOnline(), true);
      expect(restoreCalls, 1);
      expect(port.writes, isEmpty);
      release();
      presence.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    });
  }
  test('a Host without mode routes keeps ordinary online traffic', () async {
    final port = ModePort()
      ..supported = false
      ..current = const ConnectionModeSnapshot();
    final mode = ConnectionModeController(port);
    final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
    final presence = ManualPresenceController(
      source: source,
      connectionMode: mode,
    );
    await mode.refresh();
    expect(mode.snapshot.state, ConnectionModeState.unsupported);
    expect(mode.allowsOnlineTraffic, true);
    expect(presence.canEnterOffline, false);
    expect(presence.isOffline, false);
    expect(presence.selfKey, 'presence.unknown');
    expect(await presence.selectOffline(), false);
    expect(port.writes, isEmpty);
    presence.dispose();
    source.dispose();
    mode.dispose();
    await port.events.close();
  });
}
