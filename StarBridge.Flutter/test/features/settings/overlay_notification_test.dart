import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/local_notification_listener.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';

import 'local_notification_test.dart' show Fixture;
import 'desktop_notification_test.dart' show DesktopFake;
import '../friends/social_layout_test.dart' show app, size, loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test('overlay capability and saved preference round trip; old Host remains unavailable', () async {
    final f = Fixture();
    await f.start();
    addTearDown(f.close);
    expect(
      f.module.projection.value.settings!.overlayDeliveryAvailable,
      isFalse,
    );
    await f.module.save(f.module.projection.value.settings!);
    expect(f.requests.last.payload.containsKey('overlayEnabled'), isFalse);
    f.value['overlayEnabled'] = true;
    await f.module.refresh();
    final value = f.module.projection.value.settings!;
    expect(value.overlayDeliveryAvailable, isTrue);
    expect(value.channels.overlayEnabled, isTrue);
    expect(
      await f.module.save(
        value.copyWith(
          channels: value.channels.copyWith(overlayEnabled: false),
        ),
      ),
      isTrue,
    );
    expect(f.requests.last.payload['overlayEnabled'], false);
    expect(
      f.module.projection.value.settings!.channels.overlayEnabled,
      isFalse,
    );
    f.value['overlayEnabled'] = 'true';
    expect((await f.adapter.read()).settings, isNull);
  });

  testWidgets(
    'native overlay submission prevents foreground and desktop duplicates',
    (tester) async {
      size(tester, const Size(1200, 850));
      final f = Fixture();
      f.value.addAll({'overlayEnabled': true, 'windowsEnabled': true});
      await f.start();
      addTearDown(f.close);
      final desktop = DesktopFake();
      await tester.pumpWidget(
        app(
          LocalNotificationListener(
            events: f.adapter.reminders,
            settings: f.module,
            desktop: desktop,
            child: const SizedBox(),
          ),
        ),
      );
      for (final state in [
        AppLifecycleState.resumed,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        f.adapter.onRoomReminder({
          'schemaVersion': 1,
          'revision': 0,
          'invitations': 1,
          'applications': 0,
          'desktopEligible': true,
          'overlayHandled': true,
        });
        await tester.pumpAndSettle();
        expect(desktop.shown, isEmpty);
        expect(find.text('房间提醒'), findsNothing);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets(
    'ordinary mode reuses the existing overlay toggle only with real capability',
    (tester) async {
      size(tester, const Size(1200, 850));
      final f = Fixture();
      await f.start();
      addTearDown(f.close);
      Future<void> show() async {
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: NotificationChannelPanel(
                settings: f.module.projection.value.settings!,
                enabled: true,
                showSound: false,
                onSave: f.module.save,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(
        find.byKey(const Key('notification-channel-overlay')),
        findsNothing,
      );
      f.value['overlayEnabled'] = true;
      await f.module.refresh();
      await show();
      expect(
        find.byKey(const Key('notification-channel-overlay')),
        findsOneWidget,
      );
      expect(find.textContaining('不会自动打开浮层'), findsOneWidget);
      expect(tester.takeException(), isNull);
      size(tester, const Size(390, 850));
      await show();
      expect(tester.takeException(), isNull);
    },
  );
}
