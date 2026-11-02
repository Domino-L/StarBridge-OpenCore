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
                      size: (constraints.maxWidth - 2).clamp(1, 1000),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                title,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AchievementArt(
                  definition: widget.definition,
                  earned: p.earned,
                  size: 64,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 13,
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                      if (foot != null) ...[const SizedBox(height: 8), foot],
                    ],
                  ),
                ),
              ],
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
  const AchievementProgress({required this.presentation, super.key});
  final AchievementPresentation presentation;
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
