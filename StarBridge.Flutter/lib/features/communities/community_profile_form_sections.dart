import '../../design_system/icons/standard_icon.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_profile_controller.dart';
import 'community_profile_port.dart';
import 'community_profile_copy.dart';
import 'community_creation_port.dart';
import 'community_gameplay_tags.dart';
import 'community_workspace_copy.dart' show workspaceDay;
import 'community_workspace_image.dart';
import 'community_profile_rules.dart';
import 'community_system_choices.dart';
import 'community_activity_time.dart';

/// Renders the editable sections; the owning dialog retains draft lifecycle.
final class CommunityProfileFormSections {
  CommunityProfileFormSections({
    required this.context,
    required this.model,
    required this.options,
    required this.serial,
    required this.busy,
    required this.canPickLogo,
    required this.draftLogoBytes,
    required this.serverLogoBytes,
    required this.logoLoading,
    required this.logoFailed,
    required this.update,
    required this.structureChanged,
    required this.pickLogo,
    required this.chooseTags,
    required this.publishContacts,
  });
  final BuildContext context;
  final CommunityProfileController model;
  final CommunityCreationOptions? options;
  final int serial;
  final bool busy, canPickLogo, logoLoading, logoFailed;
  final Uint8List? draftLogoBytes, serverLogoBytes;
  final void Function(String, Object?) update;
  final VoidCallback structureChanged, pickLogo, chooseTags, publishContacts;
  String t(String key) => profileText(context, key);
  Map<String, Object?> get fields => model.fields;
  List<Map<String, Object?>> rows(String field) =>
      (fields[field] as List? ?? [])
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();

  Widget continuousSection(int index, Key anchor, Widget child) => Padding(
    key: ValueKey('profile-section-$index'),
    padding: EdgeInsets.only(top: index == 0 ? 0 : 32, bottom: 8),
    child: Column(
      key: anchor,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(['basic', 'discovery', 'schedule', 'contacts'][index]),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          t(
            [
              'basicHelp',
              'discoveryHelp',
              'scheduleHelp',
              'contactsHelp',
            ][index],
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );

  Widget textField(String key, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('profile-$serial-$key'),
      initialValue: fields[key] as String? ?? '',
      style: Theme.of(context).textTheme.bodyMedium,
      enabled: !busy && model.profile!.permits(key),
      minLines: lines,
      maxLines: lines,
      maxLength: communityProfileTextLimits[key],
      decoration: InputDecoration(
        labelText: t(key),
        helperText: key == 'name'
            ? t('nameHint')
            : communityProfileEditLimits.containsKey(key) && key != 'websiteUrl'
            ? t('shortTextHint')
            : null,
        counterText: communityProfileEditLimits.containsKey(key)
            ? '${key == 'websiteUrl' || key == 'name' ? (fields[key] as String? ?? '').runes.length : communityTextUnits(fields[key] as String? ?? '')}/${communityProfileEditLimits[key]}'
            : null,
      ),
      validator: (value) =>
          value != model.profile!.fields[key] &&
              !communityProfileTextFits(key, value ?? '')
          ? t(key == 'name' ? 'nameInvalid' : 'textTooLong')
          : null,
      onChanged: (v) => update(key, v),
    ),
  );
  Widget select(String key, Map<String, String> choices) {
    final value = fields[key] as String? ?? '';
    final all = {
      ...choices,
      if (!choices.containsKey(value)) value: value.isEmpty ? '—' : value,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('profile-$serial-$key'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: t(key)),
        items: all.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                enabled:
                    !(key == 'joinPolicy' &&
                        fields['recruitingEnabled'] == true &&
                        e.key == 'Invite'),
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: busy || !model.profile!.permits(key)
            ? null
            : (v) {
                if (v != null) update(key, v);
              },
      ),
    );
  }

  Widget toggle(String key) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(t(key), style: Theme.of(context).textTheme.bodyMedium),
    value: fields[key] == true,
    subtitle:
        key == 'publicListingEnabled' && fields['recruitingEnabled'] == true
        ? Text(t('recruitingLock'))
        : null,
    onChanged:
        busy ||
            !model.profile!.permits(key) ||
            (key == 'publicListingEnabled' &&
                fields['recruitingEnabled'] == true)
        ? null
        : (v) => update(key, v),
  );
  Widget box(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: context.tokens.surfaces.raised.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
  Widget get branding => Column(
    key: const ValueKey('community-profile-branding'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.profile!.name}  ·  ${model.profile!.code}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (fields['clearLogoImage'] != true &&
                (draftLogoBytes != null ||
                    serverLogoBytes != null ||
                    logoLoading ||
                    logoFailed))
              SizedBox(
                width: 72,
                height: 72,
                child: CommunityWorkspaceImage(
                  bytes: draftLogoBytes ?? serverLogoBytes,
                  loading: draftLogoBytes == null && logoLoading,
                  loadFailed: draftLogoBytes == null && logoFailed,
                  icon: StandardIconSemantic.groups,
                  maxWidth: 144,
                ),
              )
            else
              Text(
                t(
                  fields['clearLogoImage'] == true || !model.profile!.hasLogo
                      ? 'logoEmpty'
                      : 'logoExists',
                ),
              ),
            const SizedBox(height: 8),
            Text(t('imageHint')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !busy && model.profile!.canEditLogo && canPickLogo
                      ? pickLogo
                      : null,
                  icon: const StandardIcon(StandardIconSemantic.image),
                  label: Text(t('pickLogo')),
                ),
                TextButton(
                  onPressed: !busy && model.profile!.canEditLogo
                      ? () => update('clearLogoImage', true)
                      : null,
                  child: Text(t('removeLogo')),
                ),
                if (model.profile!.hasBanner)
                  TextButton(
                    onPressed: !busy && model.profile!.canEditBanner
                        ? () => update('clearBannerImage', true)
                        : null,
                    child: Text(t('removeBanner')),
                  ),
              ],
            ),
            if (fields['clearLogoImage'] == true ||
                fields['clearBannerImage'] == true)
              Text(t('dirty')),
          ],
        ),
      ),
      textField('name'),
      textField('logoText'),
    ],
  );
  Widget get profileDetails => Column(
    key: const ValueKey('community-profile-details'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      textField('description', lines: 4),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('tags')),
            const SizedBox(height: 8),
            CommunityGameplayTags(
              value: fields['type'] as String? ?? '',
              options: options,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed:
                  !busy && model.profile!.canEditProfile && options != null
                  ? chooseTags
                  : null,
              child: Text(t('chooseTags')),
            ),
          ],
        ),
      ),
    ],
  );
  Widget get basic => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [branding, profileDetails],
  );
  Widget get discovery => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        t('recruitmentGroup'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      toggle('recruitingEnabled'),
      select('recruitingTarget', {
        for (final v in ['所有玩家', '新手友好', '战斗玩家', '工业玩家', '贸易与货运', '医疗与支援'])
          v: t(v),
      }),
      textField('recruitingNote', lines: 2),
      const Divider(height: 32),
      Text(t('joiningGroup'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      select('joinPolicy', {
        for (final v in ['Open', 'Approval', 'Invite']) v: t(v),
      }),
      select('inviteCodeCreationPolicy', {
        for (final v in ['all_members', 'management', 'commander']) v: t(v),
      }),
      select('fleetInvitationCardPolicy', {
        for (final v in ['all_members', 'management', 'commander']) v: t(v),
      }),
      const Divider(height: 32),
      Text(
        t('visibilityGroup'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      toggle('publicListingEnabled'),
      select('publicMemberScaleMode', {
        for (final v in ['Exact', 'Approx', 'Hidden']) v: t(v),
      }),
      select('publicShipScaleMode', {
        for (final v in ['TypeSummary', 'TotalOnly', 'Hidden']) v: t(v),
      }),
      for (final v in [
        'publicShowDescription',
        'publicShowTags',
        'publicShowActiveSystems',
        'publicShowActivityTime',
      ])
        toggle(v),
    ],
  );
  Widget get schedule => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      languageChoices,
      select('timeZoneId', {
        for (final zone in options?.timeZones ?? <CommunityTimeZone>[])
          zone.id: zone.name,
      }),
      select('activityCadence', {
        for (final v in ['休闲', '固定开黑', '周末行动', '高频组织', '大型行动前通知']) v: t(v),
      }),
      if ((fields['activeDaysDescription'] as String? ?? '').isNotEmpty ||
          (fields['activeTime'] as String? ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '${t('legacySchedule')}\n${fields['activeDaysDescription'] ?? ''} ${fields['activeTime'] ?? ''}',
          ),
        ),
      Text(t('systems')),
      const SizedBox(height: 8),
      CommunitySystemChoices(
        selected: List<String>.from(fields['activeSystemIds'] as List),
        onChanged: busy || !model.profile!.canEditProfile
            ? null
            : (values) => update('activeSystemIds', values),
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < rows('activityWindows').length; i++) window(i),
      OutlinedButton.icon(
        onPressed:
            !busy &&
                model.profile!.canEditProfile &&
                rows('activityWindows').length < 3
            ? () {
                structureChanged();
                update('activityWindows', [
                  ...rows('activityWindows'),
                  {
                    'days': <String>[],
                    'startTime': '19:00',
                    'endTime': '22:00',
                    'endsNextDay': false,
                  },
                ]);
              }
            : null,
        icon: const StandardIcon(StandardIconSemantic.add),
        label: Text(t('addWindow')),
      ),
    ],
  );
  Widget get languageChoices {
    final chosen = (fields['language'] as String? ?? '')
        .split(RegExp(r'\s*[/,，;；、]\s*'))
        .where((v) => v.isNotEmpty)
        .toSet();
    final choices = {
      ...const [
        '中文',
        'English',
        '日本語',
        '한국어',
        'Deutsch',
        'Français',
        'Español',
        'Русский',
        'Português',
      ],
      ...chosen,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('language'), style: Theme.of(context).textTheme.titleMedium),
          Text(
            t('languagesHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in choices)
                FilterChip(
                  key: ValueKey('profile-language-$value'),
                  label: Text(value),
                  selected: chosen.contains(value),
                  onSelected: busy || !model.profile!.canEditProfile
                      ? null
                      : (yes) {
                          yes ? chosen.add(value) : chosen.remove(value);
                          update('language', chosen.join(' / '));
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget timeChoices(
    int index,
    String field,
    String value,
    bool enabled,
    ValueChanged<String> change,
  ) {
    final parts = value.split(':');
    final twelve = communityUses12Hour(context);
    final clock = communityClockMinutes(value);
    final hour = clock < 0 ? 0 : clock ~/ 60;
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t(field == 'startTime' ? 'activeFrom' : 'activeTo')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var part = 0; part < 2; part++) ...[
              if (part == 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':'),
                ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('profile-window-$serial-$index-$field-$part'),
                  initialValue: clock >= 0
                      ? (part == 0 && twelve
                            ? (hour % 12 == 0 ? 12 : hour % 12)
                                  .toString()
                                  .padLeft(2, '0')
                            : parts[part].padLeft(2, '0'))
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t(part == 0 ? 'hour' : 'minute'),
                    isDense: true,
                  ),
                  items: [
                    for (
                      var n = part == 0 && twelve ? 1 : 0;
                      n < (part == 0 ? (twelve ? 13 : 24) : 60);
                      n++
                    )
                      DropdownMenuItem(
                        value: n.toString().padLeft(2, '0'),
                        child: Text(n.toString().padLeft(2, '0')),
                      ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (selected) {
                          if (selected == null) return;
                          final next = parts.length == 2
                              ? [...parts]
                              : ['00', '00'];
                          next[part] = part == 0 && twelve
                              ? ((int.parse(selected) % 12) +
                                        (hour >= 12 ? 12 : 0))
                                    .toString()
                                    .padLeft(2, '0')
                              : selected;
                          change(next.join(':'));
                        },
                ),
              ),
            ],
            if (twelve) ...[
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('profile-window-$serial-$index-$field-period'),
                  initialValue: hour >= 12 ? 'pm' : 'am',
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: 'am',
                      child: Text(localizations.anteMeridiemAbbreviation),
                    ),
                    DropdownMenuItem(
                      value: 'pm',
                      child: Text(localizations.postMeridiemAbbreviation),
                    ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (period) {
                          if (period == null) return;
                          change(
                            communityClockText(
                              (hour % 12 + (period == 'pm' ? 12 : 0)) * 60 +
                                  (clock < 0 ? 0 : clock % 60),
                            ),
                          );
                        },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget window(int index) {
    final row = rows('activityWindows')[index];
    final enabled = !busy && model.profile!.canEditProfile;
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
                FilterChip(
                  label: Text(workspaceDay(context, day)),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final controls = [
                for (final key in ['startTime', 'endTime'])
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: timeChoices(
                      index,
                      key,
                      row[key] as String,
                      enabled,
                      (value) => change(key, value),
                    ),
                  ),
              ];
              return constraints.maxWidth < 480
                  ? Column(children: controls)
                  : Row(
                      children: [
                        for (final control in controls)
                          Expanded(child: control),
                      ],
                    );
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              t('nextDay'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            value: row['endsNextDay'] as bool,
            subtitle: Text(
              t(
                communityClockMinutes(row['startTime'] as String) == 1439
                    ? 'lastMinuteHint'
                    : 'nextDayHint',
              ),
            ),
            onChanged:
                !enabled ||
                    communityClockMinutes(row['startTime'] as String) == 1439
                ? null
                : (v) => change('endsNextDay', v!),
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
            child: TextButton(
              onPressed: !enabled
                  ? null
                  : () {
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

  Widget get contacts => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      textField('websiteUrl'),
      if (rows('externalContacts').isNotEmpty)
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  fields['publicShowExternalContacts'] == true
                      ? 'publicContacts'
                      : 'privateContacts',
                ),
              ),
              if (fields['publicShowExternalContacts'] != true)
                TextButton(
                  onPressed: busy || !model.profile!.canEditProfile
                      ? null
                      : publishContacts,
                  child: Text(t('publishContacts')),
                ),
            ],
          ),
        ),
      for (var i = 0; i < rows('externalContacts').length; i++) contact(i),
      OutlinedButton.icon(
        onPressed:
            !busy &&
                model.profile!.canEditProfile &&
                rows('externalContacts').length < 5
            ? () {
                structureChanged();
                update('externalContacts', [
                  ...rows('externalContacts'),
                  {'platform': '', 'value': ''},
                ]);
              }
            : null,
        icon: const StandardIcon(StandardIconSemantic.add),
        label: Text(t('addContact')),
      ),
      const SizedBox(height: 16),
      toggle('emailNotificationsEnabled'),
    ],
  );
  Widget contact(int index) {
    final row = rows('externalContacts')[index];
    return box(
      Column(
        children: [
          for (final key in ['platform', 'value'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: key == 'platform'
                  ? DropdownButtonFormField<String>(
                      key: ValueKey('profile-contact-$serial-$index-platform'),
                      initialValue: row['platform'] as String,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t('platform')),
                      items: [
                        for (final platform in {
                          '',
                          'Discord',
                          'QQ',
                          '微信',
                          'Telegram',
                          'Spectrum',
                          row['platform'] as String,
                        })
                          DropdownMenuItem(
                            value: platform,
                            child: Text(platform.isEmpty ? '—' : platform),
                          ),
                      ],
                      onChanged: busy || !model.profile!.canEditProfile
                          ? null
                          : (value) {
                              final list = rows('externalContacts');
                              list[index]['platform'] = value ?? '';
                              update('externalContacts', list);
                            },
                    )
                  : TextFormField(
                      key: ValueKey('profile-contact-$serial-$index-$key'),
                      initialValue: row[key] as String,
                      enabled: !busy && model.profile!.canEditProfile,
                      maxLength: key == 'platform' ? 128 : 2048,
                      decoration: InputDecoration(
                        labelText: t(key == 'value' ? 'contactValue' : key),
                      ),
                      onChanged: (v) {
                        final list = rows('externalContacts');
                        list[index][key] = v;
                        update('externalContacts', list);
                      },
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? t('required') : null,
                    ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy || !model.profile!.canEditProfile
                  ? null
                  : () {
                      final list = rows('externalContacts')..removeAt(index);
                      structureChanged();
                      update('externalContacts', list);
                    },
              child: Text(t('remove')),
            ),
          ),
        ],
      ),
    );
  }
}
