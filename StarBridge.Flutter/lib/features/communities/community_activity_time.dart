import 'package:flutter/material.dart';

import 'community_workspace_port.dart';
import 'community_workspace_copy.dart';
import 'community_profile_copy.dart';

String communityTimeZoneSummary(
  BuildContext context,
  CommunityWorkspace workspace,
) {
  if (workspace.timeZoneId?.isNotEmpty != true) return '';
  final minutes = workspace.timeZoneStandardOffsetMinutes;
  if (minutes == null) return workspaceText(context, 'timeZoneUnavailable');
  final absolute = minutes.abs();
  final offset =
      'UTC${minutes < 0 ? '−' : '+'}'
      '${(absolute ~/ 60).toString().padLeft(2, '0')}:'
      '${(absolute % 60).toString().padLeft(2, '0')}';
  return workspace.timeZoneUsesDaylightSaving
      ? '$offset (${workspaceText(context, 'standardTime')})'
      : offset;
}

/// Display structured schedules in the current language, never a stale saved label.
String communityActivitySummary(
  BuildContext context,
  Iterable<CommunityActivityWindow> windows,
) {
  final groups = <(String, String, bool), Set<String>>{};
  for (final window in windows) {
    (groups[(window.startTime, window.endTime, window.endsNextDay)] ??= {})
        .addAll(window.days);
  }
  return groups.entries
      .map((entry) {
        final (start, end, nextDay) = entry.key;
        return '${workspaceDays(context, entry.value)} '
            '${communityDisplayClock(context, start)}–'
            '${nextDay ? '${profileText(context, 'nextDayShort')} ' : ''}'
            '${communityDisplayClock(context, end)}';
      })
      .join('; ');
}

int communityClockMinutes(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return -1;
  final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
  return hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59
      ? -1
      : hour * 60 + minute;
}

String communityClockText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

// Match WPF's editor coupling while keeping the protocol's HH:mm values.
Map<String, Object?> changeCommunityWindow(
  Map<String, Object?> row,
  String field,
  Object value,
) {
  final next = {...row, field: value};
  final start = communityClockMinutes(next['startTime'] as String);
  var end = communityClockMinutes(next['endTime'] as String);
  if (start < 0 || end < 0) return next;
  if (field == 'endsNextDay') {
    if (value == true && end > start) end = start;
    if (value == false && end <= start && start < 1439) end = start + 1;
    next['endTime'] = communityClockText(end);
  }
  if (field == 'startTime' || field == 'endTime' || field == 'endsNextDay') {
    next['endsNextDay'] = end <= start;
  }
  return next;
}

bool communityUses12Hour(BuildContext context) =>
    Localizations.localeOf(context).languageCode != 'zh' &&
    switch (MaterialLocalizations.of(context)
        .timeOfDayFormat(alwaysUse24HourFormat: false)) {
      TimeOfDayFormat.h_colon_mm_space_a ||
      TimeOfDayFormat.a_space_h_colon_mm => true,
      _ => false,
    };

String communityDisplayClock(BuildContext context, String value) {
  final minutes = communityClockMinutes(value);
  if (minutes < 0) return value;
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    alwaysUse24HourFormat: !communityUses12Hour(context),
  );
}

int communityWindowDuration(Map<String, Object?> row) {
  final start = communityClockMinutes(row['startTime'] as String);
  final end = communityClockMinutes(row['endTime'] as String);
  return end - start + (end <= start || row['endsNextDay'] == true ? 1440 : 0);
}

bool communityWindowFits(Map<String, Object?> row) {
  final start = communityClockMinutes(row['startTime'] as String);
  final end = communityClockMinutes(row['endTime'] as String);
  return start >= 0 && end >= 0 && row['endsNextDay'] == (end <= start);
}
