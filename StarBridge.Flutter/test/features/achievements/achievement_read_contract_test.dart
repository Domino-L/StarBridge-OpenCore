import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';

/// The achievement read sample shared with Host and the server tests.
void main() {
  final sample = jsonDecode(
    File('../contracts/achievements/read-response.json').readAsStringSync(),
  ) as Map<String, Object?>;

  for (final name in const ['empty', 'withoutCities', 'withCities']) {
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
}
