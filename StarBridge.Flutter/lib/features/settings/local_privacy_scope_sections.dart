import 'package:flutter/material.dart';

import '../communities/community_logo.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_sharing.dart';
import 'community_member_visibility_dialog.dart';
import 'local_privacy_controller.dart';
import 'local_privacy_settings.dart';
import 'privacy_scope_editor.dart';

class LocalPrivacyRoomSection extends StatelessWidget {
  const LocalPrivacyRoomSection({required this.controller, super.key});

  final LocalPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final draft = controller.draft!;
    return PrivacyScopeEditor(
      scopeKey: 'room',
      tone: PrivacyScopeTone.room,
      icon: StarBridgeIconSemantic.room,
      title: strings.text('privacy.scope.room.title'),
      badge: strings.text('privacy.scope.room.badge'),
      description: strings.text('privacy.scope.room.body'),
      audience: PrivacyAudienceEditor(
        scopeKey: 'room',
        label: strings.text('privacy.scope.audience'),
        choices: [
          PrivacyAudienceChoice(
            id: 'members',
            label: strings.text('privacy.scope.room.members'),
            description: strings.text('privacy.scope.room.membersBody'),
            selected: draft.roomAllMembersCanView,
            enabled: controller.canEdit,
            onChanged: (value) =>
                controller.edit(draft.copyWith(roomAllMembersCanView: value)),
          ),
        ],
      ),
      fieldsLabel: strings.text('privacy.scope.fields'),
      fields: privacyFieldChoices(
        context,
        fields: draft.roomFields,
        enabled: controller.canEdit,
        onChanged: (next) => controller.edit(draft.copyWith(roomFields: next)),
      ),
    );
  }
}

class LocalPrivacyMainFleetPlaceholder extends StatelessWidget {
  const LocalPrivacyMainFleetPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PrivacyScopeEditor(
      scopeKey: 'official-fleet',
      tone: PrivacyScopeTone.officialFleet,
      icon: StarBridgeIconSemantic.officialFleet,
      title: strings.text('privacy.scope.fleet.title'),
      badge: strings.text('privacy.scope.fleet.badge'),
      status: strings.text('privacy.scope.fleet.unavailable'),
      description: strings.text('privacy.scope.fleet.body'),
      fieldsLabel: strings.text('privacy.scope.fields'),
      fields: privacyFieldChoices(
        context,
        fields: 0,
        enabled: false,
        onChanged: (_) {},
      ),
    );
  }
}

class LocalPrivacyOrganizationsSection extends StatelessWidget {
  const LocalPrivacyOrganizationsSection({required this.controller, super.key});

  final LocalPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      key: const Key('privacy-organizations-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.text('privacy.scope.organizations.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: tokens.space.xs),
        Text(
          strings.text('privacy.scope.organizations.body'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.md),
        ..._content(context),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    if (!controller.communitySharingSupported) {
      return [
        const _OrganizationStatePanel(
          key: Key('privacy-organizations-unsupported'),
          titleKey: 'privacy.scope.organizations.unsupported.title',
          bodyKey: 'privacy.scope.organizations.unsupported.body',
        ),
      ];
    }
    if (controller.communityTargetsFailed) {
      final serviceUnavailable =
          controller.communityTargetsFailure ==
          CommunityTargetsFailure.serviceUnavailable;
      return [
        _OrganizationStatePanel(
          key: const Key('privacy-organizations-failed'),
          titleKey: serviceUnavailable
              ? 'privacy.scope.organizations.serviceUnavailable.title'
              : 'privacy.scope.organizations.failed.title',
          bodyKey: serviceUnavailable
              ? 'privacy.scope.organizations.serviceUnavailable.body'
              : 'privacy.scope.organizations.failed.body',
          warning: true,
          action: OutlinedButton.icon(
            onPressed: controller.refreshCommunityTargets,
            icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            label: Text(strings.text('privacy.scope.retry')),
          ),
        ),
      ];
    }
    final targets = controller.communityTargets;
    if (targets == null) {
      return [
        StarBridgeSurface(
          role: SurfaceRole.panel,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: tokens.space.sm),
              Text(strings.text('privacy.scope.organizations.loading')),
            ],
          ),
        ),
      ];
    }
    if (controller.draft!.communities == null) {
      return [_LegacyOrganizationMigration(controller: controller)];
    }
    if (targets.communities.isEmpty) {
      return [
        const _OrganizationStatePanel(
          key: Key('privacy-organizations-empty'),
          titleKey: 'privacy.scope.organizations.empty',
        ),
      ];
    }
    return [
      for (var index = 0; index < targets.communities.length; index++) ...[
        if (index > 0) SizedBox(height: tokens.space.md),
        _OrganizationScopeEditor(
          controller: controller,
          target: targets.communities[index],
        ),
      ],
    ];
  }
}

class _OrganizationScopeEditor extends StatelessWidget {
  const _OrganizationScopeEditor({
    required this.controller,
    required this.target,
  });

  final LocalPrivacyController controller;
  final CommunitySharingTarget target;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scopes = controller.draft!.communities!;
    final scope = scopes.where(target.matches).firstOrNull;
    final choice = scope ?? target.choice();
    final count = _realtimeFieldCount(choice.fields);
    final status = scope == null
        ? strings.text('privacy.scope.organization.pending')
        : count == 0
        ? strings.text('privacy.scope.organization.none')
        : strings
              .text('privacy.scope.organization.active')
              .replaceAll('{count}', '$count');
    final editable = controller.canEdit && !controller.communityTargetsFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrivacyScopeEditor(
          scopeKey: target.code,
          tone: PrivacyScopeTone.organization,
          leading: CommunityLogo(
            data: target.logoImageData,
            size: 36,
            framed: false,
          ),
          icon: StarBridgeIconSemantic.community,
          title: target.name,
          badge: strings.text('privacy.scope.organization.badge'),
          status: status,
          statusPending: scope == null,
          description: strings.text('privacy.scope.organization.body'),
          audience: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrivacyAudienceEditor(
                scopeKey: target.code,
                label: strings.text('privacy.scope.audience'),
                choices: [
                  PrivacyAudienceChoice(
                    id: 'members',
                    label: strings.text('privacy.scope.audience.all'),
                    description: strings.text('privacy.scope.audience.allBody'),
                    selected: choice.allMembersCanView,
                    enabled: editable,
                    onChanged: (value) => controller.editCommunity(
                      choice.copyWith(
                        allMembersCanView: value,
                        administratorsCanView: value
                            ? false
                            : choice.administratorsCanView,
                      ),
                    ),
                  ),
                  PrivacyAudienceChoice(
                    id: 'administrators',
                    label: strings.text('privacy.scope.audience.admins'),
                    description: strings.text(
                      'privacy.scope.audience.adminsBody',
                    ),
                    selected: choice.administratorsCanView,
                    enabled: editable && !choice.allMembersCanView,
                    onChanged: (value) => controller.editCommunity(
                      choice.copyWith(administratorsCanView: value),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: Key('privacy-scope-${target.code}-members'),
                  onPressed:
                      editable && controller.communityMemberSharingSupported
                      ? () => editCommunityMemberVisibility(
                          context,
                          controller,
                          target,
                          choice,
                        )
                      : null,
                  child: Text(strings.text('privacy.member.title')),
                ),
              ),
            ],
          ),
          fieldsLabel: strings.text('privacy.scope.fields'),
          fields: privacyFieldChoices(
            context,
            fields: choice.fields,
            enabled: editable,
            onChanged: (next) =>
                controller.editCommunity(choice.copyWith(fields: next)),
          ),
        ),
        if (scope == null) ...[
          SizedBox(height: context.tokens.space.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: Key('privacy-scope-${target.code}-confirm-none'),
              onPressed: editable
                  ? () => controller.editCommunity(target.choice())
                  : null,
              child: Text(
                strings.text('privacy.scope.organization.confirmNone'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegacyOrganizationMigration extends StatelessWidget {
  const _LegacyOrganizationMigration({required this.controller});

  final LocalPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _OrganizationStatePanel(
      key: const Key('privacy-organizations-migration'),
      titleKey: 'privacy.scope.organizations.migrate.title',
      bodyKey: 'privacy.scope.organizations.migrate.body',
      action: FilledButton(
        key: const Key('privacy-organizations-migrate'),
        onPressed: controller.canEdit
            ? () async {
                final draft = controller.draft;
                final epoch = controller.scopeEpoch;
                final targets = controller.communityTargets;
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      strings.text(
                        'privacy.scope.organizations.migrate.dialogTitle',
                      ),
                    ),
                    content: Text(
                      strings.text(
                        'privacy.scope.organizations.migrate.dialogBody',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(strings.text('privacy.scope.cancel')),
                      ),
                      FilledButton(
                        key: const Key('privacy-organizations-migrate-confirm'),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          strings.text(
                            'privacy.scope.organizations.migrate.confirm',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (accepted == true &&
                    context.mounted &&
                    epoch == controller.scopeEpoch &&
                    identical(draft, controller.draft) &&
                    _sameMembershipTargets(
                      targets,
                      controller.communityTargets,
                    )) {
                  controller.enableCommunityChoices();
                }
              }
            : null,
        child: Text(strings.text('privacy.scope.organizations.migrate.action')),
      ),
    );
  }
}

// Background renewal leaves confirmation valid; actual membership changes do not.
bool _sameMembershipTargets(
  CommunitySharingTargets? before,
  CommunitySharingTargets? after,
) =>
    before != null &&
    after != null &&
    before.primaryFleetCode == after.primaryFleetCode &&
    before.communities.length == after.communities.length &&
    before.communities.every(
      (old) => after.communities.any(
        (next) => old.code == next.code && old.joinedAt == next.joinedAt,
      ),
    );

class _OrganizationStatePanel extends StatelessWidget {
  const _OrganizationStatePanel({
    required this.titleKey,
    this.bodyKey,
    this.warning = false,
    this.action,
    super.key,
  });

  final String titleKey;
  final String? bodyKey;
  final bool warning;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final color = warning ? tokens.colors.warning : tokens.colors.textSecondary;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            warning
                ? StarBridgeIconSemantic.warning
                : StarBridgeIconSemantic.community,
            size: tokens.icons.medium,
            color: color,
          ),
          SizedBox(height: tokens.space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text(titleKey),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (bodyKey case final bodyKey?) ...[
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          if (action case final action?) ...[
            SizedBox(height: tokens.space.md),
            action,
          ],
        ],
      ),
    );
  }
}

List<PrivacyFieldChoice> privacyFieldChoices(
  BuildContext context, {
  required int fields,
  required bool enabled,
  required ValueChanged<int> onChanged,
}) {
  final strings = AppStrings.of(context);
  return [
    for (final entry in const [
      (
        LocalPrivacySettings.presence,
        'presence',
        StarBridgeIconSemantic.activity,
      ),
      (LocalPrivacySettings.ship, 'ship', StarBridgeIconSemantic.hangar),
      (LocalPrivacySettings.location, 'location', StarBridgeIconSemantic.scene),
      (
        LocalPrivacySettings.server,
        'server',
        StarBridgeIconSemantic.statusNetwork,
      ),
    ])
      PrivacyFieldChoice(
        id: entry.$2,
        icon: entry.$3,
        label: strings.text('privacy.scope.field.${entry.$2}'),
        description: strings.text('privacy.scope.field.${entry.$2}Body'),
        selected: fields & entry.$1 != 0,
        enabled: enabled,
        onChanged: (value) =>
            onChanged(value ? fields | entry.$1 : fields & ~entry.$1),
      ),
  ];
}

int _realtimeFieldCount(int fields) => [
  LocalPrivacySettings.presence,
  LocalPrivacySettings.ship,
  LocalPrivacySettings.location,
  LocalPrivacySettings.server,
].where((field) => fields & field != 0).length;
