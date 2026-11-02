import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';
import 'local_privacy_controller.dart';
import 'sharing_status_presentation.dart';

class PrivacyLiveSharingPanel extends StatefulWidget {
  const PrivacyLiveSharingPanel({required this.controller, super.key});

  final LocalPrivacyController controller;

  @override
  State<PrivacyLiveSharingPanel> createState() =>
      _PrivacyLiveSharingPanelState();
}

class _PrivacyLiveSharingPanelState extends State<PrivacyLiveSharingPanel> {
  LocalPrivacyController get controller => widget.controller;
  Object? _readToken;
  LocalPrivacyController? _readOwner;
  int? _readEpoch;
  InteractionSource _readSource = InteractionSource.programmatic;

  Future<void> _refreshStatus(InteractionSource source) async {
    // Presentation follows this explicit read, not the publication mutation.
    // Reentry still reaches the original controller's own read admission guard.
    if (_readToken != null &&
        identical(_readOwner, controller) &&
        _readEpoch == controller.scopeEpoch) {
      await controller.refreshPublication();
      return;
    }
    final token = Object();
    final owner = controller;
    setState(() {
      _readToken = token;
      _readOwner = owner;
      _readEpoch = owner.scopeEpoch;
      _readSource = source;
    });
    try {
      await owner.refreshPublication();
    } finally {
      if (mounted && identical(_readToken, token)) {
        setState(() => _readToken = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final draft = controller.draft!;
    final readUnavailable = controller.publicationReadFailures >= 2;
    final detail = readUnavailable
        ? 'statusRead'
        : sharingStatusIssue(controller.publicationView, controller.revision);
    final canRecover =
        controller.publicationSupported &&
        controller.hasSaved &&
        draft.publicationEnabled &&
        const {
          'inactive',
          'withdrawn',
          'failed',
          'reconnecting',
        }.contains(controller.publicationView.state);
    final liveState = !controller.publicationSupported
        ? 'unsupported'
        : canRecover && controller.publicationView.state == 'inactive'
        ? 'notRunning'
        : controller.publicationView.state == 'applied' &&
              controller.publicationView.revision != controller.revision
        ? 'pending'
        : controller.publicationView.state == 'applied' &&
              controller.communityTargetsFailure ==
                  CommunityTargetsFailure.serviceUnavailable
        ? 'legacyApplied'
        : controller.publicationView.state == 'applied' &&
              controller.savedCommunityChoicesPending
        ? 'organizationPending'
        : controller.publicationView.state;
    final active =
        !readUnavailable &&
        const {
          'applied',
          'legacyApplied',
          'organizationPending',
        }.contains(liveState);
    final attention = canRecover || liveState == 'withdrawalPending';
    final failure = switch (controller.publicationView.errorCode) {
      'privacy_publication.identity_required' ||
      'privacy_publication.identity_unavailable' => 'identity',
      'privacy_publication.forbidden' => 'denied',
      'privacy_publication.rejected' => 'rejected',
      'privacy_publication.response_invalid' ||
      'privacy_publication.route_retired' => 'contract',
      'privacy_local.conflict' ||
      'privacy_local.refresh_required' ||
      'privacy_publication.refresh_required' => 'changed',
      _ => 'connection',
    };
    return StarBridgeSurface(
      key: const Key('privacy-live-sharing'),
      role: SurfaceRole.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? tokens.colors.successSoft
                      : tokens.colors.accentSoft,
                  borderRadius: tokens.shape.small,
                ),
                child: StarBridgeIcon(
                  active
                      ? StarBridgeIconSemantic.connected
                      : attention
                      ? StarBridgeIconSemantic.warning
                      : StarBridgeIconSemantic.privacy,
                  size: tokens.icons.medium,
                  color: active
                      ? tokens.colors.success
                      : tokens.colors.textSecondary,
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('privacy.scope.global.title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text('privacy.scope.global.body'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.space.md),
              StarBridgeSwitch(
                label: strings.text('privacy.scope.global.enabled'),
                controlKey: const Key('privacy-publication'),
                value: draft.publicationEnabled,
                onChanged: controller.canEdit
                    ? (value) => controller.edit(
                        draft.copyWith(publicationEnabled: value),
                      )
                    : null,
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text(
              readUnavailable
                  ? 'privacy.notice.statusRead.title'
                  : const {
                      'signIn',
                      'permission',
                      'contract',
                      'rejected',
                      'service',
                      'retired',
                    }.contains(detail)
                  ? 'privacy.notice.$detail.title'
                  : 'privacy.scope.live.$liveState',
            ),
            key: const Key('privacy-publication-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (detail != null && detail != 'waiting' && detail != 'paused') ...[
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text(
                detail == 'failed'
                    ? 'privacy.scope.failure.$failure'
                    : 'privacy.notice.$detail.body',
              ),
              key: const Key('privacy-publication-reason'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (canRecover || readUnavailable) ...[
            SizedBox(height: tokens.space.sm),
            if (_readToken != null &&
                identical(_readOwner, controller) &&
                _readEpoch == controller.scopeEpoch) ...[
              HelpSupportWaiting(
                key: ObjectKey(_readToken),
                label: strings.text('privacy.local.loading'),
                source: _readSource,
              ),
              SizedBox(height: tokens.space.sm),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: HelpSupportAction(
                controlKey: const Key('privacy-reapply'),
                kind: StarBridgeActionKind.secondary,
                onActivate: readUnavailable
                    ? _refreshStatus
                    : controller.canRetryPublication
                    ? (_) => controller.applyPublication()
                    : null,
                child: Text(
                  strings.text(
                    controller.publicationView.state == 'reconnecting'
                        ? 'privacy.notice.retry'
                        : 'privacy.scope.live.reapply',
                  ),
                ),
              ),
            ),
            if (controller.dirty)
              Text(
                strings.text('privacy.scope.live.saveFirst'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

