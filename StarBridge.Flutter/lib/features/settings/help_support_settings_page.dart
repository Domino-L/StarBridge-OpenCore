import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/legal/starbridge_third_party_licenses.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'client_license_dialog.dart';
import 'client_version_dialog.dart';
import 'help_support_feedback_content.dart';
import 'settings_entry_dialog.dart';
import 'help_support_port.dart';
import 'help_support_live_content.dart';
import 'daily_support_port.dart';
import 'help_support_header.dart';
import 'help_support_action.dart';
import 'help_support_disclosure.dart';
import 'help_support_topic_transition.dart';
import '../onboarding/first_use_setup_entry.dart';
import '../onboarding/onboarding_copy.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

enum HelpSupportTopic { gameLog, notices, updates, feedback }

class HelpSupportSettingsPage extends StatefulWidget {
  const HelpSupportSettingsPage({
    this.initialTopic = HelpSupportTopic.gameLog,
    this.port,
    this.dailySupport,
    super.key,
  });

  final HelpSupportTopic initialTopic;
  final HelpSupportPort? port;
  final DailySupportPort? dailySupport;

  @override
  State<HelpSupportSettingsPage> createState() =>
      _HelpSupportSettingsPageState();
}

class _HelpSupportSettingsPageState extends State<HelpSupportSettingsPage> {
  late HelpSupportTopic _selected;
  bool _topicInstant = false;
  InteractionSource _topicSource = InteractionSource.programmatic;
  final _feedbackContact = TextEditingController();
  final _feedbackMessage = TextEditingController();

  @override
  void dispose() {
    _feedbackContact.dispose();
    _feedbackMessage.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTopic;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SingleChildScrollView(
      key: const Key('settings-help-support-page'),
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HelpSupportHeader(
                onOpenScm: widget.port == null ? null : _openScm,
                dailySupport: widget.dailySupport,
              ),
              SizedBox(height: tokens.space.lg),
              if (FirstUseSetupEntry.of(context) case final open?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: HelpSupportAction(
                    controlKey: const Key('first-use-setup-entry'),
                    onActivate: (_) => open(context),
                    child: Text(
                      OnboardingCopy(Localizations.localeOf(context))
                          .text('entry'),
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 232,
                          child: _TopicNavigation(
                            selected: _selected,
                            onSelect: _select,
                            vertical: true,
                          ),
                        ),
                        SizedBox(width: tokens.space.lg),
                        Expanded(child: _topicContent()),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopicNavigation(
                        selected: _selected,
                        onSelect: _select,
                        vertical: false,
                      ),
                      SizedBox(height: tokens.space.lg),
                      _topicContent(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(HelpSupportTopic topic, InteractionSource source) {
    if (topic != _selected) {
      setState(() {
        _selected = topic;
        _topicInstant = source != InteractionSource.pointer;
        _topicSource = source;
      });
    }
  }

  Future<void> _openScm(InteractionSource source) async {
    try {
      final result = await widget.port!.read('helpSupport.openScm');
      if (result['schemaVersion'] != 1 || result['opened'] != true) {
        throw const FormatException('Unconfirmed browser launch');
      }
    } catch (_) {
      if (!mounted) return;
      showStarBridgeSnackBar(
        context,
        starBridgeTimedSnackBar(
          content: Text(AppStrings.of(context).text('help.scm.openFailed')),
        ),
        source: source,
      );
    }
  }

  Widget _topicContent() => starBridgeInitialReadViewport(
    context,
    source: resolveStarBridgeInitialReadSource(context, _topicSource),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 130),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => HelpSupportTopicTransition(
        animation: animation,
        instant: _topicInstant,
        child: child,
      ),
      child: switch (_selected) {
        HelpSupportTopic.gameLog => const _GameLogHelp(
          key: Key('help-topic-game-log'),
        ),
        HelpSupportTopic.notices => const _NoticesHelp(
          key: Key('help-topic-notices'),
        ),
        HelpSupportTopic.updates => _UpdatesHelp(
          key: Key('help-topic-updates'),
          port: widget.port,
        ),
        HelpSupportTopic.feedback => _FeedbackHelp(
          key: Key('help-topic-feedback'),
          port: widget.port,
          contact: _feedbackContact,
          message: _feedbackMessage,
        ),
      },
    ),
  );
}

class _TopicNavigation extends StatelessWidget {
  const _TopicNavigation({
    required this.selected,
    required this.onSelect,
    required this.vertical,
  });

  final HelpSupportTopic selected;
  final void Function(HelpSupportTopic, InteractionSource) onSelect;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final topic in HelpSupportTopic.values)
        _TopicButton(
          topic: topic,
          selected: selected == topic,
          onPressed: (source) => onSelect(topic, source),
        ),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              SizedBox(height: context.tokens.space.xs),
          ],
        ],
      );
    }
    return Wrap(
      spacing: context.tokens.space.xs,
      runSpacing: context.tokens.space.xs,
      children: children,
    );
  }
}

class _TopicButton extends StatelessWidget {
  const _TopicButton({
    required this.topic,
    required this.selected,
    required this.onPressed,
  });

  final HelpSupportTopic topic;
  final bool selected;
  final ValueChanged<InteractionSource> onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final metadata = _topicMetadata(topic);
    final foreground = selected
        ? tokens.colors.accent
        : tokens.colors.textPrimary;
    return SizedBox(
      width: 232,
      child: Material(
        color: selected
            ? tokens.surfaces.selected.fill
            : tokens.surfaces.panel.fill,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.shape.small,
          side: BorderSide(
            color: selected
                ? tokens.colors.accent.withValues(alpha: 0.55)
                : tokens.surfaces.panel.border,
            width: tokens.stroke.regular,
          ),
        ),
        child: StarBridgeActionRow(
          controlKey: Key('help-topic-button-${topic.name}'),
          onActivate: (_, source) => onPressed(source),
          baseRadius: tokens.shape.radiusSmall,
          semanticSelected: selected,
          semanticLabel:
              '${strings.text(metadata.titleKey)}. ${strings.text(metadata.descriptionKey)}',
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space.sm,
                vertical: tokens.space.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarBridgeIcon(
                    metadata.icon,
                    size: tokens.icons.medium,
                    color: selected
                        ? tokens.colors.accent
                        : tokens.colors.textSecondary,
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text(metadata.titleKey),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: foreground),
                        ),
                        SizedBox(height: tokens.space.xxs),
                        Text(
                          strings.text(metadata.descriptionKey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameLogHelp extends StatelessWidget {
  const _GameLogHelp({super.key});

  static const _categories = [
    ('help.log.session.title', 'help.log.session.body'),
    ('help.log.identity.title', 'help.log.identity.body'),
    ('help.log.server.title', 'help.log.server.body'),
    ('help.log.ship.title', 'help.log.ship.body'),
    ('help.log.location.title', 'help.log.location.body'),
    ('help.log.health.title', 'help.log.health.body'),
    ('help.log.records.title', 'help.log.records.body'),
    ('help.log.confidence.title', 'help.log.confidence.body'),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopicHeading(
          icon: StarBridgeIconSemantic.diagnostics,
          color: tokens.colors.info,
          titleKey: 'help.log.title',
          descriptionKey: 'help.log.description',
        ),
        SizedBox(height: tokens.space.md),
        _InformationCard(
          icon: StarBridgeIconSemantic.privacy,
          color: tokens.colors.success,
          titleKey: 'help.log.scope.title',
          bodyKey: 'help.log.scope.body',
        ),
        SizedBox(height: tokens.space.md),
        _InformationCard(
          icon: StarBridgeIconSemantic.refresh,
          color: tokens.colors.info,
          titleKey: 'help.log.troubleshoot.title',
          bodyKey: 'help.log.troubleshoot.body',
        ),
        SizedBox(height: tokens.space.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.text('help.log.catalog'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${_categories.length}',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: tokens.colors.info),
            ),
          ],
        ),
        SizedBox(height: tokens.space.sm),
        for (var index = 0; index < _categories.length; index++) ...[
          HelpSupportDisclosureCard(
            key: Key('help-log-category-$index'),
            titleKey: _categories[index].$1,
            bodyKey: _categories[index].$2,
            accent: switch (index % 4) {
              0 => tokens.colors.info,
              1 => tokens.colors.success,
              2 => tokens.colors.warning,
              _ => tokens.colors.accent,
            },
          ),
          if (index != _categories.length - 1)
            SizedBox(height: tokens.space.xs),
        ],
      ],
    );
  }
}

class _NoticesHelp extends StatelessWidget {
  const _NoticesHelp({super.key});

  static const _sections = [
    ('help.legal.operation.title', 'help.legal.operation.body'),
    ('help.legal.data.title', 'help.legal.data.body'),
    ('help.legal.safety.title', 'help.legal.safety.body'),
    ('help.legal.unofficial.title', 'help.legal.unofficial.body'),
    ('help.legal.use.title', 'help.legal.use.body'),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopicHeading(
          icon: StarBridgeIconSemantic.legalNotice,
          color: tokens.colors.success,
          titleKey: 'help.legal.title',
          descriptionKey: 'help.legal.description',
        ),
        SizedBox(height: tokens.space.md),
        for (var index = 0; index < _sections.length; index++) ...[
          HelpSupportDisclosureCard(
            key: Key('help-legal-section-$index'),
            titleKey: _sections[index].$1,
            bodyKey: _sections[index].$2,
            initiallyExpanded: index == 0,
            accent: switch (index) {
              0 => tokens.colors.info,
              1 => tokens.colors.success,
              2 => tokens.colors.warning,
              3 => tokens.colors.accent,
              _ => tokens.colors.textSecondary,
            },
          ),
          SizedBox(height: tokens.space.xs),
        ],
        SizedBox(height: tokens.space.sm),
        const StarBridgeSurface(
          key: Key('help-cig-fankit-notice'),
          role: SurfaceRole.raised,
          child: CigFankitNoticeContent(),
        ),
        SizedBox(height: tokens.space.md),
        StarBridgeSurface(
          role: SurfaceRole.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('legal.distribution.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('legal.distribution.body'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space.md),
        ClientLicenseButton(
          open: SettingsEntryOverrides.of(context)['client-license'],
        ),
        SizedBox(height: tokens.space.md),
        StarBridgeSurface(
          key: const Key('help-third-party-licenses'),
          role: SurfaceRole.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('help.legal.licenses.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('help.legal.licenses.body'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary, height: 1.5),
              ),
              SizedBox(height: tokens.space.md),
              HelpSupportAction(
                kind: StarBridgeActionKind.secondary,
                controlKey: const Key('help-open-third-party-licenses'),
                onActivate: (_) => StarBridgeThirdPartyLicenses.show(context),
                icon: StarBridgeIconSemantic.legalNotice,
                child: Text(strings.text('help.legal.licenses.open')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdatesHelp extends StatelessWidget {
  const _UpdatesHelp({this.port, super.key});
  final HelpSupportPort? port;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopicHeading(
          icon: StarBridgeIconSemantic.refresh,
          color: tokens.colors.warning,
          titleKey: 'help.version.title',
          descriptionKey: 'help.version.description',
        ),
        SizedBox(height: tokens.space.md),
        ClientVersionButton(
          open: SettingsEntryOverrides.of(context)['client-version'],
        ),
        SizedBox(height: tokens.space.md),
        HelpSupportReadCard(name: 'applicationUpdates.check', port: port),
        SizedBox(height: tokens.space.md),
        HelpSupportAction(
          kind: StarBridgeActionKind.secondary,
          controlKey: const Key('help-check-updates'),
          onActivate:
              SettingsEntryOverrides.of(context)['application-updates'] == null
              ? null
              : (_) => SettingsEntryOverrides.of(
                  context,
                )['application-updates']!(context),
          icon: StarBridgeIconSemantic.refresh,
          child: Text(strings.text('help.version.check')),
        ),
        SizedBox(height: tokens.space.md),
        HelpSupportReadCard(name: 'helpSupport.history', port: port),
        SizedBox(height: tokens.space.md),
        HelpSupportReadCard(name: 'helpSupport.stats', port: port),
      ],
    );
  }
}

class _FeedbackHelp extends StatelessWidget {
  const _FeedbackHelp({
    this.port,
    required this.contact,
    required this.message,
    super.key,
  });
  final HelpSupportPort? port;
  final TextEditingController contact, message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return HelpSupportFeedbackContent(
      heading: _TopicHeading(
        icon: StarBridgeIconSemantic.notifications,
        color: tokens.colors.accent,
        titleKey: 'help.feedback.title',
        descriptionKey: 'help.feedback.description',
      ),
      unavailableNotice: HelpSupportFeedbackForm(
        port: port,
        contact: contact,
        message: message,
      ),
    );
  }
}

class _TopicHeading extends StatelessWidget {
  const _TopicHeading({
    required this.icon,
    required this.color,
    required this.titleKey,
    required this.descriptionKey,
  });

  final StarBridgeIconSemantic icon;
  final Color color;
  final String titleKey;
  final String descriptionKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: tokens.shape.small,
              border: Border.all(
                color: color.withValues(alpha: 0.42),
                width: tokens.stroke.hairline,
              ),
            ),
            child: StarBridgeIcon(icon, color: color),
          ),
          SizedBox(width: tokens.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  strings.text(descriptionKey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.color,
    required this.titleKey,
    required this.bodyKey,
  });

  final StarBridgeIconSemantic icon;
  final Color color;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(icon, color: color),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

({String titleKey, String descriptionKey, StarBridgeIconSemantic icon})
_topicMetadata(HelpSupportTopic topic) => switch (topic) {
  HelpSupportTopic.gameLog => (
    titleKey: 'help.topic.log',
    descriptionKey: 'help.topic.log.description',
    icon: StarBridgeIconSemantic.diagnostics,
  ),
  HelpSupportTopic.notices => (
    titleKey: 'help.topic.legal',
    descriptionKey: 'help.topic.legal.description',
    icon: StarBridgeIconSemantic.legalNotice,
  ),
  HelpSupportTopic.updates => (
    titleKey: 'help.topic.version',
    descriptionKey: 'help.topic.version.description',
    icon: StarBridgeIconSemantic.refresh,
  ),
  HelpSupportTopic.feedback => (
    titleKey: 'help.topic.feedback',
    descriptionKey: 'help.topic.feedback.description',
    icon: StarBridgeIconSemantic.notifications,
  ),
};
