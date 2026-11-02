import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'achievement_art.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';
import 'achievement_entry.dart';
import 'achievement_presentation.dart';

class AchievementDetail extends StatelessWidget {
  const AchievementDetail({
    required this.definition,
    required this.collection,
    this.index = 0,
    this.total = 1,
    this.onPrevious,
    this.onNext,
    super.key,
  });
  final AchievementDefinition definition;
  final AchievementCollection collection;
  final int index, total;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context), tokens = context.tokens;
    final p = AchievementPresentation(definition, collection, s);
    final status = [
      ?p.status,
      if (definition.source == AchievementSource.scm) 'SCM',
      if (definition.source == AchievementSource.scm &&
          definition.rarity != null)
        s.text('achievements.rarity.${definition.rarity!.name}'),
    ].join(' · ');
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.isNotEmpty) ...[
          Text(status, style: TextStyle(color: tokens.colors.textSecondary)),
          const SizedBox(height: 6),
        ],
        Text(
          p.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        if (p.earned) ...[Text(p.memory), const SizedBox(height: 18)],
        Text(
          definition.isSeries && definition.metricKey != null && !p.concealed
              ? s
                    .text('achievements.metricCondition')
                    .replaceAll('{metric}', s.text(definition.metricKey!))
              : s.text('achievements.condition'),
          style: TextStyle(fontSize: 12, color: tokens.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (!definition.isSeries || p.concealed) ...[
          Text(p.condition),
          const SizedBox(height: 10),
          AchievementProgress(presentation: p),
          if (collection.dateFor(definition.id) case final date?) ...[
            const SizedBox(height: 14),
            Text(
              s
                  .text('achievements.earnedOn')
                  .replaceAll('{date}', achievementDate(context, date)),
              style: TextStyle(
                fontSize: 12,
                color: tokens.colors.textSecondary,
              ),
            ),
          ],
        ] else ...[
          Text(
            p.peak == null
                ? s.text('achievements.peakPending')
                : s
                      .text('achievements.peak')
                      .replaceAll('{current}', achievementNumber(p.peak!))
                      .replaceAll('{unit}', p.unit),
            style: TextStyle(fontSize: 12, color: tokens.colors.textSecondary),
          ),
          const SizedBox(height: 6),
          for (var level = 1; level <= definition.thresholds.length; level++)
            _Tier(definition: definition, collection: collection, level: level),
          const SizedBox(height: 8),
          if (definition.groupId == 'hangar')
            Text(
              s.text('achievements.peakNote'),
              style: TextStyle(
                fontSize: 12,
                color: tokens.colors.textSecondary,
              ),
            ),
        ],
      ],
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousAchievement(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextAchievement(),
      },
      child: Actions(
        actions: {
          _PreviousAchievement: CallbackAction<_PreviousAchievement>(
            onInvoke: (_) {
              onPrevious?.call();
              return null;
            },
          ),
          _NextAchievement: CallbackAction<_NextAchievement>(
            onInvoke: (_) {
              onNext?.call();
              return null;
            },
          ),
        },
        child: Dialog(
          key: const Key('achievement-detail'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: tokens.surfaces.floating.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: tokens.surfaces.floating.border),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 800,
              maxHeight: (MediaQuery.sizeOf(context).height - 48).clamp(
                80,
                double.infinity,
              ),
            ),
            child: SingleChildScrollView(
              key: ValueKey('achievement-inspector-scroll-${definition.id}'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StarBridgeNativeIconAction(
                            controlKey: const Key('achievement-detail-prev'),
                            label: s.text('achievements.previous'),
                            consumeHintEscape: false,
                            onActivate: onPrevious == null
                                ? null
                                : (_) => onPrevious!(),
                            icon: const StarBridgeIcon(
                              StarBridgeIconSemantic.forward,
                              size: 20,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                          Text(
                            '${index + 1} / $total',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.colors.textSecondary,
                            ),
                          ),
                          StarBridgeNativeIconAction(
                            controlKey: const Key('achievement-detail-next'),
                            label: s.text('achievements.next'),
                            consumeHintEscape: false,
                            onActivate: onNext == null
                                ? null
                                : (_) => onNext!(),
                            icon: const StarBridgeIcon(
                              StarBridgeIconSemantic.forward,
                              size: 20,
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ],
                      ),
                      StarBridgeActionButton(
                        controlKey: const Key('achievement-detail-close'),
                        autofocus: true,
                        onActivate: (source) =>
                            dismissStarBridgeDialog(context, source: source),
                        child: Text(s.text('achievements.close')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          MediaQuery.sizeOf(context).width < 760 ||
                          MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
                          constraints.maxWidth < 600;
                      final art = AchievementArt(
                        definition: definition,
                        earned: p.earned,
                        size: stacked
                            ? constraints.maxWidth.clamp(1, 240)
                            : 240,
                      );
                      return stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: art),
                                const SizedBox(height: 20),
                                text,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                art,
                                const SizedBox(width: 24),
                                Expanded(child: text),
                              ],
                            );
                    },
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

class _PreviousAchievement extends Intent {
  const _PreviousAchievement();
}

class _NextAchievement extends Intent {
  const _NextAchievement();
}

class _Tier extends StatelessWidget {
  const _Tier({
    required this.definition,
    required this.collection,
    required this.level,
  });
  final AchievementDefinition definition;
  final AchievementCollection collection;
  final int level;
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context), tokens = context.tokens;
    final p = AchievementPresentation(definition, collection, s);
    final current = level == p.rank + 1,
        date = collection.earnedAt['${definition.id}-$level'];
    final done = date != null,
        target = definition.thresholds[level - 1],
        peak = p.peak;
    final condition = current
        ? definition.condition(s.text(definition.conditionKey), level)
        : s
              .text('achievements.atLeast')
              .replaceAll('{target}', achievementNumber(target))
              .replaceAll('{unit}', p.unit)
              .trim();
    final progress = peak == null
        ? s.text('achievements.progressPending')
        : '${achievementNumber(peak.clamp(0, target))} / ${achievementNumber(target)}';
    final right = done ? achievementDate(context, date) : progress;
    final extra = current && peak != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (peak / target).clamp(0, 1),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 4),
              Text(
                peak >= target
                    ? s.text('achievements.awaitingAward')
                    : s
                          .text('achievements.remaining')
                          .replaceAll(
                            '{count}',
                            achievementNumber(target - peak),
                          )
                          .replaceAll('{unit}', p.unit),
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.colors.textSecondary,
                ),
              ),
            ],
          )
        : null;
    return Container(
      key: Key('achievement-rank-${definition.id}-$level'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: current ? tokens.colors.accentSoft : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              MediaQuery.sizeOf(context).width < 760 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
              constraints.maxWidth < 420;
          final info = Text(
            right,
            key: !done && peak != null
                ? Key('achievement-progress-${definition.id}-$level')
                : Key('achievement-date-${definition.id}-$level'),
            style: TextStyle(fontSize: 12, color: tokens.colors.textSecondary),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  done
                      ? '✓'
                      : current
                      ? '▸'
                      : '',
                  style: TextStyle(color: tokens.colors.accent),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 26,
                child: Text(
                  AchievementDefinition.roman(level),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (narrow) ...[
                      Text(condition, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      info,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              condition,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          info,
                        ],
                      ),
                    ?extra,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
