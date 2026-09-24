import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'communities_module.dart';
import 'community_directory_card.dart';
import 'community_gameplay_tags.dart';
import 'community_logo.dart';

/// Public directory information only. Opening details never reads edit access
/// or joins a workspace; commands retain the page's existing confirmation flow.
class CommunityDirectoryDetails extends StatefulWidget {
  const CommunityDirectoryDetails({
    required this.row,
    required this.text,
    required this.onClose,
    this.onAction,
    this.onEnter,
    this.message,
    super.key,
  });

  final CommunityCard? row;
  final String Function(String) text;
  final VoidCallback onClose;
  final void Function(String)? onAction;
  final VoidCallback? onEnter;
  final String? message;

  @override
  State<CommunityDirectoryDetails> createState() =>
      _CommunityDirectoryDetailsState();
}

class _CommunityDirectoryDetailsState extends State<CommunityDirectoryDetails> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final t = widget.text;
    final colors = context.tokens.colors;
    final type = Theme.of(context).textTheme;
    final member =
        row != null && const {'owner', 'member'}.contains(row.relationship);
    return Dialog(
      key: const ValueKey('community-directory-details'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
        child: SizedBox(
          width: 860,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(t('details.title'), style: type.titleMedium),
                    ),
                    IconButton(
                      tooltip: t('card.close'),
                      onPressed: widget.onClose,
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('community-details-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(24),
                    child: row == null
                        ? Text(t('refreshRequired'))
                        : _body(context, row),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                key: const ValueKey('community-details-footer'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.message != null) ...[
                      Text(widget.message!),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: widget.onClose,
                          child: Text(t('card.close')),
                        ),
                        if (row != null)
                          for (final action in row.actions)
                            if (action == 'join' || action == 'apply')
                              FilledButton(
                                key: ValueKey(
                                  'community-details-action-$action',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(126, 44),
                                ),
                                onPressed: widget.onAction == null
                                    ? null
                                    : () => widget.onAction!(action),
                                child: Text(t('action.$action')),
                              )
                            else
                              OutlinedButton(
                                key: ValueKey(
                                  'community-details-action-$action',
                                ),
                                style: action == 'leave'
                                    ? OutlinedButton.styleFrom(
                                        foregroundColor: colors.warning,
                                      )
                                    : null,
                                onPressed: widget.onAction == null
                                    ? null
                                    : () => widget.onAction!(action),
                                child: Text(t('action.$action')),
                              ),
                        if (member)
                          FilledButton(
                            onPressed: widget.onEnter,
                            child: Text(t('card.enter')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CommunityCard row) {
    final t = widget.text;
    final type = Theme.of(context).textTheme;
    final colors = context.tokens.colors;
    final secondary = type.bodySmall?.copyWith(color: colors.textSecondary);
    final scale = row.memberCount != null
        ? '${row.memberCount} ${t('members')}'
        : row.memberScale.isEmpty
        ? ''
        : t('option.scale.${row.memberScale}');

    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: secondary),
        const SizedBox(height: 6),
        SelectableText(
          value.isEmpty ? t('card.notSpecified') : value,
          style: type.bodyMedium,
        ),
      ],
    );
    Widget section(String title, Widget content, {bool recruiting = false}) =>
        Container(
          margin: const EdgeInsets.only(top: 24),
          padding: recruiting ? const EdgeInsets.all(16) : EdgeInsets.zero,
          decoration: recruiting
              ? BoxDecoration(
                  color: colors.success.withValues(alpha: .065),
                  border: Border(
                    left: BorderSide(color: colors.success, width: 2),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: type.titleMedium?.copyWith(
                  color: recruiting ? colors.success : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              content,
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommunityLogo(data: row.logo, size: 60, framed: false),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    row.name,
                    style: type.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Text(t('relation.${row.relationship}'), style: secondary),
                      if (scale.isNotEmpty)
                        Text(
                          scale,
                          style: type.bodyMedium?.copyWith(
                            color: colors.accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              field(t('filter.join'), t('mode.${row.joinMode}')),
              field(
                t('language'),
                row.language.isEmpty
                    ? ''
                    : communityLanguageLabel(context, row.language),
              ),
            ];
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [fields[0], const SizedBox(height: 16), fields[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 24),
                Expanded(child: fields[1]),
              ],
            );
          },
        ),
        section(
          t('details.about'),
          SelectableText(
            row.description.isEmpty ? t('card.notSpecified') : row.description,
            key: const ValueKey('community-details-description'),
            style: type.bodyMedium,
          ),
        ),
        if (row.tags.isNotEmpty)
          section(t('tags'), CommunityGameplayTags(value: row.tags)),
        section(
          t('details.activity'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(t('activeTime'), row.activeTime),
              if (row.systems.isNotEmpty) ...[
                const SizedBox(height: 16),
                field(
                  t('filter.systems'),
                  row.systems
                      .map((system) {
                        final label = t('option.systems.$system');
                        return label == 'option.systems.$system' ||
                                label == 'communities.option.systems.$system'
                            ? system
                            : label;
                      })
                      .join(' / '),
                ),
              ],
            ],
          ),
        ),
        if (row.recruiting)
          section(
            t('recruiting'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(
                  t('filter.targets'),
                  row.recruitingTarget.isEmpty
                      ? ''
                      : communityRecruitingTarget(row.recruitingTarget, t),
                ),
                const SizedBox(height: 16),
                field(
                  t('card.recruitingNote'),
                  row.recruitingNote.isEmpty
                      ? t('card.noRecruitingNote')
                      : row.recruitingNote,
                ),
              ],
            ),
            recruiting: true,
          ),
        if (row.relationship == 'owner') ...[
          const SizedBox(height: 20),
          Text(t('ownerHint'), style: secondary),
        ],
      ],
    );
  }
}
