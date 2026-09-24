import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/legal/starbridge_third_party_licenses.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'client_license_dialog.dart';
import 'client_version_dialog.dart';
import 'help_support_feedback_content.dart';
import 'settings_entry_dialog.dart';
import 'help_support_port.dart';
import 'help_support_live_content.dart';

enum HelpSupportTopic { gameLog, notices, updates, feedback }

class HelpSupportSettingsPage extends StatefulWidget {
  const HelpSupportSettingsPage({
    this.initialTopic = HelpSupportTopic.gameLog,
    this.port,
    super.key,
  });

  final HelpSupportTopic initialTopic;
  final HelpSupportPort? port;

  @override
  State<HelpSupportSettingsPage> createState() =>
      _HelpSupportSettingsPageState();
}

class _HelpSupportSettingsPageState extends State<HelpSupportSettingsPage> {
  late HelpSupportTopic _selected;
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
              _HelpHeader(onOpenScm: widget.port == null ? null : _openScm),
              SizedBox(height: tokens.space.lg),
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

  void _select(HelpSupportTopic topic) {
    if (topic != _selected) setState(() => _selected = topic);
  }

  Future<void> _openScm() async {
    try {
      final result = await widget.port!.read('helpSupport.openScm');
      if (result['schemaVersion'] != 1 || result['opened'] != true) {
        throw const FormatException('Unconfirmed browser launch');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('help.scm.openFailed')),
        ),
      );
    }
  }

  Widget _topicContent() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 130),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
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
  );
}

class _HelpHeader extends StatelessWidget {
  const _HelpHeader({this.onOpenScm});
  final VoidCallback? onOpenScm;

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
            Tooltip(
              message: 'SCM · scm.flowcld.com',
              child: TextButton(
                key: const Key('help-scm-team'),
                onPressed: onOpenScm,
                child: const ScmBrandMark(),
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

class _TopicNavigation extends StatelessWidget {
  const _TopicNavigation({
    required this.selected,
    required this.onSelect,
    required this.vertical,
  });

  final HelpSupportTopic selected;
  final ValueChanged<HelpSupportTopic> onSelect;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final topic in HelpSupportTopic.values)
        _TopicButton(
          topic: topic,
          selected: selected == topic,
          onPressed: () => onSelect(topic),
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
  final VoidCallback onPressed;

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
        child: InkWell(
          key: Key('help-topic-button-${topic.name}'),
          onTap: onPressed,
          borderRadius: tokens.shape.small,
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
          _DisclosureCard(
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
          _DisclosureCard(
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
              OutlinedButton.icon(
                key: const Key('help-open-third-party-licenses'),
                onPressed: () => StarBridgeThirdPartyLicenses.show(context),
                icon: const StarBridgeIcon(StarBridgeIconSemantic.legalNotice),
                label: Text(strings.text('help.legal.licenses.open')),
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
        OutlinedButton.icon(
          key: const Key('help-check-updates'),
          onPressed:
              SettingsEntryOverrides.of(context)['application-updates'] == null
              ? null
              : () => SettingsEntryOverrides.of(
                  context,
                )['application-updates']!(context),
          icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
          label: Text(strings.text('help.version.check')),
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

class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard({
    required this.titleKey,
    required this.bodyKey,
    required this.accent,
    this.initiallyExpanded = false,
    super.key,
  });

  final String titleKey;
  final String bodyKey;
  final Color accent;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: EdgeInsets.symmetric(
              horizontal: tokens.space.md,
              vertical: tokens.space.xxs,
            ),
            childrenPadding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.md,
              0,
              tokens.space.md,
              tokens.space.md,
            ),
            leading: Container(
              width: 4,
              height: 30,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: tokens.shape.small,
              ),
            ),
            title: Text(
              strings.text(titleKey),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: StarBridgeIcon(
              StarBridgeIconSemantic.menuDown,
              size: tokens.icons.small,
              color: tokens.colors.textSecondary,
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
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
