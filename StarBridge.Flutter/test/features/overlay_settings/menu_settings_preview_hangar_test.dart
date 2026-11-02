import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';

import '../friends/social_layout_test.dart' show app, size;
import '../tools/exec_hangar_test.dart' as hangar show Port, sample, origin;
import 'menu_settings_workspace_test.dart' show Port;

String countdown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('menu-hangar-countdown'))).data!;

// The draft loads, the preview rebuilds, and the widget reads its port.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
    'settings preview counts down the real hangar schedule, not a sample',
    (tester) async {
      size(tester, const Size(1600, 900));
      // Closed now; the next window opens 3h05m later (fixture window 1).
      final port = hangar.Port()
        ..snapshot = hangar.sample(
          phases: [
            ExecHangarPhase(
              hangar.origin,
              hangar.origin.add(const Duration(hours: 2)),
              false,
              0,
              5,
            ),
          ],
        );
      final draft = MenuSettingsDraft(Port());
      await tester.pumpWidget(
        app(MenuSettingsWorkspace(draft: draft, execHangar: () => port)),
      );
      await settle(tester);
      expect(port.reads, greaterThan(0), reason: 'reads the live schedule');
      // The sample was always "open, closes in ~20 minutes".
      expect(countdown(tester), startsWith('03:0'));

      // A failed read keeps the illustration instead of breaking the preview.
      await tester.pumpWidget(const SizedBox());
      port.fail = true;
      await tester.pumpWidget(
        app(MenuSettingsWorkspace(draft: draft, execHangar: () => port)),
      );
      await settle(tester);
      expect(countdown(tester), startsWith('00:'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
}
