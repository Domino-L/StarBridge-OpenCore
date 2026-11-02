import '../../design_system/icons/standard_icon.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_profile_controller.dart';
import 'community_profile_activity_windows.dart';
import 'community_profile_port.dart';
import 'community_profile_copy.dart';
import 'community_creation_port.dart';
import 'community_gameplay_tags.dart';
import 'community_workspace_image.dart';
import 'community_profile_rules.dart';
import 'community_system_choices.dart';
import 'community_profile_language_choices.dart';

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
    this.logoLoadingIndicator,
    this.wideImages,
  });
  final BuildContext context;
  final CommunityProfileController model;
  final CommunityCreationOptions? options;
  final int serial;
  final bool busy, canPickLogo, logoLoading, logoFailed;
  final Uint8List? draftLogoBytes, serverLogoBytes;
  final Widget? logoLoadingIndicator;

  /// Banner/background editor; only shown once the server supports both.
  final Widget? wideImages;
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
    child: StarBridgeFieldFrame(
      enabled: !busy && model.profile!.permits(key),
      builder: (_, focus) => TextFormField(
        focusNode: focus,
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
              : communityProfileEditLimits.containsKey(key) &&
                    key != 'websiteUrl'
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
      child: StarBridgeSelectFormField<String>(
        identity: 'profile-$serial-$key',
        controlKey: ValueKey('profile-$serial-$key-control'),
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

  Widget toggle(String key) => StarBridgeSwitch.tile(
    controlKey: ValueKey('profile-toggle-$key'),
    label: t(key),
    titleWidget: Text(t(key), style: Theme.of(context).textTheme.bodyMedium),
    value: fields[key] == true,
    subtitle:
        key == 'publicListingEnabled' && fields['recruitingEnabled'] == true
        ? t('recruitingLock')
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
                child:
                    draftLogoBytes == null &&
                        logoLoading &&
                        logoLoadingIndicator != null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.tokens.surfaces.raised.fill,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 48,
                            child: logoLoadingIndicator,
                          ),
                        ),
                      )
                    : CommunityWorkspaceImage(
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
                StarBridgeActionButton(
                  controlKey: const Key('profile-pick-logo'),
                  onActivate: !busy && model.profile!.canEditLogo && canPickLogo
                      ? (_) => pickLogo()
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StandardIcon(StandardIconSemantic.image, size: 18),
                      const SizedBox(width: 8),
                      Text(t('pickLogo')),
                    ],
                  ),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('profile-remove-logo'),
                  onActivate: !busy && model.profile!.canEditLogo
                      ? (_) => update('clearLogoImage', true)
                      : null,
                  child: Text(t('removeLogo')),
                ),
                if (model.profile!.hasBanner &&
                    !model.profile!.wideImagesSupported)
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('profile-remove-banner'),
                    onActivate: !busy && model.profile!.canEditBanner
                        ? (_) => update('clearBannerImage', true)
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
      if (wideImages != null && model.profile!.wideImagesSupported) wideImages!,
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
            StarBridgeActionButton(
              controlKey: const Key('profile-choose-tags'),
              onActivate:
                  !busy && model.profile!.canEditProfile && options != null
                  ? (_) => chooseTags()
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
      StarBridgeActionButton(
        controlKey: const Key('profile-add-window'),
        onActivate:
            !busy &&
                model.profile!.canEditProfile &&
                rows('activityWindows').length < 3
            ? (_) {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StandardIcon(StandardIconSemantic.add, size: 18),
            const SizedBox(width: 8),
            Text(t('addWindow')),
          ],
        ),
      ),
    ],
  );
  Widget get languageChoices => CommunityProfileLanguageChoices(
    value: fields['language'] as String? ?? '',
    enabled: !busy && model.profile!.canEditProfile,
    onChanged: (value) => update('language', value),
  );

  CommunityProfileActivityWindows get _activityWindows =>
      CommunityProfileActivityWindows(
        context: context,
        serial: serial,
        readFields: () => fields,
        canEdit: () => !busy && model.profile!.canEditProfile,
        update: update,
        structureChanged: structureChanged,
        box: box,
      );

  Widget window(int index) => _activityWindows.window(index);

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
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('profile-publish-contacts'),
                  onActivate: busy || !model.profile!.canEditProfile
                      ? null
                      : (_) => publishContacts(),
                  child: Text(t('publishContacts')),
                ),
            ],
          ),
        ),
      for (var i = 0; i < rows('externalContacts').length; i++) contact(i),
      StarBridgeActionButton(
        controlKey: const Key('profile-add-contact'),
        onActivate:
            !busy &&
                model.profile!.canEditProfile &&
                rows('externalContacts').length < 5
            ? (_) {
                structureChanged();
                update('externalContacts', [
                  ...rows('externalContacts'),
                  {'platform': '', 'value': ''},
                ]);
              }
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StandardIcon(StandardIconSemantic.add, size: 18),
            const SizedBox(width: 8),
            Text(t('addContact')),
          ],
        ),
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
                  ? StarBridgeSelectFormField<String>(
                      identity: 'profile-contact-$serial-$index-platform',
                      controlKey: ValueKey(
                        'profile-contact-$serial-$index-platform-control',
                      ),
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
                  : StarBridgeFieldFrame(
                      enabled: !busy && model.profile!.canEditProfile,
                      builder: (_, focus) => TextFormField(
                        focusNode: focus,
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
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t('required')
                            : null,
                      ),
                    ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: ValueKey('profile-contact-$serial-$index-remove'),
              onActivate: busy || !model.profile!.canEditProfile
                  ? null
                  : (_) {
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
