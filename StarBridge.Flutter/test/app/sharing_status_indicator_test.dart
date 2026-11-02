import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_indicator.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_top_bar.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'sharing_status_notice_test.dart' show NoticePrivacy;
import '../features/settings/local_privacy_page_test.dart' show app, viewport;

void main() {
  testWidgets(
    'indicator fits alongside real account chrome at supported widths',
    (tester) async {
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
      );
      final controller = LocalPrivacyController(
        NoticePrivacy()..state = 'withdrawalPending',
      );
      final monitor = SharingStatusMonitor(controller: controller);
      for (final width in [900.0, 1280.0, 1440.0, 2560.0]) {
        viewport(tester, Size(width, 900));
        final mode = ShellLayoutResolver.resolve(width);
        await tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: width - 224,
                child: ShellTopBar(
                  selected: composition.features.byRoute('/settings/privacy'),
                  topBarDestinations: composition.features.inRegion(
                    NavigationRegion.topBar,
                  ),
                  accountMenuDestinations: composition.features.inRegion(
                    NavigationRegion.accountMenu,
                  ),
                  projection: InMemoryShellChrome.connectedProjection,
                  shellChrome: composition.shellChrome,
                  mode: mode,
                  onSelect: (_) {},
                  onAccountLogin: () {},
                  onAccountLogout: () {},
                  onAccountIssueAction: () {},
                  windowChrome: composition.windowChrome,
                  sharingIndicator: SharingStatusIndicator(
                    monitor: monitor,
                    compact: mode != ShellLayoutMode.wide,
                    onOpenSettings: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('sharing-status-indicator')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      controller.dispose();
      composition.dispose();
    },
  );
  testWidgets(
    'persistent indicator follows receipts, not drafts or banner grace',
    (tester) async {
      final port = NoticePrivacy()..state = 'applied';
      final controller = LocalPrivacyController(port);
      final monitor = SharingStatusMonitor(controller: controller);
      var opened = 0;
      await tester.pumpWidget(
        app(
          SharingStatusIndicator(
            monitor: monitor,
            onOpenSettings: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('共享中'), findsOneWidget);
      controller.edit(controller.draft!.copyWith(publicationEnabled: false));
      await tester.pump();
      expect(find.text('共享中'), findsOneWidget);
      port.state = 'withdrawalPending';
      await controller.refreshPublication();
      await tester.pump();
      expect(find.text('正在停止共享'), findsOneWidget);
      port.state = 'withdrawn';
      await controller.refreshPublication();
      await tester.pump();
      expect(find.text('共享已关闭'), findsOneWidget);
      port.failStatus = true;
      await controller.refreshPublication();
      await tester.pump();
      expect(find.text('共享状态待确认'), findsNothing);
      port.failStatus = false;
      port.state = 'applied';
      await controller.refreshPublication();
      await tester.pump();
      expect(find.text('共享中'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sharing-status-indicator')));
      expect(opened, 1);
      expect(port.actions.every((a) => a == 'status'), isTrue);
      expect(port.writes, 0);
      port.snapshot = const LocalPrivacySnapshot(revision: 0);
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('共享中'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      controller.dispose();
    },
  );

  testWidgets('compact indicator remains accessible and navigable', (
    tester,
  ) async {
    viewport(tester, const Size(430, 900));
    final controller = LocalPrivacyController(
      NoticePrivacy()..state = 'withdrawn',
    );
    final monitor = SharingStatusMonitor(controller: controller);
    var opened = false;
    await tester.pumpWidget(
      app(
        SharingStatusIndicator(
          monitor: monitor,
          compact: true,
          onOpenSettings: () => opened = true,
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is StarBridgeTooltip &&
            widget.message == '共享已关闭 · 查看同步与隐私',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sharing-status-indicator')));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    controller.dispose();
  });
}
