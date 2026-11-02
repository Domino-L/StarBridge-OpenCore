import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/desktop_notification_test_button.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';

import 'interaction_batch3ae_test.dart' show mount;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class HeldDesktop implements DesktopNotificationPort {
  final answer = Completer<bool>();
  int calls = 0, clears = 0;
  @override
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  }) {
    calls++;
    return answer.future;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite notification row exposes one reader action', (t) async {
      final handle = t.ensureSemantics();
      var calls = 0;
      await mount(
        t,
        NotificationToggleRow(
          settingKey: const Key('row'),
          value: false,
          enabled: true,
          titleKey: 'settings.notification.local.enabled',
          descriptionKey: 'settings.notification.local.enabledDescription',
          onChanged: (_) async {
            calls++;
            return true;
          },
        ),
        suite,
      );
      final node = t.getSemantics(find.byKey(const Key('row')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await t.pump();
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    testWidgets('$suite preview exposes reader activation', (t) async {
      final handle = t.ensureSemantics();
      var calls = 0;
      await mount(
        t,
        SingleChildScrollView(
          child: NotificationPreviewPanel(
            settings: InMemoryNotificationSettingsAdapter.forReview()
                .current
                .settings!,
            enabled: true,
            onSave: (_) async {
              calls++;
              return true;
            },
          ),
        ),
        suite,
      );
      final node = t.getSemantics(
        find.byKey(const Key('notification-preview-hiddenDetails')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await t.pump();
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    testWidgets('$suite port replacement retires pending desktop attempt', (
      t,
    ) async {
      final old = HeldDesktop(), next = HeldDesktop();
      var current = old;
      late StateSetter update;
      await mount(
        t,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return DesktopNotificationTestButton(port: current, enabled: true);
          },
        ),
        suite,
      );
      await t.tap(find.byKey(const Key('notification-desktop-test')));
      await t.pump();
      expect(old.calls, 1);
      update(() => current = next);
      await t.pump();
      // Native branch before integration; original issue is the owner slot,
      // not whether a particular painted button is present.
      final button = find.byKey(const Key('notification-desktop-test'));
      final w = t.widget(button);
      if (w is OutlinedButton) expect(w.onPressed, isNotNull);
      await t.tap(button);
      await t.pump();
      expect(next.calls, 1);
      next.answer.complete(false);
      await t.pump();
      old.answer.complete(true);
      await t.pump();
      expect(find.textContaining('已提交桌面提醒卡'), findsNothing);
      expect(old.clears, greaterThan(0));
      await t.pumpWidget(const SizedBox());
    });
  }
}
