import 'package:flutter/material.dart';

import '../../shared/time_zone_region.dart';
import 'community_workspace_port.dart';
import 'community_workspace_copy.dart';
import 'community_profile_copy.dart';

/// One phrase of a readout: it wraps only between phrases, never inside
/// (user 2026-10-29: the time zone must not split from its offset). Display
/// only; the stored and searched texts keep their ordinary spaces.
String communityNoBreak(String value) =>
    value.replaceAll(' ', '\u00A0').replaceAll('–', '–\u2060');

/// A readout value whose phrases ("; " and " · " apart) never break inside.
String communityReadoutPhrases(String value) => value
    .split('; ')
    .map((phrase) => phrase.split(' · ').map(communityNoBreak).join(' · '))
    .join('; ');

/// "UTC−06:00（美国中部）": the offset and, when known, the region people
/// recognise (user 2026-10-29: "时区后也该跟用户能看懂的位置").
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
  final notes = [
    ?timeZoneRegionLabel(context, workspace.timeZoneId!, minutes),
    if (workspace.timeZoneUsesDaylightSaving)
      workspaceText(context, 'standardTime'),
  ];
  if (notes.isEmpty) return offset;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final note = notes.join(zh ? '，' : ', ');
  return zh ? '$offset（$note）' : '$offset ($note)';
}

/// Display structured schedules in the current language, never a stale saved label.
String communityActivitySummary(
  BuildContext context,
  Iterable<CommunityActivityWindow> windows, {
  int shiftMinutes = 0,
}) {
  final groups = <(String, String, bool), Set<String>>{};
  for (final window in windows) {
    (groups[(window.startTime, window.endTime, window.endsNextDay)] ??= {})
        .addAll(window.days);
  }
  return groups.entries
      .map((entry) {
        var (start, end, nextDay) = entry.key;
        if (shiftMinutes != 0) {
          final from = communityClockMinutes(start),
              to = communityClockMinutes(end);
          if (from >= 0 && to >= 0) {
            final shiftedFrom = (from + shiftMinutes) % 1440;
            final shiftedTo = (to + shiftMinutes) % 1440;
            start = communityClockText((shiftedFrom + 1440) % 1440);
            end = communityClockText((shiftedTo + 1440) % 1440);
            // Day names stay the organization's; only a window that now
            // crosses midnight shows the next-day mark.
            nextDay =
                communityClockMinutes(end) <= communityClockMinutes(start);
          }
        }
        return '${workspaceDays(context, entry.value)} '
            '${communityDisplayClock(context, start)}–'
            '${nextDay ? '${profileText(context, 'nextDayShort')} ' : ''}'
            '${communityDisplayClock(context, end)}';
      })
      .join('; ');
}

/// The same windows in the viewer's clock, or empty when the viewer already
/// lives in the organization's standard offset (user 2026-10-29: "可以加").
/// Day names stay the organization's; the shift is standard offset to the
/// viewer's current offset, so a daylight-saving organization is approximate.
String communityViewerActivitySummary(
  BuildContext context,
  Iterable<CommunityActivityWindow> windows,
  int? organizationOffsetMinutes, {
  int? viewerOffsetMinutes,
}) {
  if (organizationOffsetMinutes == null || windows.isEmpty) return '';
  final viewer = viewerOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
  final shift = viewer - organizationOffsetMinutes;
  if (shift == 0) return '';
  return communityActivitySummary(context, windows, shiftMinutes: shift);
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
