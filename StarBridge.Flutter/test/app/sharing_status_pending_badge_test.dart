import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_indicator.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import 'sharing_status_notice_test.dart' show NoticePrivacy;
import '../features/settings/local_privacy_page_test.dart' show app;

// User report 2026-10-22: right after launch the title bar showed
// "共享状态待确认". A pending state is never shown; only a confirmed one is.
void main() {
  testWidgets('no pending badge while the sharing state is unconfirmed', (
    tester,
  ) async {
    final port = NoticePrivacy()
      ..state = 'applied'
      ..failStatus = true;
    final controller = LocalPrivacyController(port);
    final monitor = SharingStatusMonitor(controller: controller);
    await tester.pumpWidget(
      app(SharingStatusIndicator(monitor: monitor, onOpenSettings: () {})),
    );
    await tester.pumpAndSettle();
    expect(monitor.indicator, SharingIndicatorState.unknown);
    expect(find.text('共享状态待确认'), findsNothing);
    expect(find.byKey(const Key('sharing-status-indicator')), findsNothing);
    port.failStatus = false;
    await controller.refreshPublication();
    await tester.pumpAndSettle();
    expect(find.text('共享中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    controller.dispose();
  });
}
