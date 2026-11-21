import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';
import 'package:starbridge_flutter/features/achievements/journey_station_markers.dart';

void main() {
  final strings = AppStrings.resolve(const Locale('zh', 'CN'));
  final at = DateTime.utc(2026, 10, 30);
  AchievementPresentation present(
    String id,
    Iterable<String> awards, {
    AchievementCollectionStatus status = AchievementCollectionStatus.ready,
    Map<String, num>? progress,
  }) => AchievementPresentation(
    achievementCatalog.firstWhere((d) => d.id == id),
    AchievementCollection(
      generation: 1,
      status: status,
      earnedAt: {for (final id in awards) id: at},
      progress: progress,
    ),
    strings,
  );

  test('only the exact 23 stations and three major stations count', () {
    expect(pyroStationMarkers, hasLength(23));
    expect(pyroMajorStationMarkers, {
      'journey-station-rr-p2-l4',
      'journey-station-rr-p3-leo',
      'journey-station-rr-p6-leo',
    });
    final awards = [
      'journey-station-rr-p2-l4',
      'journey-station-rr-p6-leo',
      'journey-station-rr-p1-l2',
      'journey-station-rr-p1-l1',
      'journey-station-rr-p3-l4',
      'journey-station-rr-p4-leo',
      'journey-levski',
      'journey-grimhex',
      'journey-stanton',
    ];
    final majors = present('journey-pyro-majors', awards);
    expect(majors.progressText, '2 / 3');
    expect(majors.fraction, closeTo(2 / 3, 0.00001));
    expect(majors.earned, isFalse);
    expect(majors.status, '尚未收藏');
    expect(present('journey-pyro-all', awards).progressText, '3 / 23');
    // Catalog order, Chinese names; non-Pyro and unknown rows never appear.
    expect(present('journey-pyro-all', awards).reachedStations, [
      '死局空间站',
      '废墟空间站',
      '焰联-远程站-1-2',
    ]);
    expect(majors.reachedStations, ['死局空间站', '废墟空间站']);
  });

  test('all markers fill progress without granting either collection', () {
    for (final (id, target) in [
      ('journey-pyro-majors', 3),
      ('journey-pyro-all', 23),
    ]) {
      final p = present(id, pyroStationMarkers);
      expect(p.progressText, '$target / $target');
      expect(p.fraction, 1);
      expect(p.earned, isFalse);
      expect(p.complete, isFalse);
      expect(p.status, '尚未收藏');
    }
  });

  test('server collection IDs unlock; progress still counts only markers', () {
    for (final (id, target, markers) in [
      ('journey-pyro-majors', 3, pyroMajorStationMarkers),
      ('journey-pyro-all', 23, pyroStationMarkers),
    ]) {
      final bare = present(id, [id]);
      expect(bare.earned, isTrue);
      expect(bare.complete, isTrue);
      expect(bare.status, '已收藏');
      expect(bare.peak, isNull, reason: 'no marker, no invented count');
      expect(bare.progressText, isNull);
      expect(bare.reachedStations, isEmpty);
      final partial = present(id, [id, markers.first]);
      expect(partial.earned, isTrue);
      expect(partial.peak, 1);
      final full = present(id, [id, ...markers]);
      expect(full.progressText, '$target / $target');
      expect(full.fraction, 1);
      expect(full.inProgress, isFalse);
    }
  });

  test('no station yet shows an empty bar and 0 / N, never "not synced"', () {
    for (final (id, target) in [
      ('journey-pyro-majors', 3),
      ('journey-pyro-all', 23),
    ]) {
      expect(present(id, []).peak, 0);
      expect(present(id, []).progressText, '0 / $target');
      expect(present(id, []).reachedStations, isEmpty);
      expect(present(id, []).fraction, 0);
      expect(present(id, []).inProgress, isFalse);
    }
    for (final id in journeyCollectionMarkers.keys) {
      for (final status in AchievementCollectionStatus.values.where(
        (s) => s != AchievementCollectionStatus.ready,
      )) {
        final p = present(id, pyroStationMarkers, status: status);
        expect(p.peak, isNull);
        expect(p.progressText, isNull);
        expect(p.fraction, isNull);
        expect(p.status, isNull);
      }
    }
  });

  test('station names: Chinese first, English when Chinese is missing', () {
    expect(journeyStationNames.keys.toSet(), pyroStationMarkers);
    for (final (zh, en) in journeyStationNames.values) {
      expect(en.trim(), isNotEmpty);
      expect(zh?.trim(), isNotEmpty);
    }
    expect(
      journeyReachedStationNames({
        'journey-station-rr-p2-l4',
        'journey-station-unknown',
      }, (_) => true),
      ['死局空间站', 'journey-station-unknown'],
    );
    expect(
      journeyReachedStationNames(
        {'a', 'b', 'c'},
        (_) => true,
        names: const {
          'a': (null, 'Alpha'),
          'b': ('  ', 'Beta'),
          'c': ('丙', 'C'),
        },
      ),
      ['Alpha', 'Beta', '丙'],
    );
  });

  test('hangar series: unread shows no 0, a read 0 shows 0 / N', () {
    for (final (id, first) in [
      ('hangar-home', 1),
      ('hangar-collection', 3),
      ('hangar-paths', 2),
    ]) {
      final unread = present(id, const []);
      expect(unread.peak, isNull);
      expect(unread.fraction, isNull);
      expect(unread.progressText, '读取机库后显示进度');
      final read = present(id, const [], progress: {id: 0});
      expect(read.peak, 0);
      expect(read.fraction, 0);
      expect(read.progressText, contains('0 / $first'));
      expect(read.progressText, isNot(contains('暂未同步')));
    }
  });

  test('rank-like IDs cannot substitute for a server collection ID', () {
    for (final id in journeyCollectionMarkers.keys) {
      final p = present(id, ['$id-1', '$id-5']);
      expect(p.earned, isFalse);
      expect(p.complete, isFalse);
      expect(p.peak, isNull);
    }
  });

  test('Stanton keeps server progress; single arrivals have no target', () {
    final stanton = present(
      'journey-stanton',
      pyroStationMarkers,
      progress: {'journey-stanton': 2},
    );
    expect(stanton.progressText, '2 / 4');
    // No server progress yet: 0 / 4 with an empty bar instead of "not synced".
    expect(present('journey-stanton', pyroStationMarkers).peak, 0);
    expect(
      present('journey-stanton', pyroStationMarkers).progressText,
      '0 / 4',
    );
    final earned = present(
      'journey-stanton',
      ['journey-stanton'],
      progress: {'journey-stanton': 4},
    );
    expect(earned.earned, isTrue);
    expect(earned.progressText, isNull);
    expect(earned.fraction, isNull);
    for (final id in ['journey-levski', 'journey-grimhex']) {
      final locked = present(id, []);
      expect(locked.earned, isFalse);
      expect(locked.nextTarget, isNull);
      expect(locked.progressText, isNull);
      final earned = present(id, [id]);
      expect(earned.earned, isTrue);
      expect(earned.nextTarget, isNull);
      expect(earned.progressText, isNull);
    }
  });

  test('all supported locales provide the new names and descriptions', () {
    final additions = achievementCatalog.where(
      (d) => const [
        'journey-levski',
        'journey-pyro-majors',
        'journey-pyro-all',
        'journey-grimhex',
      ].contains(d.id),
    );
    for (final locale in AppStrings.supportedLocales) {
      final localized = AppStrings.resolve(locale);
      for (final d in additions) {
        for (final key in [
          d.nameKey,
          d.conditionKey,
          d.memoryKey,
          ?d.unitKey,
          ?d.metricKey,
        ]) {
          expect(localized.text(key), isNot(key));
          expect(localized.text(key), isNotEmpty);
        }
      }
    }
  });
}
