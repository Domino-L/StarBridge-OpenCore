import '../../platform/bridge/bridge_client_session.dart';
import 'device_review_port.dart';

final class BridgeDeviceReviewAdapter implements DeviceReviewPort {
  BridgeDeviceReviewAdapter(this.session);
  static const capability = 'onboarding.deviceReview.v1';
  final BridgeClientSession session;
  DeviceReviewSnapshot? _current;
  int? _generation;
  int _epoch = 0;
  void _invalidate() {
    _epoch++;
    _current = null;
    _generation = null;
  }

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) => const {
          'account.changed',
          'bootstrap.invalidated',
          'onboarding.changed',
          'applicationPreferences.changed',
          'overlay.changed',
          'notificationSettings.changed',
          'playReminder.changed',
        }.contains(event.name),
      )
      .map((_) {
        _invalidate();
      });
  @override
  Future<DeviceReviewSnapshot> read() async {
    if (!session.hostCapabilities.contains(capability)) {
      _invalidate();
      return const DeviceReviewSnapshot();
    }
    return _request('onboarding.deviceReview.read', const {});
  }

  @override
  Future<DeviceReviewSnapshot> confirm(
    String reviewKey,
    Set<DeviceReviewSection> sections,
  ) {
    if (!session.hostCapabilities.contains(capability) ||
        _generation != session.activeGeneration ||
        _current?.reviewKey != reviewKey ||
        _current?.canReview != true ||
        sections.length != DeviceReviewSection.values.length) {
      throw StateError('Device review is no longer current.');
    }
    return _request('onboarding.deviceReview.confirm', {
      'reviewKey': reviewKey,
      'reviewedSections': DeviceReviewSection.values
          .map((section) => section.name)
          .toList(),
    });
  }

  Future<DeviceReviewSnapshot> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    final epoch = ++_epoch;
    final generation = session.activeGeneration;
    // A sent confirmation consumes the observation even if its outcome is unknown.
    _current = null;
    _generation = null;
    try {
      final response = await session.request(
        name,
        payload: {'schemaVersion': 1, ...payload},
      );
      if (epoch != _epoch ||
          !session.hostCapabilities.contains(capability) ||
          generation != session.activeGeneration ||
          response.sessionGeneration != generation ||
          response.status != 'ok' ||
          response.error != null) {
        throw StateError('Device review was not confirmed.');
      }
      final value = DeviceReviewWire.parse(response.payload);
      _current = value;
      _generation = generation;
      return value;
    } on Object {
      if (epoch == _epoch) _invalidate();
      rethrow;
    }
  }
}

abstract final class DeviceReviewWire {
  static DeviceReviewSnapshot parse(Map<String, Object?> raw) {
    shape(raw, {
      'schemaVersion',
      'state',
      'reviewKey',
      ...DeviceReviewSection.values.map((s) => s.name),
    });
    if (raw['schemaVersion'] is! int || raw['schemaVersion'] != 1) bad();
    final state = DeviceReviewState.values
        .where((s) => s.name == raw['state'])
        .singleOrNull;
    if (state == null) bad();
    final key = raw['reviewKey'];
    if (key != null &&
        (key is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(key))) {
      bad();
    }
    final sections = <DeviceReviewSection, Map<String, Object?>?>{};
    for (final section in DeviceReviewSection.values) {
      final value = raw[section.name];
      if (value == null) {
        sections[section] = null;
        continue;
      }
      if (value is! Map<String, Object?>) bad();
      final booleans = switch (section) {
        DeviceReviewSection.application => {
          'launchAtStartup',
          'keepRunningInBackground',
          'startMinimized',
          'startupChoiceMade',
          'closeBehaviorChoiceMade',
        },
        DeviceReviewSection.overlay => {
          'hotkeyEnabled',
          'autoOpenOnGameStart',
          'autoOpenOnGameForeground',
          'autoCloseOnGameBackground',
          'showEventNotifications',
        },
        DeviceReviewSection.notifications => {
          'inAppEnabled',
          'windowsEnabled',
          'overlayEnabled',
          'directMessageWindowsEnabled',
        },
        DeviceReviewSection.playReminder => {'enabled'},
      };
      final others = switch (section) {
        DeviceReviewSection.application => <String>{},
        DeviceReviewSection.overlay => {
          'renderMode',
          'hotkeyBinding',
          'opacity',
        },
        DeviceReviewSection.notifications => {'position', 'preview'},
        DeviceReviewSection.playReminder => {
          'firstReminderMinutes',
          'repeatReminderMinutes',
        },
      };
      shape(value, {...booleans, ...others});
      if (booleans.any((field) => value[field] is! bool)) bad();
      if (section == DeviceReviewSection.overlay) {
        final binding = value['hotkeyBinding'];
        final opacity = value['opacity'];
        if (value['renderMode'] != 'DirectComposition' ||
            binding is! String ||
            !RegExp(
              r'^(?:(?:Ctrl|Control|Alt|Shift|Win|Windows)\+)*[\p{L}\p{N}]{1,24}$',
              unicode: true,
              caseSensitive: false,
            ).hasMatch(binding) ||
            opacity is! num ||
            !opacity.isFinite ||
            opacity < 0 ||
            opacity > 1) {
          bad();
        }
      }
      if (section == DeviceReviewSection.notifications &&
          (!{
                'topLeft',
                'topRight',
                'bottomLeft',
                'bottomRight',
              }.contains(value['position']) ||
              !{
                'fullContent',
                'sourceOnly',
                'hiddenDetails',
              }.contains(value['preview']))) {
        bad();
      }
      if (section == DeviceReviewSection.playReminder &&
          (value['firstReminderMinutes'] is! int ||
              value['repeatReminderMinutes'] is! int ||
              !{60, 90, 120, 180}.contains(value['firstReminderMinutes']) ||
              !{60, 120}.contains(value['repeatReminderMinutes']))) {
        bad();
      }
      sections[section] = Map.unmodifiable(value);
    }
    final reviewable = {
      DeviceReviewState.reviewRequired,
      DeviceReviewState.reviewed,
    }.contains(state);
    if (reviewable != (key != null) ||
        reviewable &&
            (sections.values.any((v) => v == null) ||
                sections[DeviceReviewSection
                        .application]!['startupChoiceMade'] !=
                    true ||
                sections[DeviceReviewSection
                        .application]!['closeBehaviorChoiceMade'] !=
                    true)) {
      bad();
    }
    return DeviceReviewSnapshot(
      state: state,
      reviewKey: key as String?,
      sections: Map.unmodifiable(sections),
    );
  }

  static void shape(Map<String, Object?> raw, Set<String> fields) {
    if (raw.length != fields.length || !fields.every(raw.containsKey)) bad();
  }

  static Never bad() =>
      throw const FormatException('Invalid device review projection.');
}
