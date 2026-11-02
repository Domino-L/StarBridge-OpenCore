import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../shared/clock_field.dart';
import 'community_activity_time.dart';
import 'community_profile_copy.dart';
import 'community_workspace_copy.dart' show workspaceDay;

/// Activity-window fields only; the form owns mutations and permissions.
final class CommunityProfileActivityWindows {
  const CommunityProfileActivityWindows({
    required this.context,
    required this.serial,
    required this.readFields,
    required this.canEdit,
    required this.update,
    required this.structureChanged,
    required this.box,
  });
  final BuildContext context;
  final int serial;
  final Map<String, Object?> Function() readFields;
  final bool Function() canEdit;
  final void Function(String, Object?) update;
  final VoidCallback structureChanged;
  final Widget Function(Widget) box;
  String t(String key) => profileText(context, key);
  List<Map<String, Object?>> rows(String field) =>
      (readFields()[field] as List? ?? [])
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();

  Widget window(int index) {
    final row = rows('activityWindows')[index];
    final enabled = canEdit();
    void change(String key, Object value) {
      final list = rows('activityWindows');
      list[index] = changeCommunityWindow(list[index], key, value);
      update('activityWindows', list);
    }

    return box(
      Column(
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final day in [
                'mon',
                'tue',
                'wed',
                'thu',
                'fri',
                'sat',
                'sun',
              ])
                StarBridgeChoiceChip.filter(
                  controlKey: ValueKey(
                    'profile-window-$serial-$index-day-$day',
                  ),
                  label: workspaceDay(context, day),
                  selected: (row['days'] as List).contains(day),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          final days = List<String>.from(row['days'] as List);
                          selected ? days.add(day) : days.remove(day);
                          change('days', days);
                        },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            // The shared clock lists (user decision 2026-10-22); the line
            // below already states the length, so no second summary.
            child: StarBridgeTimeRangeField(
              keyPrefix: 'profile-window-$serial-$index',
              start: row['startTime'] as String,
              end: row['endTime'] as String,
              startLabel: t('activeFrom'),
              endLabel: t('activeTo'),
              showSummary: false,
              onChanged: !enabled
                  ? null
                  : (start, end) => start != row['startTime']
                        ? change('startTime', start)
                        : change('endTime', end),
            ),
          ),
          StarBridgeCheckboxTile(
            controlKey: ValueKey('profile-window-$serial-$index-next-day'),
            label: t('nextDay'),
            titleWidget: Text(
              t('nextDay'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            dense: false,
            trailingControl: true,
            value: row['endsNextDay'] as bool,
            subtitle: t(
              communityClockMinutes(row['startTime'] as String) == 1439
                  ? 'lastMinuteHint'
                  : 'nextDayHint',
            ),
            onChanged:
                !enabled ||
                    communityClockMinutes(row['startTime'] as String) == 1439
                ? null
                : (v) => change('endsNextDay', v),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${communityDisplayClock(context, row['startTime'] as String)} → '
              '${row['endsNextDay'] == true ? '${t('nextDayShort')} ' : ''}'
              '${communityDisplayClock(context, row['endTime'] as String)} · '
              '${communityWindowDuration(row) ~/ 60} ${t('durationHour')} ${communityWindowDuration(row) % 60} ${t('durationMinute')}',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: ValueKey('profile-window-$serial-$index-remove'),
              onActivate: !enabled
                  ? null
                  : (_) {
                      final list = rows('activityWindows')..removeAt(index);
                      structureChanged();
                      update('activityWindows', list);
                    },
              child: Text(t('remove')),
            ),
          ),
        ],
      ),
    );
  }
}
