import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';

void main() {
  test('module applies one revisioned semantic notification update', () async {
    final adapter = InMemoryNotificationSettingsAdapter.forReview();
    final module = createNotificationSettingsModule(adapter);
    addTearDown(module.dispose);

    await module.initialize();
    final original = module.projection.value;
    expect(original.availability, NotificationSettingsAvailability.available);
    expect(original.revision, 11);

    final saved = await module.save(
      original.settings!.copyWith(
        previewMode: NotificationPreviewMode.hiddenDetails,
      ),
    );

    expect(saved, isTrue);
    expect(module.projection.value.revision, 12);
    expect(
      module.projection.value.settings!.previewMode,
      NotificationPreviewMode.hiddenDetails,
    );
    expect(adapter.current.revision, 12);
  });

  test('failed writes preserve last confirmed notification values', () async {
    final adapter = InMemoryNotificationSettingsAdapter.forReview();
    final module = createNotificationSettingsModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();
    final original = module.projection.value.settings!;
    adapter.failNextUpdate = true;

    final saved = await module.save(
      original.copyWith(
        channels: original.channels.copyWith(windowsDesktopEnabled: false),
      ),
    );

    expect(saved, isFalse);
    expect(module.projection.value.settings, same(original));
    expect(
      module.projection.value.failure,
      NotificationSettingsFailure.writeFailed,
    );
    expect(module.projection.value.canEdit, isTrue);
  });

  test('new-device and migrated WPF defaults remain explicit', () {
    final value = NotificationSettingsValue.reviewDefaults(
      sourceRules: const [],
    );

    expect(value.channels.windowsDesktopEnabled, isTrue);
    expect(value.channels.directMessageWindowsEnabled, isFalse);
    expect(
      value.channels.desktopPosition,
      DesktopNotificationPosition.bottomRight,
    );
    expect(
      value.channels.sound.availability,
      NotificationSoundAvailability.notImplemented,
    );
    expect(value.previewMode, NotificationPreviewMode.sourceOnly);
    expect(value.playerActivity.enabled, isFalse);
    expect(value.playerActivity.includeOfficialFleet, isTrue);
    expect(value.playerActivity.notifyOnline, isTrue);
    expect(value.playerActivity.notifyOffline, isFalse);
    expect(value.playerActivity.notifyGameStarted, isTrue);
    expect(value.playerActivity.notifyGameStopped, isFalse);
    expect(value.continuousPlay.enabled, isTrue);
    expect(value.continuousPlay.firstReminderMinutes, 120);
    expect(value.continuousPlay.repeatReminderMinutes, 120);
  });
}
