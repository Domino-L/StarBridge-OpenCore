import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_panel.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_monitor_panel.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_schedule.dart';

import '../../features/tools/exec_hangar_test.dart' show ExperiencePort, app;
import '../../features/friends/social_layout_test.dart' show size;
import '../../features/tools/exec_hangar_presets.dart';

void main() {
  for (final width in [360.0, 520.0, 900.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      testWidgets('prepared menu hangar $width ${locale.toLanguageTag()}', (
        tester,
      ) async {
        size(tester, Size(width, 620));
        final port = ExperiencePort();
        await tester.pumpWidget(
          app(MenuExecHangarPanel(port: port), locale, AppearanceMode.dark),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('exec-countdown')), findsOneWidget);
        expect(find.byKey(const Key('exec-only-next')), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(ExecHangarMonitorPanel)).dy,
          lessThan(tester.getTopLeft(find.byType(ExecHangarSchedule)).dy),
          reason: 'Monitor controls precede the full chronological schedule',
        );
        expect(port.starts, 0);
        expect(port.saves, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'menu hide retains draft and stops reads, close checks the draft',
    (tester) async {
      size(tester, const Size(520, 760));
      final port = ExperiencePort();
      final cached = CachedExecHangar(port);
      final key = GlobalKey<MenuExecHangarPanelState>();
      Widget surface(bool visible) => app(
        Offstage(
          offstage: !visible,
          child: MenuExecHangarPanel(key: key, port: cached, visible: visible),
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      );
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      expect(await key.currentState!.confirmClose(), true);
      await pickExecPreset(tester, execBeforeOpen, 15);
      final reads = port.reads;
      await tester.pumpWidget(surface(false));
      await tester.pump(const Duration(minutes: 2));
      expect(
        port.reads,
        reads,
        reason: 'Hidden content makes no presentation reads',
      );
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      expect(port.reads, reads + 1);
      expect(
        execPresetShown(tester, execBeforeOpen),
        15,
      );
      var closing = key.currentState!.confirmClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(await closing, false);
      closing = key.currentState!.confirmClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃并离开'));
      await tester.pumpAndSettle();
      expect(await closing, true);
      expect(port.saves, 0);
      expect(
        port.starts,
        0,
        reason: 'Hide and close never change Host monitoring',
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
