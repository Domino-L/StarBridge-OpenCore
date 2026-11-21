import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/standard_icon.dart';
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

  // Three ways to reach us (user 11-16): the StarBridge QQ group, the SCM
  // team QQ group (also the "join us" group), and email. Each copies on tap.
  // The two groups show their own brand marks (user 11-16); email keeps the
  // design-system glyph.
  static const contacts = <HelpSupportContact>[
    HelpSupportContact(
      id: 'group',
      value: '534268220',
      icon: StarBridgeIconSemantic.friends,
      brand: HelpSupportContactBrand.starBridge,
    ),
    HelpSupportContact(
      id: 'teamGroup',
      value: '588620092',
      icon: StarBridgeIconSemantic.community,
      brand: HelpSupportContactBrand.scm,
    ),
    HelpSupportContact(
      id: 'email',
      value: 'scstarbridge.app@gmail.com',
      icon: StarBridgeIconSemantic.messages,
    ),
  ];

  final Widget heading;
  final Widget unavailableNotice;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        SizedBox(height: tokens.space.md),
        unavailableNotice,
        for (final contact in contacts) ...[
          SizedBox(height: tokens.space.md),
          _ContactCard(contact: contact),
        ],
      ],
    );
  }
}

enum HelpSupportContactBrand { starBridge, scm }

class HelpSupportContact {
  const HelpSupportContact({
    required this.id,
    required this.value,
    required this.icon,
    this.brand,
  });

  final String id;
  final String value;

  /// Fallback glyph, used when [brand] is null.
  final StarBridgeIconSemantic icon;
  final HelpSupportContactBrand? brand;

  String get _keySuffix => switch (id) {
    'group' => 'group',
    'teamGroup' => 'team-group',
    _ => id,
  };
  Key get cardKey => Key('help-feedback-$_keySuffix');
  Key get copyKey => Key('help-copy-feedback-$_keySuffix');
  Key get markKey => Key('help-feedback-mark-$_keySuffix');
  String text(AppStrings strings, String part) =>
      strings.text('help.feedback.$id.$part');
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final HelpSupportContact contact;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: contact.cardKey,
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
                child: KeyedSubtree(
                  key: contact.markKey,
                  child: _ContactMark(contact: contact),
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.text(strings, 'title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xs),
                    Text(
                      contact.text(strings, 'body'),
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
                contact.text(strings, 'number'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              HelpSupportAction(
                kind: StarBridgeActionKind.primary,
                controlKey: contact.copyKey,
                onActivate: (source) => _copy(context, source),
                customIcon: const StandardIcon(StandardIconSemantic.copy),
                child: Text(contact.text(strings, 'copy')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, InteractionSource source) async {
    await Clipboard.setData(ClipboardData(text: contact.value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        starBridgeSnackBarFromContext(
          context,
          starBridgeTimedSnackBar(
            content: Text(contact.text(AppStrings.of(context), 'copied')),
          ),
          source: source,
        ),
      );
  }
}

/// The small mark inside a contact card's 38-px tile. Brand marks stay within
/// the tile; the SCM artwork is light grey, so on a light theme it takes the
/// text colour, as the unframed header mark does.
class _ContactMark extends StatelessWidget {
  const _ContactMark({required this.contact});

  static const markExtent = 26.0;

  final HelpSupportContact contact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return switch (contact.brand) {
      HelpSupportContactBrand.starBridge => const StarBridgeAppIcon(
        size: markExtent,
      ),
      HelpSupportContactBrand.scm => Image.asset(
        ScmBrandMark.markAssetPath,
        width: markExtent,
        height: markExtent,
        color: Theme.of(context).brightness == Brightness.light
            ? tokens.colors.textPrimary
            : null,
        colorBlendMode: Theme.of(context).brightness == Brightness.light
            ? BlendMode.srcIn
            : null,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
      null => StarBridgeIcon(contact.icon, color: tokens.colors.accent),
    };
  }
}
