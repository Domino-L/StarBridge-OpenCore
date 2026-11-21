import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';
import 'package:starbridge_flutter/features/achievements/journey_station_markers.dart';

/// The achievement read sample shared with Host and the server tests.
void main() {
  final sample = jsonDecode(
    File('../contracts/achievements/read-response.json').readAsStringSync(),
  ) as Map<String, Object?>;

  for (final name in const [
    'empty',
    'withoutCities',
    'withCities',
    'withStations',
  ]) {
    test('$name stays readable', () {
      final payload = sample[name]! as Map<String, Object?>;
      final collection = BridgeAchievementCollection.parseCollection(
        payload,
        1,
      );
      expect(collection.isReady, isTrue);
      final earned = payload['earnedAt']! as Map<String, Object?>;
      expect(collection.earnedAt, {
        for (final entry in earned.entries)
          entry.key: DateTime.parse(entry.value! as String),
      });
      final progress = payload['progress']! as Map<String, Object?>;
      for (final entry in progress.entries) {
        expect(collection.progressFor(entry.key), entry.value);
      }
    });
  }

  test('accounts without cities stay inside the released client rule', () {
    final released = sample['releasedClientProgress']! as Map<String, Object?>;
    final keys = (released['keys']! as List<Object?>).toSet();
    for (final name in const ['empty', 'withoutCities']) {
      final payload = sample[name]! as Map<String, Object?>;
      final progress = payload['progress']! as Map<String, Object?>;
      expect(
        progress.length,
        lessThanOrEqualTo(released['maximumKeys']! as int),
      );
      expect(keys.containsAll(progress.keys), isTrue);
    }
  });

  test('station markers coexist with the released four-key progress shape', () {
    final original = sample['withCities']! as Map<String, Object?>;
    final awards = {
      ...original['earnedAt']! as Map<String, Object?>,
      for (final id in pyroStationMarkers) id: '2026-10-30T12:00:00Z',
      'journey-levski': '2026-10-30T12:00:00Z',
      'journey-pyro-majors': '2026-10-30T12:00:00Z',
      'journey-pyro-all': '2026-10-30T12:00:00Z',
      'journey-grimhex': '2026-11-05T12:00:00Z',
    };
    final payload = {...original, 'earnedAt': awards};
    final collection = BridgeAchievementCollection.parseCollection(payload, 1);
    expect(collection.isReady, isTrue);
    expect(collection.earnedAt.keys, containsAll(awards.keys));
    expect(
      collection.progress!.keys,
      unorderedEquals([
        'hangar-home',
        'hangar-collection',
        'hangar-paths',
        'journey-stanton',
      ]),
    );
    expect(collection.progressFor('journey-stanton'), 1);
    expect(collection.progressFor('journey-pyro-all'), isNull);
    expect(collection.progressFor('journey-grimhex'), isNull);
    // Marker suffixes do not join the hangar series or relax its continuity.
    expect(
      BridgeAchievementCollection.parseCollection({
        ...payload,
        'earnedAt': {...awards, 'hangar-home-2': '2026-10-30T12:00:00Z'}
          ..remove('hangar-home-1'),
        'progress': {...collection.progress!, 'hangar-home': 3},
      }, 1).isReady,
      isFalse,
    );
    for (final id in [
      'journey-pyro-majors',
      'journey-pyro-all',
      'journey-grimhex',
      'unknown',
    ]) {
      expect(
        BridgeAchievementCollection.parseCollection({
          ...payload,
          'progress': {id: 1},
        }, 1).isReady,
        isFalse,
      );
      expect(
        BridgeAchievementCollection.parseCollection({
          ...payload,
          'progress': {...collection.progress!, id: 1},
        }, 1).isReady,
        isFalse,
      );
    }
  });
}
