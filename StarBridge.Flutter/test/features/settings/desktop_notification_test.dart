import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/local_notification_listener.dart';
import 'package:starbridge_flutter/features/settings/desktop_notification_test_button.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';

import 'local_notification_test.dart' show Fixture;
import '../friends/social_layout_test.dart' show app, size, loadFonts;

class DesktopFake implements DesktopNotificationPort {
  final shown = <String>[];
  int clears = 0;
  bool submitted = true;
  bool? lastTest;
  @override
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  }) async {
    shown.add('$title|$message');
    lastTest = test;
    return submitted;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  test(
    'older Host keeps desktop unavailable and receives no unsupported field',
    () async {
      final f = Fixture();
      f.value.remove('windowsEnabled');
      await f.start();
      addTearDown(f.close);
      final value = f.module.projection.value.settings!;
      expect(value.desktopDeliveryAvailable, isFalse);
      expect(await f.module.save(value), isTrue);
      expect(f.requests.last.payload.containsKey('windowsEnabled'), isFalse);
    },
  );
  test(
    'native port returns actual submission and gracefully handles old Runner',
    () async {
      const channel = MethodChannel('starbridge/application-lifecycle');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const port = RunnerDesktopNotificationPort();
      expect(await port.show('title', 'body'), isTrue);
      expect(calls.single.arguments, {
        'title': 'title',
        'message': 'body',
        'test': false,
      });
      await port.clear();
      expect(calls.last.method, 'clearDesktopNotification');
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await port.show('title', 'body'), isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await port.show('title', 'body'), isFalse);
      await port.clear();
    },
  );
  testWidgets(
    'desktop obeys Host eligibility, local preference, preview and invalidation',
    (tester) async {
      size(tester, const Size(1200, 850));
      final f = Fixture();
      await f.start();
      addTearDown(f.close);
      final port = DesktopFake();
      final initial = f.module.projection.value.settings!;
      await f.module.save(
        initial.copyWith(
          channels: initial.channels.copyWith(
            inAppEnabled: false,
            windowsDesktopEnabled: true,
          ),
        ),
      );
      await tester.pumpWidget(
        app(
          LocalNotificationListener(
            events: f.adapter.reminders,
            settings: f.module,
            desktop: port,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void emit({bool eligible = true, int? revision}) =>
          f.adapter.onRoomReminder({
            'schemaVersion': 1,
            'revision': revision ?? f.value['revision'],
            'invitations': 2,
            'applications': 1,
            'desktopEligible': eligible,
          });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      emit();
      await tester.pumpAndSettle();
      expect(port.shown, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      emit(eligible: false);
      emit(revision: 0);
      await tester.pumpAndSettle();
      expect(port.shown, isEmpty);
      emit();
      await tester.pumpAndSettle();
      expect(port.shown.single, '房间提醒|有新的房间消息，请前往房间查看。');
      expect(port.lastTest, isFalse);
      final value = f.module.projection.value.settings!;
      await f.module.save(
        value.copyWith(previewMode: NotificationPreviewMode.hiddenDetails),
      );
      final clears = port.clears;
      emit();
      await tester.pumpAndSettle();
      expect(port.shown.last, isNot(contains('房间')));
      expect(port.shown.last, isNot(contains('2')));
      await f.module.save(
        value.copyWith(
          channels: value.channels.copyWith(windowsDesktopEnabled: false),
        ),
      );
      emit();
      await tester.pumpAndSettle();
      expect(port.shown, hasLength(2));
      expect(port.clears, greaterThan(clears));
      f.adapter.onRoomReminder(null); // Malformed events never deliver.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(port.shown, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('manual test is opt-in and reports submission, not display', (
    tester,
  ) async {
    final port = DesktopFake();
    await tester.pumpWidget(
      app(DesktopNotificationTestButton(port: port, enabled: false)),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('notification-desktop-test'));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    await tester.pumpWidget(
      app(DesktopNotificationTestButton(port: port, enabled: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(port.lastTest, isTrue);
    expect(find.textContaining('已提交桌面提醒卡'), findsOneWidget);
    port.submitted = false;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('暂未显示提醒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(port.clears, greaterThan(0));
  });
}
