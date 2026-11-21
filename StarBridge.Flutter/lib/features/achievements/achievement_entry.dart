import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'achievement_art.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';
import 'achievement_presentation.dart';

class AchievementEntry extends StatefulWidget {
  const AchievementEntry({
    required this.definition,
    required this.collection,
    required this.focusNode,
    required this.onPressed,
    this.wall = false,
    super.key,
  });
  final AchievementDefinition definition;
  final AchievementCollection collection;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool wall;
  @override
  State<AchievementEntry> createState() => _AchievementEntryState();
}

class _AchievementEntryState extends State<AchievementEntry> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final p = AchievementPresentation(
      widget.definition,
      widget.collection,
      AppStrings.of(context),
    );
    final tokens = context.tokens;
    final progress = p.progressText;
    final date = widget.collection.dateFor(widget.definition.id);
    final title = Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          p.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (widget.definition.source == AchievementSource.scm)
          const AchievementSourceTag(),
      ],
    );
    final summary = p.earned ? p.memory : p.condition;
    final note = p.note == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              p.note!,
              style: TextStyle(
                fontSize: 12,
                color: tokens.colors.textSecondary,
              ),
            ),
          );
    final foot = progress == null ? null : AchievementProgress(presentation: p);
    final body = widget.wall
        ? LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _hovered
                          ? tokens.colors.accent
                          : tokens.surfaces.panel.border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: AchievementArt(
                      definition: widget.definition,
                      earned: p.earned,
                      rank: p.rank,
                      size: (constraints.maxWidth - 2).clamp(1, 1000),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                title,
                ?note,
                AchievementRarityInfo(presentation: p),
                if (p.memory.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.memory,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  date == null
                      ? p.strings.text('achievements.datePending')
                      : achievementDate(context, date),
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.colors.textSecondary,
                  ),
                ),
                if (foot != null) ...[const SizedBox(height: 8), foot],
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final art = AchievementArt(
                  definition: widget.definition,
                  earned: p.earned,
                  rank: p.rank,
                  size: 64,
                );
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    ?note,
                    AchievementRarityInfo(presentation: p),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 13,
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                    ],
                    if (foot != null) ...[const SizedBox(height: 8), foot],
                  ],
                );
                return constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: art,
                          ),
                          const SizedBox(height: 12),
                          text,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          art,
                          const SizedBox(width: 12),
                          Expanded(child: text),
                        ],
                      );
              },
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListenableBuilder(
        listenable: widget.focusNode,
        builder: (_, child) => CustomPaint(
          foregroundPainter: widget.focusNode.hasFocus
              ? _AchievementFocusBorder(tokens.colors.accent)
              : null,
          child: child,
        ),
        child: Material(
          color: widget.wall ? Colors.transparent : tokens.surfaces.panel.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: widget.wall
                ? BorderSide.none
                : BorderSide(color: tokens.surfaces.panel.border),
          ),
          child: StarBridgeActionRow(
            focusNode: widget.focusNode,
            onActivate: (_, _) => widget.onPressed(),
            semanticLabel: [
              p.name,
              ?p.status,
              summary,
              ?p.note,
              progress ?? '',
            ].join('. '),
            baseRadius: 8,
            child: ExcludeSemantics(
              child: DefaultTextStyle(
                style: DefaultTextStyle.of(context).style,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AchievementProgress extends StatelessWidget {
  const AchievementProgress({
    required this.presentation,
    this.showStations = false,
    super.key,
  });
  final AchievementPresentation presentation;

  /// The reached-station list is detail-only; cards keep their height.
  final bool showStations;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (presentation.progressText case final text?)
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: context.tokens.colors.textSecondary,
          ),
        ),
      if (presentation.reachedStations case final names
          when showStations && names.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          AppStrings.of(context)
              .text('achievements.stationsVisited')
              .replaceAll('{names}', names.join('、')),
          key: const Key('achievement-reached-stations'),
          style: TextStyle(
            fontSize: 12,
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ],
      if (presentation.fraction case final value?) ...[
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: value,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    ],
  );
}

class AchievementRarityInfo extends StatelessWidget {
  const AchievementRarityInfo({
    required this.presentation,
    this.level,
    super.key,
  });
  final AchievementPresentation presentation;
  final int? level;
  @override
  Widget build(BuildContext context) {
    final text = presentation.rarityTextFor(level);
    if (text == null) return const SizedBox.shrink();
    final label = presentation.rarityLabelFor(level);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: context.tokens.colors.textSecondary,
            ),
          ),
          if (label != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.tokens.colors.accentSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.tokens.colors.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AchievementSourceTag extends StatelessWidget {
  const AchievementSourceTag({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        'SCM',
        style: TextStyle(
          fontSize: 11,
          color: context.tokens.colors.textSecondary,
        ),
      ),
    ),
  );
}

class _AchievementFocusBorder extends CustomPainter {
  _AchievementFocusBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(3),
      const Radius.circular(9),
    ),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  @override
  bool shouldRepaint(_AchievementFocusBorder oldDelegate) =>
      oldDelegate.color != color;
}
