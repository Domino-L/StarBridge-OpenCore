import '../../design_system/icons/standard_icon.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'communities_module.dart';
import 'community_gameplay_tags.dart';
import 'community_logo.dart';

/// Equal-sized discovery cards; the dialog retains complete text and actions.
class CommunityDirectoryCard extends StatefulWidget {
  const CommunityDirectoryCard({
    required this.row,
    required this.text,
    required this.onDetails,
    required this.onAction,
    this.horizontal = false,
    super.key,
  });

  /// Wide, short list viewports use a flat layout without reducing text size.
  final bool horizontal;
  final CommunityCard row;
  final String Function(String) text;
  final VoidCallback? onDetails;
  final void Function(String)? onAction;

  @override
  State<CommunityDirectoryCard> createState() => _CommunityDirectoryCardState();
}

class _CommunityDirectoryCardState extends State<CommunityDirectoryCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final t = widget.text;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context).textTheme;
    final secondary = theme.bodySmall?.copyWith(color: colors.textSecondary);
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      3.0,
    );
    final highlight = _hovered || _focused;
    final accent = row.recruiting ? colors.success : colors.stateAccent;
    final member = const {'owner', 'member'}.contains(row.relationship);
    final primary = row.actions
        .where((a) => a == 'join' || a == 'apply')
        .firstOrNull;
    final modeColor = row.joinMode == 'application'
        ? colors.warning
        : colors.stateAccent;
    final scaleParts = row.memberScale.isEmpty
        ? <String>[]
        : t('option.scale.${row.memberScale}').split(' · ');
    final radius = BorderRadius.circular(10);

    Widget line(StandardIconSemantic icon, String label) => Row(
      children: [
        StandardIcon(icon, size: 15, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: StarBridgeTooltip(
            message: label,
            child: Text(
              _summary(label),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: secondary,
            ),
          ),
        ),
      ],
    );

    final header = SizedBox(
      height: 64 * scale,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityLogo(
            data: row.logo,
            size: 52,
            framed: false,
            downloadedBy: row,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarBridgeTooltip(
                  message: row.name,
                  child: Text(
                    _summary(row.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  t(
                    row.displayOnly
                        ? 'cachedMembershipUnknown'
                        : 'relation.${row.relationship}',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: secondary?.copyWith(
                    color: member ? colors.success : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (row.memberCount != null || scaleParts.isNotEmpty) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 102,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    row.memberCount != null
                        ? '${row.memberCount}'
                        : scaleParts.first,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.titleLarge?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.memberCount != null
                        ? t('members')
                        : scaleParts.skip(1).join(' · '),
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: secondary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    final metadata = SizedBox(
      height: 30 * scale,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: .12),
              border: Border.all(color: modeColor.withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              t(row.displayOnly ? 'cachedReadOnly' : 'mode.${row.joinMode}'),
              style: secondary?.copyWith(
                color: modeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: line(
              StandardIconSemantic.language,
              row.language.isEmpty
                  ? t('card.notSpecified')
                  : communityLanguageLabel(context, row.language),
            ),
          ),
        ],
      ),
    );
    final activity = SizedBox(
      height: 20 * scale,
      child: line(
        StandardIconSemantic.schedule,
        '${t('activeTime')} · ${row.activeTime.isEmpty ? t('card.notSpecified') : row.activeTime}',
      ),
    );
    final tags = SizedBox(
      height: (widget.horizontal ? 32 : 64) * scale,
      child: CommunityGameplayTags(value: row.tags, fitAvailableSpace: true),
    );
    final description = SizedBox(
      height: 40 * scale,
      child: Text(
        _summary(row.description),
        key: ValueKey('community-card-description-${row.key}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: secondary,
      ),
    );
    final recruitment = SizedBox(
      height: (widget.horizontal ? 146 : 106) * scale,
      child: row.recruiting
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: .065),
                border: Border(
                  left: BorderSide(color: colors.success, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      StandardIcon(
                        StandardIconSemantic.campaign,
                        size: 16,
                        color: colors.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t('recruiting'),
                        style: secondary?.copyWith(
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${t('filter.targets')} · ${row.recruitingTarget.isEmpty ? t('card.notSpecified') : communityRecruitingTarget(row.recruitingTarget, t)}',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: secondary,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.recruitingNote.isEmpty
                        ? t('card.noRecruitingNote')
                        : _summary(row.recruitingNote),
                    key: ValueKey('community-card-recruitment-${row.key}'),
                    maxLines: widget.horizontal ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
    final footer = Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: ValueKey('community-card-details-${row.key}'),
              onActivate: widget.onDetails == null
                  ? null
                  : (_) => widget.onDetails!(),
              child: Text(
                t('card.details'),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 126, minHeight: 44),
          child: StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: ValueKey('community-card-primary-${row.key}'),
            onActivate: primary != null
                ? widget.onAction == null
                      ? null
                      : (_) => widget.onAction!(primary)
                : member || row.relationship == 'pending'
                ? (widget.onDetails == null ? null : (_) => widget.onDetails!())
                : null,
            child: Text(
              row.displayOnly
                  ? t('cachedReadOnly')
                  : primary != null
                  ? t('action.$primary')
                  : member
                  ? t('relation.member')
                  : row.relationship == 'pending'
                  ? t('card.application')
                  : t('mode.${row.joinMode}'),
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      key: ValueKey('community-card-${row.key}'),
      height: (widget.horizontal ? 304 : 464) * scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: highlight && row.recruiting
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: .16),
                    blurRadius: 16,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: tokens.surfaces.panel.fill,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: highlight ? accent : tokens.surfaces.panel.border,
            ),
          ),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (value) => setState(() => _focused = value),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: StarBridgeActionRow(
                baseRadius: 10,
                controlKey: ValueKey('community-card-open-${row.key}'),
                onActivate: widget.onDetails == null
                    ? null
                    : (_, _) => widget.onDetails!(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      if (widget.horizontal) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 146 * scale,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    metadata,
                                    const SizedBox(height: 8),
                                    activity,
                                    const SizedBox(height: 8),
                                    tags,
                                    const SizedBox(height: 8),
                                    description,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: recruitment),
                            ],
                          ),
                        ),
                        const Spacer(),
                        footer,
                      ] else ...[
                        const SizedBox(height: 10),
                        metadata,
                        const SizedBox(height: 10),
                        activity,
                        const SizedBox(height: 12),
                        tags,
                        const SizedBox(height: 8),
                        description,
                        const SizedBox(height: 12),
                        recruitment,
                        const Spacer(),
                        footer,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Cards are excerpts, not document viewers. Collapse paragraph whitespace so
// blank lines cannot consume the preview before the visible ellipsis.
String _summary(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String communityRecruitingTarget(String value, String Function(String) text) {
  final key = 'option.targets.$value';
  final translated = text(key);
  return translated == key || translated == 'communities.$key'
      ? value
      : translated;
}

String communityLanguageLabel(BuildContext context, String value) {
  final locale = Localizations.localeOf(context);
  final labels = switch (value.toLowerCase()) {
    'zh-cn' || 'zh-hans' => ('简体中文', '簡體中文', 'Simplified Chinese'),
    'zh-tw' || 'zh-hant' => ('繁体中文', '繁體中文', 'Traditional Chinese'),
    'en' || 'en-us' || 'en-gb' => ('英语', '英語', 'English'),
    'ja' || 'ja-jp' => ('日语', '日語', 'Japanese'),
    'ko' || 'ko-kr' => ('韩语', '韓語', 'Korean'),
    _ => null,
  };
  if (labels == null) return value;
  if (locale.languageCode != 'zh') return labels.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? labels.$2
      : labels.$1;
}
