import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_indicator.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import '../features/settings/local_privacy_page_test.dart' show app;
import 'sharing_status_notice_test.dart' show NoticePrivacy;

void main() {
  testWidgets(
    'confirmed offline suppresses sharing fault and retry until online',
    (tester) async {
      final port = NoticePrivacy()..failStatus = true;
      final privacy = LocalPrivacyController(port);
      final modePort = ModePort();
      final mode = ConnectionModeController(modePort);
      await tester.runAsync(mode.refresh);
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 7,
          confirmedMode: PresenceVisibility.online,
        ),
      );
      final presence = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      final monitor = SharingStatusMonitor(
        controller: privacy,
        presence: presence,
      );
      await tester.pumpWidget(
        app(
          Column(
            children: [
              SharingStatusNotice(status: monitor, onOpenSettings: () {}),
              SharingStatusIndicator(monitor: monitor, onOpenSettings: () {}),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await privacy.refreshPublication();
      await privacy.refreshPublication();
      await tester.pumpAndSettle();
      expect(find.text('暂时无法读取共享状态'), findsOneWidget);
      expect(find.text('共享状态待确认'), findsNothing);

      modePort.current = modeFact('offline');
      await tester.runAsync(mode.refresh);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      expect(find.text('共享状态待确认'), findsNothing);
      expect(monitor.canRetry, false);
      final actions = port.actions.length;
      await monitor.retry();
      await tester.pump(const Duration(seconds: 40));
      expect(
        port.actions.length,
        actions,
        reason: 'intentional offline must not poll',
      );

      modePort.current = modeFact('online');
      await tester.runAsync(mode.refresh);
      await tester.pumpAndSettle();
      expect(find.text('暂时无法读取共享状态'), findsOneWidget);
      expect(find.text('共享状态待确认'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      monitor.dispose();
      privacy.dispose();
      presence.dispose();
      source.dispose();
      mode.dispose();
      await modePort.events.close();
    },
  );
}
