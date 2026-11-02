import 'dart:async';

import 'package:starbridge_flutter/features/onboarding/bridge_device_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_port.dart';

// Synthetic device settings; no account, filesystem or native runtime.
Map<String, Object?> deviceWire({
  String state = 'reviewRequired',
  String? key = '11111111111111111111111111111111',
}) => {
  'schemaVersion': 1,
  'state': state,
  'reviewKey': key,
  'application': <String, Object?>{
    'launchAtStartup': false,
    'keepRunningInBackground': true,
    'startMinimized': false,
    'startupChoiceMade': true,
    'closeBehaviorChoiceMade': true,
  },
  'overlay': <String, Object?>{
    'renderMode': 'DirectComposition',
    'hotkeyBinding': 'Ctrl+F9',
    'hotkeyEnabled': true,
    'opacity': .64,
    'autoOpenOnGameStart': false,
    'autoOpenOnGameForeground': false,
    'autoCloseOnGameBackground': true,
    'showEventNotifications': true,
  },
  'notifications': <String, Object?>{
    'inAppEnabled': true,
    'windowsEnabled': false,
    'overlayEnabled': true,
    'directMessageWindowsEnabled': false,
    'position': 'bottomRight',
    'preview': 'sourceOnly',
  },
  'playReminder': <String, Object?>{
    'enabled': false,
    'firstReminderMinutes': 90,
    'repeatReminderMinutes': 60,
  },
};

class FakeDeviceReviewPort implements DeviceReviewPort {
  DeviceReviewSnapshot snapshot = DeviceReviewWire.parse(deviceWire());
  final events = StreamController<void>.broadcast(sync: true);
  bool fail = false;
  int reads = 0, confirmations = 0;
  Future<DeviceReviewSnapshot> Function()? onRead;
  Future<DeviceReviewSnapshot> Function()? onConfirm;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<DeviceReviewSnapshot> read() async {
    reads++;
    if (fail) throw StateError('synthetic failure');
    return onRead?.call() ?? snapshot;
  }

  @override
  Future<DeviceReviewSnapshot> confirm(
    String key,
    Set<DeviceReviewSection> sections,
  ) async {
    confirmations++;
    if (key != snapshot.reviewKey || sections.length != 4) {
      throw StateError('stale synthetic review');
    }
    if (fail) throw StateError('synthetic failure');
    if (onConfirm != null) return onConfirm!();
    snapshot = DeviceReviewWire.parse(
      deviceWire(state: 'reviewed', key: '22222222222222222222222222222222'),
    );
    return snapshot;
  }

  Future<void> close() => events.close();
}
