import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';

/// Read-only presentation of confirmed awards. Progress never grants a rank.
final class AchievementPresentation {
  const AchievementPresentation(this.definition, this.collection, this.strings);
  final AchievementDefinition definition;
  final AchievementCollection collection;
  final AppStrings strings;
  bool get earned => collection.isEarned(definition.id);
  bool get concealed => definition.hidden && !earned;
  int get rank => collection.rank(definition.id);
  num? get peak => collection.progressFor(definition.id);
  bool get complete =>
      definition.isSeries ? rank >= definition.thresholds.length : earned;
  String get name => concealed
      ? strings.text('achievements.hidden')
      : definition.rankedName(
          definition.serverName ?? strings.text(definition.nameKey),
          rank,
        );
  String get unit =>
      definition.unitKey == null ? '' : strings.text(definition.unitKey!);

  /// Null while this source is unknown: neither state can be claimed.
  String? get status => !collection.isConfirmed(definition.id)
      ? null
      : strings.text(earned ? 'achievements.earned' : 'achievements.locked');
  String get memory =>
      definition.serverMemory ?? strings.text(definition.memoryKey);
  String get condition => concealed
      ? strings.text('achievements.revealedLater')
      : definition.isSeries
      ? definition.condition(
          strings.text(definition.conditionKey),
          (rank + 1).clamp(1, definition.thresholds.length),
        )
      : definition.serverCondition ?? strings.text(definition.conditionKey);
  num? get nextTarget => definition.isSeries
      ? complete
            ? null
            : definition.thresholds[rank.clamp(
                0,
                definition.thresholds.length - 1,
              )]
      : definition.target;
  double? get fraction =>
      !collection.isConfirmed(definition.id) ||
          concealed ||
          complete ||
          definition.ended ||
          peak == null ||
          nextTarget == null ||
          nextTarget! <= 0
      ? null
      : (peak! / nextTarget!).clamp(0.0, 1.0);
  bool get inProgress => fraction != null && peak! > 0 && !complete;
  String? get progressText {
    if (!collection.isConfirmed(definition.id)) return null;
    if (concealed) return strings.text('achievements.revealedLater');
    if (definition.isSeries) {
      if (complete) return strings.text('achievements.stagesCollected');
      if (peak == null) return strings.text('achievements.progressPending');
      return strings
          .text(
            rank > 0
                ? 'achievements.nextTarget'
                : 'achievements.initialProgress',
          )
          .replaceAll('{current}', achievementNumber(peak!))
          .replaceAll('{target}', achievementNumber(nextTarget!))
          .replaceAll('{unit}', unit)
          .trim();
    }
    if (earned) return null;
    if (definition.ended) return strings.text('achievements.eventEnded');
    if (definition.target != null) {
      return peak == null
          ? strings.text('achievements.progressPending')
          : '${achievementNumber(peak!)} / ${achievementNumber(definition.target!)}';
    }
    return null;
  }
}

/// Display precision only: confirmed progress and sorting keep original values.
/// Fractions round down to one decimal so near-complete progress never reads
/// as complete (9.96 / 10 shows 9.9, not 10).
String achievementNumber(num value) {
  // The small epsilon keeps binary fractions such as 2.3 from flooring to 2.2.
  final tenths = (value * 10 + 1e-9).floor();
  return tenths % 10 == 0
      ? (tenths ~/ 10).toString()
      : (tenths / 10).toStringAsFixed(1);
}

String achievementDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatShortDate(date.toLocal());

/// Stable catalog order breaks ties explicitly, independently of sorting APIs.
List<AchievementDefinition> recentAchievements(
  List<AchievementDefinition> items,
  AchievementCollection collection,
) {
  final order = {for (var i = 0; i < items.length; i++) items[i].id: i};
  return [...items]..sort((a, b) {
    final dates = (collection.dateFor(b.id) ?? DateTime(0)).compareTo(
      collection.dateFor(a.id) ?? DateTime(0),
    );
    return dates != 0 ? dates : order[a.id]!.compareTo(order[b.id]!);
  });
}
