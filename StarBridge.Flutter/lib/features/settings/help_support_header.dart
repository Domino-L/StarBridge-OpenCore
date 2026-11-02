import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'daily_support_port.dart';
import 'help_support_action.dart';
import 'spiritual_support_button.dart';

class HelpSupportHeader extends StatelessWidget {
  const HelpSupportHeader({this.onOpenScm, this.dailySupport, super.key});
  final ValueChanged<InteractionSource>? onOpenScm;
  final DailySupportPort? dailySupport;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: tokens.space.md,
          runSpacing: tokens.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const StarBridgeAppIcon(size: 58),
            StarBridgeTooltip(
              message: 'SCM · scm.flowcld.com',
              waitDuration:
                  TooltipTheme.of(context).waitDuration ?? Duration.zero,
              child: HelpSupportAction(
                controlKey: const Key('help-scm-team'),
                onActivate: onOpenScm,
                child: const ScmBrandMark(),
              ),
            ),
            SpiritualSupportButton(port: dailySupport),
          ],
        ),
        SizedBox(height: tokens.space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('help.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xxs),
            Text(
              strings.text('help.description'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
