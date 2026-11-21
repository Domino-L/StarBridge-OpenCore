import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/github_mark.dart';
import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'daily_support_port.dart';
import 'help_support_action.dart';

class HelpSupportHeader extends StatelessWidget {
  const HelpSupportHeader({
    this.onOpenScm,
    this.onOpenWebsite,
    this.onOpenGitHub,
    this.dailySupport,
    this.scmHost = 'scm.flowcld.com',
    super.key,
  });
  static const websiteHost = 'scstarbridge.com';
  static const gitHubPath = 'github.com/Domino-L/StarBridge-OpenCore';
  final ValueChanged<InteractionSource>? onOpenScm;
  // Our website and public repository (user 11-16); both open in the browser.
  final ValueChanged<InteractionSource>? onOpenWebsite;
  final ValueChanged<InteractionSource>? onOpenGitHub;
  final String scmHost;
  // The daily support button is not shown (user 11-10: "不展示这个按钮"); the
  // port stays so the button can come back with one line.
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
            StarBridgeTooltip(
              message: '${strings.text('help.website.tooltip')} · $websiteHost',
              waitDuration:
                  TooltipTheme.of(context).waitDuration ?? Duration.zero,
              child: HelpSupportAction(
                controlKey: const Key('help-starbridge-website'),
                onActivate: onOpenWebsite,
                child: const StarBridgeAppIcon(size: 58),
              ),
            ),
            StarBridgeTooltip(
              message: 'SCM · $scmHost',
              waitDuration:
                  TooltipTheme.of(context).waitDuration ?? Duration.zero,
              child: HelpSupportAction(
                controlKey: const Key('help-scm-team'),
                onActivate: onOpenScm,
                child: const ScmBrandMark(framed: false),
              ),
            ),
            StarBridgeTooltip(
              message: 'GitHub · $gitHubPath',
              waitDuration:
                  TooltipTheme.of(context).waitDuration ?? Duration.zero,
              child: HelpSupportAction(
                controlKey: const Key('help-github'),
                onActivate: onOpenGitHub,
                child: const GitHubMark(),
              ),
            ),
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
