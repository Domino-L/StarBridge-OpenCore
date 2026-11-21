import 'package:flutter/foundation.dart';

enum NotificationChatMode { inherit, enabled, disabled }

@immutable
class NotificationOrganizationOptions {
  // 0.7.3 card defaults (user): organization chat raises no card unless
  // turned on; announcements follow the source mode. Saved choices stay saved.
  const NotificationOrganizationOptions({
    this.chat = NotificationChatMode.disabled,
    this.announcement = NotificationChatMode.inherit,
    this.activity = NotificationChatMode.disabled,
    this.quietEnabled = false,
    this.startMinute = 1320,
    this.endMinute = 480,
  });
  final NotificationChatMode chat;
  final NotificationChatMode announcement, activity;
  final bool quietEnabled;
  final int startMinute, endMinute;

  NotificationOrganizationOptions copyWith({
    NotificationChatMode? chat,
    NotificationChatMode? announcement,
    bool? quietEnabled,
    int? startMinute,
    int? endMinute,
  }) => NotificationOrganizationOptions(
    chat: chat ?? this.chat,
    announcement: announcement ?? this.announcement,
    activity: activity,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
  );

  bool get valid =>
      startMinute >= 0 &&
      startMinute < 1440 &&
      endMinute >= 0 &&
      endMinute < 1440 &&
      startMinute != endMinute;

  Map<String, Object?> toWire() => {
    'typeRules': [
      {'type': 'chat', 'mode': chat.name},
      {'type': 'announcement', 'mode': announcement.name},
      {'type': 'activity', 'mode': activity.name},
    ],
    'quietHours': {
      'enabled': quietEnabled,
      'startMinute': startMinute,
      'endMinute': endMinute,
      'clock': 'local',
    },
  };

  static NotificationOrganizationOptions parse(Map row) {
    final types = row['typeRules'], q = row['quietHours'];
    if (types is! List ||
        types.length > 3 ||
        q is! Map ||
        q['enabled'] is! bool ||
        q['startMinute'] is! int ||
        q['endMinute'] is! int ||
        q['clock'] != 'local') {
      throw const FormatException('Invalid organization notification options');
    }
    final seen = <String>{};
    var chat = NotificationChatMode.disabled;
    var announcement = NotificationChatMode.inherit;
    var activity = NotificationChatMode.disabled;
    for (final t in types) {
      if (t is! Map ||
          !['chat', 'announcement', 'activity'].contains(t['type']) ||
          !seen.add(t['type'] as String) ||
          !NotificationChatMode.values.any((m) => m.name == t['mode'])) {
        throw const FormatException('Invalid notification type rule');
      }
      if (t['type'] == 'chat') {
        chat = NotificationChatMode.values.byName(t['mode'] as String);
      }
      if (t['type'] == 'announcement') {
        announcement = NotificationChatMode.values.byName(t['mode'] as String);
      }
      if (t['type'] == 'activity') {
        activity = NotificationChatMode.values.byName(t['mode'] as String);
      }
    }
    final result = NotificationOrganizationOptions(
      chat: chat,
      announcement: announcement,
      activity: activity,
      quietEnabled: q['enabled'] as bool,
      startMinute: q['startMinute'] as int,
      endMinute: q['endMinute'] as int,
    );
    if (!result.valid) throw const FormatException('Invalid quiet hours');
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationOrganizationOptions &&
      chat == other.chat &&
      announcement == other.announcement &&
      activity == other.activity &&
      quietEnabled == other.quietEnabled &&
      startMinute == other.startMinute &&
      endMinute == other.endMinute;
  @override
  int get hashCode => Object.hash(
    chat,
    announcement,
    activity,
    quietEnabled,
    startMinute,
    endMinute,
  );
}
