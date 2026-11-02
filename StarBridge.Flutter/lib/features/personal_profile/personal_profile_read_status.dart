import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../settings/help_support_waiting.dart';
import 'personal_profile_models.dart';

class PersonalProfileLoadingView extends StatelessWidget {
  const PersonalProfileLoadingView({
    this.source = InteractionSource.programmatic,
    super.key,
  });
  final InteractionSource source;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: PersonalProfileReadProgress(
        label: strings.text('profile.loading'),
        source: source,
        initial: true,
      ),
    );
  }
}

/// Paint only: a phase's source never controls admission, retries or data.
class PersonalProfileReadProgress extends StatefulWidget {
  const PersonalProfileReadProgress({
    required this.label,
    required this.source,
    this.initial = false,
    super.key,
  });
  final String label;
  final InteractionSource source;
  final bool initial;

  @override
  State<PersonalProfileReadProgress> createState() => _ReadProgressState();
}

class _ReadProgressState extends State<PersonalProfileReadProgress> {
  InteractionSource? _source;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= resolveStarBridgeInitialReadSource(context, widget.source);
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        if (data.suite != InteractionSuite.standard) {
          return HelpSupportWaiting(label: widget.label, source: _source!);
        }
        final animated =
            _source != InteractionSource.keyboard && !data.reduceMotion;
        if (!widget.initial) {
          return animated
              ? LinearProgressIndicator(
                  minHeight: 2,
                  semanticsLabel: widget.label,
                )
              : Text(widget.label);
        }
        final tokens = context.tokens;
        return Row(
          children: [
            SizedBox.square(
              dimension: tokens.icons.medium,
              child: animated
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            ),
            SizedBox(width: tokens.space.md),
            Flexible(child: Text(widget.label)),
          ],
        );
      },
    ),
  );
}

class PersonalProfileSignedOutView extends StatelessWidget {
  const PersonalProfileSignedOutView({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.profile,
            size: tokens.icons.large,
            color: tokens.colors.accent,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('profile.signedOut.title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('profile.signedOut.body'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class PersonalProfileUnavailableView extends StatelessWidget {
  const PersonalProfileUnavailableView({
    super.key,
    required this.failureKey,
    required this.onRetry,
    required this.retrying,
    this.source = InteractionSource.programmatic,
  });

  final String failureKey;
  final Future<PersonalProfileActionResult> Function() onRetry;
  final bool retrying;
  final InteractionSource source;

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final data = InteractionScope.of(context);
    final animated = source != InteractionSource.keyboard && !data.reduceMotion;
    // A settled answer from the server, not a failed read: asking again would
    // give the same result. The page's own refresh stays for when it changes.
    final notVisible = failureKey == 'profile.visitor.notVisible';
    return StarBridgeSurface(
      key: const Key('profile-unavailable'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.large,
            color: tokens.colors.warning,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text(
              notVisible
                  ? 'profile.unavailable.notVisibleTitle'
                  : 'profile.unavailable.title',
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text(failureKey),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          if (!notVisible) ...[
            SizedBox(height: tokens.space.md),
            StarBridgeActionButton(
              controlKey: const Key('profile-retry'),
              onActivate: retrying ? null : (_) => unawaited(onRetry()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (retrying &&
                      animated &&
                      data.suite == InteractionSuite.standard)
                    SizedBox.square(
                      dimension: tokens.icons.small,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      strings.text(
                        retrying
                            ? 'profile.retrying'
                            : 'profile.unavailable.retry',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (retrying &&
              animated &&
              data.suite != InteractionSuite.standard) ...[
            SizedBox(height: tokens.space.sm),
            const ExcludeSemantics(
              child: SuiteProgressBar(
                value: null,
                phase: ProgressPhase.running,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
