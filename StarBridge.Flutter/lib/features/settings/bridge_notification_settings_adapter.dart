import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import 'notification_settings_models.dart';
import 'notification_settings_port.dart';
import 'bridge_notification_sources.dart';

final class LocalRoomReminder {
  const LocalRoomReminder(
    this.revision,
    this.invitations,
    this.applications, {
    this.desktopEligible = false,
    this.overlayHandled = false,
    this.desktopTicket,
  });
  final int revision, invitations, applications;
  final bool desktopEligible;
  final bool overlayHandled;
  final String? desktopTicket;
}

final class BridgeNotificationSettingsAdapter
    implements NotificationSettingsPort {
  BridgeNotificationSettingsAdapter(this.session) {
    notificationSourceDeliveryEpoch(session).addListener(_clearSourceReminder);
    _subscription = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _reminders.add(null);
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession session;
  final _reminders = StreamController<LocalRoomReminder?>.broadcast(sync: true);
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<Object?> _subscription;
  Stream<LocalRoomReminder?> get reminders => _reminders.stream;
  void _clearSourceReminder() {
    if (!_reminders.isClosed) _reminders.add(null);
  }

  void onRoomReminder(Object? raw) {
    if (_reminders.isClosed || raw is! Map || raw['schemaVersion'] != 1) return;
    final revision = raw['revision'],
        invitations = raw['invitations'],
        applications = raw['applications'];
    if (revision is! int ||
        revision < 0 ||
        invitations is! int ||
        applications is! int ||
        invitations < 0 ||
        applications < 0 ||
        invitations + applications <= 0 ||
        invitations + applications > 512) {
      return;
    }
    if (raw.containsKey('desktopEligible') && raw['desktopEligible'] is! bool) {
      return;
    }
    if (raw.containsKey('overlayHandled') && raw['overlayHandled'] is! bool) {
      return;
    }
    final ticket = raw['desktopTicket'];
    if (ticket != null &&
        (ticket is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(ticket))) {
      return;
    }
    _reminders.add(
      LocalRoomReminder(
        revision,
        invitations,
        applications,
        desktopEligible: raw['desktopEligible'] == true,
        overlayHandled: raw['overlayHandled'] == true,
        desktopTicket: ticket as String?,
      ),
    );
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;
  NotificationSettingsFailure _failure(Object error, bool write) =>
      switch (error) {
        BridgeClientException(code: 'notificationSettings.write_conflict') =>
          NotificationSettingsFailure.writeConflict,
        BridgeClientException(
          code: 'host.capability_missing' || 'bridge.disconnected',
        ) =>
          NotificationSettingsFailure.hostUnavailable,
        FormatException() => NotificationSettingsFailure.invalidResponse,
        _ =>
          write
              ? NotificationSettingsFailure.writeFailed
              : NotificationSettingsFailure.readFailed,
      };
  Future<NotificationSettingsSnapshot> _call(
    String name, [
    Map<String, Object?> fields = const {},
  ]) async {
    if (!session.hostCapabilities.contains('notificationSettings.$name')) {
      return const NotificationSettingsSnapshot.unavailable();
    }
    final response = await session.request(
      'notificationSettings.$name',
      payload: {'schemaVersion': 1, ...fields},
    );
    final data = response.payload;
    final revision = data['revision'], enabled = data['inAppEnabled'];
    if (data['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        enabled is! bool ||
        (data.containsKey('windowsEnabled') &&
            data['windowsEnabled'] is! bool) ||
        (data.containsKey('directMessageWindowsEnabled') &&
            data['directMessageWindowsEnabled'] is! bool) ||
        (data.containsKey('overlayEnabled') &&
            data['overlayEnabled'] is! bool)) {
      throw const FormatException();
    }
    final positions = DesktopNotificationPosition.values.where(
      (v) => v.name == data['position'],
    );
    final previews = NotificationPreviewMode.values.where(
      (v) => v.name == data['preview'],
    );
    if (positions.length != 1 || previews.length != 1) {
      throw const FormatException();
    }
    return NotificationSettingsSnapshot.available(
      revision: revision,
      settings: NotificationSettingsValue(
        localInAppOnly: true,
        desktopDeliveryAvailable: data.containsKey('windowsEnabled'),
        directMessageDeliveryAvailable: data.containsKey(
          'directMessageWindowsEnabled',
        ),
        overlayDeliveryAvailable: data.containsKey('overlayEnabled'),
        channels: NotificationChannelSettings(
          inAppEnabled: enabled,
          windowsDesktopEnabled: data['windowsEnabled'] == true,
          directMessageWindowsEnabled:
              data['directMessageWindowsEnabled'] == true,
          overlayEnabled: data['overlayEnabled'] == true,
          desktopPosition: positions.single,
          sound: const NotificationSoundSettings.notImplemented(),
        ),
        sourceRules: const [],
        previewMode: previews.single,
        playerActivity: PlayerActivityNotificationSettings.migratedDefault(),
        continuousPlay: ContinuousPlayReminderSettings.migratedDefault()
            .copyWith(enabled: false),
      ),
    );
  }

  @override
  Future<NotificationSettingsSnapshot> read() async {
    try {
      return await _call('read');
    } catch (e) {
      return NotificationSettingsSnapshot.unavailable(
        failure: _failure(e, false),
      );
    }
  }

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue value, {
    required int expectedRevision,
  }) async {
    try {
      final result = await _call('save', {
        'expectedRevision': expectedRevision,
        'inAppEnabled': value.channels.inAppEnabled,
        'position': value.channels.desktopPosition.name,
        'preview': value.previewMode.name,
        if (value.desktopDeliveryAvailable)
          'windowsEnabled': value.channels.windowsDesktopEnabled,
        if (value.overlayDeliveryAvailable)
          'overlayEnabled': value.channels.overlayEnabled,
        if (value.directMessageDeliveryAvailable)
          'directMessageWindowsEnabled':
              value.channels.directMessageWindowsEnabled,
      });
      if (result.availability != NotificationSettingsAvailability.available) {
        return const NotificationSettingsWriteResult.failed(
          NotificationSettingsFailure.hostUnavailable,
        );
      }
      return NotificationSettingsWriteResult.completed(result);
    } catch (e) {
      return NotificationSettingsWriteResult.failed(_failure(e, true));
    }
  }

  @override
  Future<void> close() async {
    notificationSourceDeliveryEpoch(session)
        .removeListener(_clearSourceReminder);
    await _subscription.cancel();
    await _reminders.close();
    await _invalidations.close();
  }
}
