import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import 'help_support_action.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class HelpSupportFeedbackContent extends StatelessWidget {
  const HelpSupportFeedbackContent({
    required this.heading,
    required this.unavailableNotice,
    super.key,
  });

  static const _groupNumber = '534268220';

  final Widget heading;
  final Widget unavailableNotice;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        SizedBox(height: tokens.space.md),
        unavailableNotice,
        SizedBox(height: tokens.space.md),
        StarBridgeSurface(
          key: const Key('help-feedback-group'),
          role: SurfaceRole.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.colors.accentSoft,
                      borderRadius: tokens.shape.small,
                    ),
                    child: StarBridgeIcon(
                      StarBridgeIconSemantic.friends,
                      color: tokens.colors.accent,
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('help.feedback.group.title'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: tokens.space.xs),
                        Text(
                          strings.text('help.feedback.group.body'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: tokens.colors.textSecondary,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.lg),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText(
                    strings.text('help.feedback.group.number'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  HelpSupportAction(
                    kind: StarBridgeActionKind.primary,
                    controlKey: const Key('help-copy-feedback-group'),
                    onActivate: (source) => _copyGroup(context, source),
                    icon: StarBridgeIconSemantic.notifications,
                    child: Text(strings.text('help.feedback.group.copy')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _copyGroup(
    BuildContext context,
    InteractionSource source,
  ) async {
    await Clipboard.setData(const ClipboardData(text: _groupNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        starBridgeSnackBarFromContext(
          context,
          starBridgeTimedSnackBar(
            content: Text(
              AppStrings.of(context).text('help.feedback.group.copied'),
            ),
          ),
          source: source,
        ),
      );
  }
}
