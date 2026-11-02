import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../communities/community_logo.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_sharing.dart';
import 'community_member_visibility_dialog.dart';
import 'local_privacy_controller.dart';
import 'local_privacy_settings.dart';
import 'official_runtime_privacy_port.dart';
import '../official_fleet/official_fleet_audience_picker.dart';
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
  const LocalPrivacyMainFleetPlaceholder({this.controller, super.key});
  final LocalPrivacyController? controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final owner = controller;
    final supported = owner?.officialRuntimePrivacySupported == true;
    final scope = owner?.officialScope;
    final status = !supported
        ? 'privacy.scope.fleet.unavailable'
        : owner!.officialScopeReading ||
              scope == null && !owner.officialScopeFailed
        ? 'privacy.official.loading'
        : owner.officialScopeFailed
        ? 'privacy.official.failed'
        : scope?.state != 'available'
        ? 'privacy.official.unavailable'
        : owner.officialCancelSavedScope
        ? 'privacy.official.cancelPending'
        : scope!.savedForCurrentSource
        ? 'privacy.official.selected'
        : 'privacy.official.unselected';
    return PrivacyScopeEditor(
      scopeKey: 'official-fleet',
      tone: PrivacyScopeTone.officialFleet,
      icon: StarBridgeIconSemantic.officialFleet,
      title: strings.text('privacy.scope.fleet.title'),
      status: strings.text(status),
      statusPending: supported && scope?.savedForCurrentSource != true,
      description: strings.text(
        supported ? 'privacy.official.body' : 'privacy.scope.fleet.body',
      ),
      audience: !supported
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.text('privacy.official.audience')),
                if (scope?.audienceRankSupported == true) ...[
                  const SizedBox(height: 8),
                  Text(strings.text('privacy.official.audienceLabel')),
                  const SizedBox(height: 8),
                  OfficialFleetAudiencePicker(
                    keyPrefix: 'privacy-official-audience',
                    value: owner!.officialDraftAudience,
                    onChanged: owner.canEditOfficial
                        ? owner.editOfficialAudience
                        : null,
                  ),
                  Text(strings.text('privacy.official.audienceHint')),
                ],
                if (scope?.canCancel == true && !scope!.savedForCurrentSource)
                  Text(strings.text('privacy.official.previous')),
                if (owner!.officialScopeFailed)
                  StarBridgeActionButton(
                    controlKey: const Key('privacy-official-retry'),
                    onActivate: owner.saving || owner.publicationBusy
                        ? null
                        : (_) => owner.refreshOfficialRuntimePrivacy(),
                    child: Text(strings.text('privacy.scope.retry')),
                  ),
                if (owner.officialSaveStage != OfficialPrivacySaveStage.idle)
                  Text(
                    strings.text(
                      'privacy.official.stage.${owner.officialSaveStage.name}',
                    ),
                    key: const Key('privacy-official-save-stage'),
                  ),
              ],
            ),
      fieldsLabel: strings.text('privacy.scope.fields'),
      fields: privacyFieldChoices(
        context,
        fields: supported ? owner!.officialDraftFields ?? 0 : 0,
        enabled:
            supported &&
            (owner!.canEditOfficial ||
                owner.canCancelOfficial && !owner.officialCancelSavedScope),
        onChanged: (fields) => owner!.canEditOfficial
            ? owner.editOfficialFields(fields)
            : owner.chooseCancelSavedOfficialScope(),
      ),
    );
  }
}

class LocalPrivacyOrganizationsSection extends StatefulWidget {
  const LocalPrivacyOrganizationsSection({
    required this.controller,
    this.onlyCode,
    super.key,
  });

  final LocalPrivacyController controller;

  /// One organization alone, on its own page, without this section's heading.
  final String? onlyCode;

  @override
  State<LocalPrivacyOrganizationsSection> createState() =>
      _LocalPrivacyOrganizationsSectionState();
}

class _LocalPrivacyOrganizationsSectionState
    extends State<LocalPrivacyOrganizationsSection> {
  LocalPrivacyController get controller => widget.controller;
  Object? _retryToken;
  InteractionSource _retrySource = InteractionSource.programmatic;

  @override
  void didUpdateWidget(LocalPrivacyOrganizationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) _retryToken = null;
  }

  Future<void> _retry(InteractionSource source) async {
    if (!mounted ||
        _retryToken != null ||
        !controller.communitySharingSupported ||
        !controller.communityTargetsFailed) {
      return;
    }
    final owner = controller, token = Object();
    setState(() {
      _retryToken = token;
      _retrySource = source;
    });
    try {
      await owner.refreshCommunityTargets();
    } finally {
      if (mounted && controller == owner && identical(_retryToken, token)) {
        setState(() => _retryToken = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      key: const Key('privacy-organizations-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onlyCode == null) ...[
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
        ],
        ..._content(context),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final owner = controller, epoch = controller.scopeEpoch;
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
          action: StarBridgeActionButton(
            controlKey: const Key('privacy-organizations-retry'),
            onActivate: _retryToken == null
                ? (source) {
                    if (mounted &&
                        controller == owner &&
                        controller.scopeEpoch == epoch) {
                      _retry(source);
                    }
                  }
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_retryToken != null)
                  SizedBox(
                    width: 40,
                    child: _OrganizationWaiting(source: _retrySource),
                  )
                else
                  const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                SizedBox(width: tokens.space.xs),
                Text(strings.text('privacy.scope.retry')),
              ],
            ),
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
              SizedBox(
                width: 40,
                child: _OrganizationWaiting(
                  source: resolveStarBridgeInitialReadSource(
                    context,
                    InteractionSource.programmatic,
                  ),
                ),
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
    final only = widget.onlyCode?.toLowerCase();
    final shown = only == null
        ? targets.communities
        : targets.communities
              .where((target) => target.code.toLowerCase() == only)
              .toList();
    if (shown.isEmpty) {
      return [
        const _OrganizationStatePanel(
          key: Key('privacy-organizations-empty'),
          titleKey: 'privacy.scope.organizations.empty',
        ),
      ];
    }
    return [
      for (var index = 0; index < shown.length; index++) ...[
        if (index > 0) SizedBox(height: tokens.space.md),
        _OrganizationScopeEditor(controller: controller, target: shown[index]),
      ],
    ];
  }
}

class _OrganizationWaiting extends StatelessWidget {
  const _OrganizationWaiting({required this.source});
  final InteractionSource source;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: const SuiteProgressBar(
            value: null,
            phase: ProgressPhase.running,
          ),
        );
      },
    ),
  );
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
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: Key('privacy-scope-${target.code}-members'),
                  onActivate:
                      editable && controller.communityMemberSharingSupported
                      ? (source) => editCommunityMemberVisibility(
                          context,
                          controller,
                          target,
                          choice,
                          source: source,
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
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: Key('privacy-scope-${target.code}-confirm-none'),
              onActivate: editable
                  ? (_) => controller.editCommunity(target.choice())
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

class _LegacyOrganizationMigration extends StatefulWidget {
  const _LegacyOrganizationMigration({required this.controller});

  final LocalPrivacyController controller;

  @override
  State<_LegacyOrganizationMigration> createState() =>
      _LegacyOrganizationMigrationState();
}

class _LegacyOrganizationMigrationState
    extends State<_LegacyOrganizationMigration> {
  StarBridgeDialogRoute<bool>? _route;
  Object? _draft;
  int? _epoch;
  CommunitySharingTargets? _targets;

  bool get _current =>
      mounted &&
      widget.controller.canEdit &&
      !widget.controller.communityTargetsFailed &&
      _epoch == widget.controller.scopeEpoch &&
      identical(_draft, widget.controller.draft) &&
      _sameMembershipTargets(_targets, widget.controller.communityTargets);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  void _retire() {
    final route = _route;
    _route = null;
    retireStarBridgeDialog(route);
  }

  void _check() {
    if (_route != null && !_current) _retire();
  }

  @override
  void didUpdateWidget(_LegacyOrganizationMigration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_check);
      _retire();
      widget.controller.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    _retire();
    super.dispose();
  }

  Future<void> _open(InteractionSource source) async {
    if (!mounted ||
        _route != null ||
        !widget.controller.canEdit ||
        widget.controller.communityTargetsFailed) {
      return;
    }
    _draft = widget.controller.draft;
    _epoch = widget.controller.scopeEpoch;
    _targets = widget.controller.communityTargets;
    final strings = AppStrings.of(context);
    StarBridgeDialogRoute<bool>? owned;
    final accepted = await showStarBridgeDialog<bool>(
      context,
      source: source,
      onRouteCreated: (route) => _route = owned = route,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          strings.text('privacy.scope.organizations.migrate.dialogTitle'),
        ),
        content: Text(
          strings.text('privacy.scope.organizations.migrate.dialogBody'),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('privacy-organizations-migrate-cancel'),
            onActivate: (source) {
              if (_route != owned || !_current) return;
              dismissStarBridgeDialog(
                dialogContext,
                source: source,
                result: false,
              );
            },
            child: Text(strings.text('privacy.scope.cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('privacy-organizations-migrate-confirm'),
            onActivate: (source) {
              if (_route != owned || !_current) return;
              dismissStarBridgeDialog(
                dialogContext,
                source: source,
                result: true,
              );
            },
            child: Text(
              strings.text('privacy.scope.organizations.migrate.confirm'),
            ),
          ),
        ],
      ),
    );
    if (_route != owned) return;
    _route = null;
    if (accepted == true && _current) {
      widget.controller.enableCommunityChoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final owner = widget.controller, epoch = widget.controller.scopeEpoch;
    return _OrganizationStatePanel(
      key: const Key('privacy-organizations-migration'),
      titleKey: 'privacy.scope.organizations.migrate.title',
      bodyKey: 'privacy.scope.organizations.migrate.body',
      action: StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        controlKey: const Key('privacy-organizations-migrate'),
        onActivate:
            widget.controller.canEdit &&
                !widget.controller.communityTargetsFailed
            ? (source) {
                if (mounted &&
                    widget.controller == owner &&
                    widget.controller.scopeEpoch == epoch) {
                  _open(source);
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
