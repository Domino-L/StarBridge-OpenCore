import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_display_editor.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../friends/social_layout_test.dart' show app, size;

void main() {
  testWidgets(
    'first menu read survives brief Host latency without manual reload',
    (tester) async {
      size(tester, const Size(1100, 800));
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final timers = <Timer>[];
      int reads = 0;
      final host = pair.host.incoming.listen((request) {
        if (request.name != 'applicationPreferences.menu.get') return;
        reads++;
        void reply() {
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: request.sessionGeneration,
                status: 'ok',
                payload: MenuWindowPreferences.defaults.toMap(),
              ),
            ),
          );
        }

        if (reads == 1) {
          timers.add(Timer(const Duration(milliseconds: 3200), reply));
        } else {
          reply();
        }
      });
      final draft = MenuSettingsDraft(BridgeMenuWindowPreferences(session));
      await tester.pumpWidget(app(MenuSettingsWorkspace(draft: draft)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('menu-settings-expand')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));
      final automatic =
          draft.ready && find.byType(MenuDisplayEditor).evaluate().isNotEmpty;
      // Keep the manual recovery in the repro to distinguish unreadable settings
      // from a dropped first read. No writes or real account data are involved.
      if (!automatic) {
        final reload = draft.reload();
        await tester.pump();
        await tester.pump();
        await reload;
      }
      expect(
        draft.ready,
        true,
        reason: 'the same settings can be read manually',
      );
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
      for (final timer in timers) {
        timer.cancel();
      }
      unawaited(host.cancel());
      unawaited(session.close());
      unawaited(pair.host.close());
      expect(
        automatic,
        true,
        reason: 'settings must appear without pressing Reload',
      );
    },
  );
}
