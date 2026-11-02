import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_profile_controller.dart';
import 'community_profile_copy.dart';
import '../common/social_read_activity.dart';

/// Editor chrome only; the original dialog owns operations and draft lifetime.
class CommunityProfileEditorHeader extends StatelessWidget {
  const CommunityProfileEditorHeader({
    required this.model,
    required this.embedded,
    required this.choosing,
    required this.optionsFailed,
    required this.localError,
    required this.onLeave,
    required this.onRetryOptions,
    this.loadingIndicator,
    this.optionsActivity,
    super.key,
  });
  final CommunityProfileController model;
  final bool embedded, choosing, optionsFailed;
  final String? localError;
  final Future<void> Function() onLeave, onRetryOptions;
  final Widget? loadingIndicator, optionsActivity;
  @override
  Widget build(BuildContext context) {
    String t(String key) => profileText(context, key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('editProfile'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!embedded)
              StarBridgeIconAction(
                controlKey: const Key('profile-close'),
                onActivate: model.submitting || choosing
                    ? null
                    : (_) => onLeave(),
                label: t('close'),
                icon: const StandardIcon(StandardIconSemantic.close),
              ),
          ],
        ),
        if (model.loading)
          loadingIndicator ??
              SocialReadActivity(
                source: InteractionSource.programmatic,
                opening: false,
                label: t('loading'),
                height: 4,
              ),
        if (!model.loading && optionsActivity != null) optionsActivity!,
        if (optionsFailed)
          Row(
            children: [
              Expanded(child: Text(t('optionsFailed'))),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('profile-options-retry'),
                onActivate: (_) => onRetryOptions(),
                child: Text(t('reload')),
              ),
            ],
          ),
        if (localError != null || model.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              t(localError ?? model.error!),
              style: TextStyle(color: context.tokens.colors.warning),
            ),
          ),
      ],
    );
  }
}

class CommunityProfileEditorActions extends StatelessWidget {
  const CommunityProfileEditorActions({
    required this.model,
    required this.busy,
    required this.choosing,
    required this.embedded,
    required this.onReload,
    required this.onDiscard,
    required this.onSave,
    this.activity,
    super.key,
  });
  final CommunityProfileController model;
  final bool busy, choosing, embedded;
  final Future<void> Function() onReload, onDiscard, onSave;
  final Widget? activity;
  @override
  Widget build(BuildContext context) {
    String t(String key) => profileText(context, key);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          t(
            model.submitting
                ? 'saving'
                : model.dirty
                ? 'dirty'
                : model.outcome?.status == 'accepted'
                ? 'saved'
                : 'clean',
          ),
        ),
        if (activity != null)
          SizedBox(width: 80, child: ExcludeSemantics(child: activity!)),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('profile-reload'),
          onActivate: model.submitting || choosing ? null : (_) => onReload(),
          child: Text(t('reload')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('profile-discard'),
          onActivate: !busy && model.dirty ? (_) => onDiscard() : null,
          child: Text(t('discard')),
        ),
        StarBridgeTooltip(
          message: embedded ? t('saveProfileDraft') : '',
          child: StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('profile-save'),
            onActivate: !busy && model.canSave ? (_) => onSave() : null,
            child: Text(t('save')),
          ),
        ),
      ],
    );
  }
}
