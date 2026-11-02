import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionScope;

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../localization/app_strings.dart';

abstract final class CigFankitLegalNotice {
  static const requiredEnglish =
      'This site is not endorsed by or affiliated with the Cloud Imperium '
      'or Roberts Space Industries group of companies. All game content and '
      'materials are copyright Cloud Imperium Rights LLC and Cloud Imperium '
      'Rights Ltd.. Star Citizen®, Squadron 42®, Roberts Space Industries®, '
      'and Cloud Imperium® are registered trademarks of Cloud Imperium Rights '
      'LLC. All rights reserved.';
}

Future<void> showCigFankitNoticeDialog(BuildContext context) {
  return showStarBridgeDialog<void>(
    context,
    builder: (context) => StarBridgeInteractionConfiguration(
      suite: InteractionScope.of(context).suite,
      reduceMotion: InteractionScope.of(context).reduceMotion,
      child: const _CigFankitNoticeDialog(),
    ),
  );
}

class CigFankitNoticeButton extends StatelessWidget {
  const CigFankitNoticeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final title = strings.text('legal.fankit.inlineAction');
    final style = OutlinedButton.styleFrom(
      foregroundColor: tokens.colors.textPrimary,
      backgroundColor: tokens.surfaces.floating.fill,
      side: BorderSide(
        color: tokens.surfaces.floating.border,
        width: tokens.stroke.regular,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
    ).merge(OutlinedButtonTheme.of(context).style);
    final defaults = OutlinedButton(
      onPressed: () {},
      child: const SizedBox.shrink(),
    ).defaultStyleOf(context);
    final effective = style.merge(defaults);
    final minimum = effective.minimumSize!.resolve({})!;
    final adjustment =
        (effective.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (effective.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final labelStyle = effective.textStyle?.resolve({});
    final icon = StarBridgeIcon(
      StarBridgeIconSemantic.legalNotice,
      size: tokens.icons.small,
    );
    final label = Flexible(
      child: Text(
        title,
        style: labelStyle?.copyWith(
          inherit: false,
          color: tokens.colors.textPrimary,
        ),
      ),
    );
    final alignment =
        OutlinedButtonTheme.of(context).style?.iconAlignment ??
        style.iconAlignment ??
        IconAlignment.start;
    return StarBridgeActionButton(
      nativeStyle: style,
      minHeight: math.max(
        minimum.height + adjustment.dy,
        target + adjustment.dy,
      ),
      padding: effective.padding?.resolve({}),
      semanticLabel: title,
      onActivate: (_) => showCigFankitNoticeDialog(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - (scale - 1) * 4,
        children: alignment == IconAlignment.start
            ? [icon, label]
            : [label, icon],
      ),
    );
  }
}

class CigFankitNoticeContent extends StatelessWidget {
  const CigFankitNoticeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarBridgeIcon(
              StarBridgeIconSemantic.legalNotice,
              color: tokens.colors.info,
              size: tokens.icons.large,
            ),
            SizedBox(width: tokens.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('legal.fankit.title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    strings.text('legal.fankit.summary'),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space.lg),
        Container(
          padding: EdgeInsets.all(tokens.space.md),
          decoration: BoxDecoration(
            color: tokens.colors.infoSoft,
            borderRadius: tokens.shape.small,
            border: Border.all(
              color: tokens.colors.info,
              width: tokens.stroke.hairline,
            ),
          ),
          child: Text(
            strings.text('legal.fankit.nonCommercial'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SizedBox(height: tokens.space.lg),
        Text(
          strings.text('legal.fankit.requiredNotice'),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.xs),
        SelectableText(
          CigFankitLegalNotice.requiredEnglish,
          key: const Key('cig-fankit-required-notice'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
        SizedBox(height: tokens.space.lg),
        Divider(color: tokens.surfaces.panel.border),
        SizedBox(height: tokens.space.md),
        Text(
          strings.text('legal.fankit.watermark'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.xs),
        Text(
          strings.text('legal.fankit.source'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
  }
}

class _CigFankitNoticeDialog extends StatelessWidget {
  const _CigFankitNoticeDialog();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: StarBridgeSurface(
          role: SurfaceRole.floating,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.text('legal.page.title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  StarBridgeNativeIconAction(
                    controlKey: const Key('cig-fankit-notice-close'),
                    label: strings.text('legal.close'),
                    onActivate: (source) =>
                        dismissStarBridgeDialog<void>(context, source: source),
                    icon: const StarBridgeIcon(
                      StarBridgeIconSemantic.windowClose,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.md),
              const Flexible(
                child: SingleChildScrollView(child: CigFankitNoticeContent()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
