import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_privacy_controller.dart';

class PrivacyLiveSharingPanel extends StatelessWidget {
  const PrivacyLiveSharingPanel({required this.controller, super.key});

  final LocalPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final draft = controller.draft!;
    final canRecover =
        controller.publicationSupported &&
        controller.hasSaved &&
        draft.publicationEnabled &&
        const {'inactive', 'failed'}.contains(controller.publicationView.state);
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
        : controller.publicationView.state;
    final active = const {'applied', 'legacyApplied'}.contains(liveState);
    final attention = canRecover || liveState == 'withdrawalPending';
    final failure = switch (controller.publicationView.errorCode) {
      'privacy_publication.identity_required' ||
      'privacy_publication.identity_unavailable' => 'identity',
      'privacy_publication.forbidden' => 'denied',
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
              Semantics(
                label: strings.text('privacy.scope.global.enabled'),
                child: Switch(
                  key: const Key('privacy-publication'),
                  value: draft.publicationEnabled,
                  onChanged: controller.canEdit
                      ? (value) => controller.edit(
                          draft.copyWith(publicationEnabled: value),
                        )
                      : null,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('privacy.scope.live.$liveState'),
            key: const Key('privacy-publication-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (controller.publicationView.state == 'failed' ||
              controller.publicationView.state == 'withdrawalPending') ...[
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text('privacy.scope.failure.$failure'),
              key: const Key('privacy-publication-reason'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (canRecover) ...[
            SizedBox(height: tokens.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('privacy-reapply'),
                onPressed: controller.canEdit && !controller.dirty
                    ? controller.applyPublication
                    : null,
                child: Text(strings.text('privacy.scope.live.reapply')),
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
