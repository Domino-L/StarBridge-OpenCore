import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';

import '../../shared/clock_field.dart';
import '../../shared/time_zone_label.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import 'personal_profile_models.dart';
import 'personal_profile_collaboration.dart';

class PersonalProfileScheduleEditor extends StatefulWidget {
  const PersonalProfileScheduleEditor({
    required this.initial,
    required this.timeZones,
    required this.enabled,
    required this.onChanged,
    this.initiallyChanged = false,
    super.key,
  });
  final PersonalProfileSchedule initial;
  final bool initiallyChanged;
  final Map<String, String> timeZones;
  final bool enabled;
  final ValueChanged<PersonalProfileSchedule> onChanged;
  @override
  State<PersonalProfileScheduleEditor> createState() => _ScheduleState();
}

class _ScheduleState extends State<PersonalProfileScheduleEditor> {
  late String _zone = widget.initial.timeZoneId;
  late PersonalProfileActivityRhythm _rhythm = widget.initial.rhythm;
  late final _windows = widget.initial.windows.toList();
  late final _keys = List.generate(_windows.length, (_) => UniqueKey());
  late bool _changed = widget.initiallyChanged;
  bool _expanded = false;
  void _emit() {
    _changed = true;
    widget.onChanged(
      PersonalProfileSchedule(
        timeZoneId: _zone,
        rhythm: _rhythm,
        windows: List.unmodifiable(_windows),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final gap = context.tokens.space.md;
    final zones = {
      ...widget.timeZones,
      if (_zone.isNotEmpty && !widget.timeZones.containsKey(_zone))
        _zone: _zone,
    };
    return Material(
      type: MaterialType.transparency,
      child: FormField<void>(
        validator: (_) =>
            !_changed ||
                ProfileCollaboration.validSchedule(
                  PersonalProfileSchedule(
                    timeZoneId: _zone,
                    rhythm: _rhythm,
                    windows: _windows,
                  ),
                )
            ? null
            : strings.text('profile.collab.invalid'),
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (field.hasError)
              Text(
                field.errorText!,
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            Padding(
              // Preserve the native disclosure's transparent top/bottom border.
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: StarBridgeExpansionTile(
                maintainState: true,
                key: const Key('profile-schedule-editor'),
                useNativePageStorage: true,
                onExpansionChanged: (value) =>
                    setState(() => _expanded = value),
                headerMinHeight: 0,
                headerBuilder: (context, visual, open) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.text('profile.collab.schedule'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    ProfileCollaboration.summary(context, _windows),
                  ),
                  trailing: StarBridgeIcon(
                    _expanded
                        ? StarBridgeIconSemantic.menuDown
                        : StarBridgeIconSemantic.forward,
                  ),
                ),
                // Floating labels paint above their field; keep them inside the
                // ExpansionTile's animated clip, including enlarged text.
                childrenPadding: EdgeInsets.only(
                  top: MediaQuery.textScalerOf(context).scale(gap),
                ),
                title: strings.text('profile.collab.schedule'),
                subtitle: ProfileCollaboration.summary(context, _windows),
                children: [
                  StarBridgeSelectFormField<String>(
                    identity: 'profile-schedule-zone',
                    controlKey: const Key('profile-schedule-zone-trigger'),
                    key: const Key('profile-schedule-zone'),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.menuDown),
                    initialValue: _zone.isEmpty ? null : _zone,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.text('profile.availability.timeZone'),
                    ),
                    items: [
                      for (final zone in zones.entries)
                        DropdownMenuItem(
                          value: zone.key,
                          child: Text(
                            zone.key == 'UTC'
                                ? 'UTC'
                                : timeZoneLabel(
                                    context,
                                    zone.key,
                                    fallback: zone.value,
                                  ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (_) =>
                        _changed && _windows.isNotEmpty && _zone.isEmpty
                        ? strings.text('profile.collab.chooseZone')
                        : null,
                    onChanged: !widget.enabled
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _zone = value;
                                _emit();
                              });
                            }
                          },
                  ),
                  SizedBox(height: gap / 2),
                  Text(
                    strings.text('profile.collab.zoneHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(height: gap),
                  StarBridgeSelectFormField<PersonalProfileActivityRhythm>(
                    identity: 'profile-schedule-rhythm',
                    controlKey: const Key('profile-schedule-rhythm-trigger'),
                    key: const Key('profile-schedule-rhythm'),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.menuDown),
                    initialValue: _rhythm,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.text('profile.activity.title'),
                    ),
                    items: [
                      for (final rhythm in PersonalProfileActivityRhythm.values)
                        DropdownMenuItem(
                          value: rhythm,
                          child: Text(
                            strings.text('profile.activity.${rhythm.name}'),
                          ),
                        ),
                    ],
                    onChanged: !widget.enabled
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _rhythm = value;
                                _emit();
                              });
                            }
                          },
                  ),
                  for (var i = 0; i < _windows.length; i++)
                    Padding(
                      key: _keys[i],
                      padding: EdgeInsets.only(top: gap),
                      child: _WindowEditor(
                        value: _windows[i],
                        index: i,
                        enabled: widget.enabled,
                        validate: _changed,
                        onRemove: () => setState(() {
                          _windows.removeAt(i);
                          _keys.removeAt(i);
                          _emit();
                        }),
                        onChanged: (value) => setState(() {
                          _windows[i] = value;
                          _emit();
                        }),
                      ),
                    ),
                  SizedBox(height: gap),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StarBridgeActionButton(
                      controlKey: const Key('profile-add-window'),
                      onActivate: !widget.enabled || _windows.length >= 3
                          ? null
                          : (_) => setState(() {
                              _windows.add(
                                const PersonalProfileAvailabilityWindow(
                                  days: [1, 2, 3, 4, 5],
                                  startTime: '19:00',
                                  endTime: '22:00',
                                ),
                              );
                              _keys.add(UniqueKey());
                              _emit();
                            }),
                      child: Text(
                        '${strings.text('profile.collab.addWindow')} (${_windows.length}/3)',
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowEditor extends StatelessWidget {
  const _WindowEditor({
    required this.value,
    required this.index,
    required this.enabled,
    required this.validate,
    required this.onChanged,
    required this.onRemove,
  });
  final PersonalProfileAvailabilityWindow value;
  final int index;
  final bool enabled, validate;
  final ValueChanged<PersonalProfileAvailabilityWindow> onChanged;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final gap = context.tokens.space.sm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${strings.text('profile.collab.window')} ${index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: Key('profile-remove-window-$index'),
              onActivate: enabled ? (_) => onRemove() : null,
              child: Text(strings.text('profile.collab.remove')),
            ),
          ],
        ),
        FormField<List<int>>(
          validator: (_) => validate && value.days.isEmpty
              ? strings.text('profile.collab.chooseDays')
              : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: gap / 2,
                runSpacing: gap / 2,
                children: [
                  for (final day in [1, 2, 3, 4, 5, 6, 0])
                    StarBridgeChoiceChip.filter(
                      controlKey: Key('profile-window-$index-day-$day'),
                      label: strings.text('profile.collab.day.$day'),
                      selected: value.days.contains(day),
                      onSelected: !enabled
                          ? null
                          : (selected) {
                              final days = value.days.toSet();
                              selected ? days.add(day) : days.remove(day);
                              field.didChange(days.toList());
                              onChanged(
                                PersonalProfileAvailabilityWindow(
                                  days: days.toList(),
                                  startTime: value.startTime,
                                  endTime: value.endTime,
                                ),
                              );
                            },
                    ),
                ],
              ),
              if (field.hasError)
                Text(
                  field.errorText!,
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
            ],
          ),
        ),
        SizedBox(height: gap),
        // Picked, never typed (user decision 2026-10-22): the shared clock
        // lists, the same as trading hours and community activity time.
        FormField<String>(
          validator: (_) =>
              !validate ||
                  ProfileCollaboration.validTime(value.startTime) &&
                      ProfileCollaboration.validTime(value.endTime)
              ? null
              : strings.text('profile.collab.timeInvalid'),
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StarBridgeTimeRangeField(
                keyPrefix: 'profile-window-$index',
                start: value.startTime,
                end: value.endTime,
                startLabel: strings.text('profile.collab.start'),
                endLabel: strings.text('profile.collab.end'),
                onChanged: !enabled
                    ? null
                    : (start, end) {
                        field.didChange('$start-$end');
                        onChanged(
                          PersonalProfileAvailabilityWindow(
                            days: value.days,
                            startTime: start,
                            endTime: end,
                          ),
                        );
                      },
              ),
              if (field.hasError)
                Text(
                  field.errorText!,
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
            ],
          ),
        ),
        SizedBox(height: gap),
        const Divider(),
      ],
    );
  }
}
