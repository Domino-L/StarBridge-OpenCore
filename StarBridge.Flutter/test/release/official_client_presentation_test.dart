import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/settings/general_settings_interaction.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/first_use_setup_entry.dart';

import '../app/first_use_setup_composition_test.dart' show pump;
import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;


void main() {
  testWidgets('every profile keeps the first-use guide entry', (tester) async {
    var calls = 0;
    await pump(
      tester,
      (_) => FirstUseSetupEntry(
        open: (_) async {
          calls++;
        },
        child: Builder(
          builder: (context) => Text(
            FirstUseSetupEntry.of(context) == null ? 'no guide' : 'guide',
          ),
        ),
      ),
    );
    expect(find.text('guide'), findsOneWidget);
    expect(calls, 0);
  });
  for (final style in InteractionStyle.values) {
    test('saved $style renders as saved in every profile', () {
      final preferences = AppPreferences.defaults.copyWith(
        interactionStyle: style,
      );
      final effective = interactionSuiteFromName(
        preferences.interactionStyle.name,
      );
      expect(effective.name, style.name);
      expect(
        preferences.interactionStyle,
        style,
        reason: 'presentation restrictions must not rewrite the saved choice',
      );
    });
  }
  testWidgets('every profile offers the style selection without saving on its own', (
    tester,
  ) async {
    var writes = 0;
    await pump(
      tester,
      (_) => GeneralSettingsInteraction(
        value: InteractionStyle.rail,
        enabled: true,
        onChanged: (_) async {
          writes++;
          return true;
        },
      ),
    );
    expect(find.byKey(const Key('general-interaction-style')), findsOneWidget);
    expect(writes, 0);
  });
  test(
    'every profile reads an existing mode choice without rewriting it',
    () async {
      final port = ModePort();
      final mode = ConnectionModeController(port);
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
      final controller = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      await mode.refresh();
      expect(controller.canEnterOffline, true);
      port.current = modeFact('offline');
      await mode.refresh();
      expect(controller.isOffline, true);
      expect(controller.selfKey, 'presence.manualOffline');
      final release = controller.bindOnlineRestore(() async => false);
      expect(controller.canRestoreOnline, true);
      port.current = modeFact('signInRequired');
      await mode.refresh();
      expect(controller.canRestoreOnline, true);
      expect(controller.canEnterOffline, false);
      expect(mode.allowsOnlineTraffic, false);
      expect(
        port.writes,
        isEmpty,
        reason: 'reading a mode never writes one back',
      );
      release();
      controller.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
}
