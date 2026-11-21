import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';
import 'journey_station_markers.dart';

/// Read-only presentation of confirmed awards. Progress never grants a rank.
final class AchievementPresentation {
  const AchievementPresentation(this.definition, this.collection, this.strings);
  final AchievementDefinition definition;
  final AchievementCollection collection;
  final AppStrings strings;
  bool get earned => journeyCollectionMarkers.containsKey(definition.id)
      ? collection.isConfirmed(definition.id) &&
            collection.earnedAt.containsKey(definition.id)
      : collection.isEarned(definition.id);
  bool get concealed => definition.hidden && !earned;
  int get rank => collection.rank(definition.id);
  num? get peak => _confirmedPeak ?? (_startsAtZero ? 0 : null);

  num? get _confirmedPeak {
    final markers = journeyCollectionMarkers[definition.id];
    if (markers == null) return collection.progressFor(definition.id);
    if (!collection.isConfirmed(definition.id)) return null;
    // Only server-confirmed station markers count, even after the collection is earned.
    final reached = markers.where(collection.earnedAt.containsKey).length;
    return reached == 0 ? null : reached;
  }

  /// A confirmed, not yet started achievement with a known total shows 0 / N
  /// instead of "not synced" (user 11-11: "没到过就显示进度条为0吧，比如0/3这样").
  /// Earned or ranked rows never get an invented count. Hangar series are
  /// excluded: their count comes from reading the hangar, so a missing value
  /// means "not read yet", not zero; a read 0 arrives as real progress.
  bool get _startsAtZero =>
      collection.isConfirmed(definition.id) &&
      !earned &&
      rank == 0 &&
      !definition.ended &&
      !definition.isSeries &&
      definition.target != null;

  /// Wording when a hangar series has no read count yet.
  String get seriesPending => strings.text('achievements.hangarPending');

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
      definition.source == AchievementSource.bridge &&
          definition.groupId == 'contract'
      ? earned
            ? collection.contractRecords[definition.id]?.localized(strings) ??
                  ''
            : ''
      : definition.serverMemory ?? strings.text(definition.memoryKey);
  int? percentageFor([int? level]) =>
      definition.source != AchievementSource.bridge ||
          !collection.isConfirmed(definition.id)
      ? null
      : collection.percentages[definition.isSeries
            ? '${definition.id}-${level ?? (rank > 0 ? rank : 1)}'
            : definition.id];
  String? rarityLabelFor([int? level]) {
    if (definition.source != AchievementSource.bridge ||
        !collection.isConfirmed(definition.id)) {
      return null;
    }
    final tier =
        collection.tiers[definition.isSeries
            ? '${definition.id}-${level ?? (rank > 0 ? rank : 1)}'
            : definition.id];
    return switch (tier) {
      'veryRare' => strings.text('achievements.appRarity.ultraRare'),
      'rare' => strings.text('achievements.appRarity.rare'),
      _ => null,
    };
  }

  String? rarityTextFor([int? level]) {
    final value = percentageFor(level);
    if (value == null) return null;
    return value < 10
        ? strings.text('achievements.appRarity.belowPointOne')
        : strings
              .text('achievements.appRarity.percentage')
              .replaceAll('{percent}', (value / 100).toStringAsFixed(1));
  }

  String? get note =>
      definition.noteKey == null ? null : strings.text(definition.noteKey!);
  String get condition => concealed
      ? strings.text('achievements.revealedLater')
      : definition.isSeries
      ? definition.condition(
          strings.text(definition.conditionKey),
          (rank + 1).clamp(1, definition.thresholds.length),
        )
      : definition.conditionParameters.entries.fold(
          definition.serverCondition ?? strings.text(definition.conditionKey),
          (text, parameter) =>
              text.replaceAll('{${parameter.key}}', parameter.value),
        );
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
          (complete && !journeyCollectionMarkers.containsKey(definition.id)) ||
          definition.ended ||
          peak == null ||
          nextTarget == null ||
          nextTarget! <= 0
      ? null
      : (peak! / nextTarget!).clamp(0.0, 1.0);

  /// Server-confirmed stations of a journey collection, for the detail view.
  List<String> get reachedStations {
    final markers = journeyCollectionMarkers[definition.id];
    if (markers == null || !collection.isConfirmed(definition.id)) {
      return const [];
    }
    return journeyReachedStationNames(markers, collection.earnedAt.containsKey);
  }

  bool get inProgress => fraction != null && peak! > 0 && !complete;
  String? get progressText {
    if (!collection.isConfirmed(definition.id)) return null;
    if (concealed) return strings.text('achievements.revealedLater');
    if (definition.isSeries) {
      if (complete) return strings.text('achievements.stagesCollected');
      if (peak == null) return seriesPending;
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
    if (earned && !journeyCollectionMarkers.containsKey(definition.id)) {
      return null;
    }
    if (definition.ended) return strings.text('achievements.eventEnded');
    // An earned journey collection without station records shows no count.
    if (journeyCollectionMarkers.containsKey(definition.id) && peak == null) {
      return null;
    }
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
