import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class OfficialFleetLoadingView extends StatelessWidget {
  const OfficialFleetLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: tokens.space.md),
          Text(AppStrings.of(context).text('officialFleet.loading')),
        ],
      ),
    );
  }
}

class OfficialFleetSignedOutView extends StatelessWidget {
  const OfficialFleetSignedOutView({super.key});

  @override
  Widget build(BuildContext context) => const OfficialFleetStatePanel(
    icon: StarBridgeIconSemantic.login,
    titleKey: 'officialFleet.signedOut.title',
    bodyKey: 'officialFleet.signedOut.body',
    showScmBrand: true,
  );
}

class OfficialFleetNotMemberView extends StatelessWidget {
  const OfficialFleetNotMemberView({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => OfficialFleetStatePanel(
    key: const Key('official-fleet-not-member'),
    icon: StarBridgeIconSemantic.officialFleet,
    titleKey: 'officialFleet.notMember.title',
    bodyKey: 'officialFleet.notMember.body',
    actionKey: 'officialFleet.action.retry',
    onAction: onRetry,
  );
}

class OfficialFleetUnavailableView extends StatelessWidget {
  const OfficialFleetUnavailableView({
    required this.failureKey,
    required this.onRetry,
    super.key,
  });

  final String failureKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => OfficialFleetStatePanel(
    key: const Key('official-fleet-unavailable'),
    icon: StarBridgeIconSemantic.warning,
    color: context.tokens.colors.warning,
    titleKey: 'officialFleet.unavailable.title',
    bodyKey: failureKey,
    actionKey: 'officialFleet.action.retry',
    onAction: onRetry,
  );
}

class OfficialFleetStatePanel extends StatelessWidget {
  const OfficialFleetStatePanel({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    this.color,
    this.actionKey,
    this.onAction,
    this.showScmBrand = false,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String bodyKey;
  final Color? color;
  final String? actionKey;
  final Future<void> Function()? onAction;
  final bool showScmBrand;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final resolvedColor = color ?? tokens.colors.accent;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showScmBrand)
              const ScmBrandMark(key: Key('official-fleet-scm-brand'))
            else
              StarBridgeIcon(
                icon,
                size: tokens.icons.large,
                color: resolvedColor,
              ),
            SizedBox(height: tokens.space.md),
            Text(
              strings.text(titleKey),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text(bodyKey),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            if (actionKey != null && onAction != null) ...[
              SizedBox(height: tokens.space.lg),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                label: Text(strings.text(actionKey!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
