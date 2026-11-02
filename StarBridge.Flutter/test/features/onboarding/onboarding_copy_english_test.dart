import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy_behavior_prompt.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy_profile.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy_setup.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy_verify.dart';

// CX-34: first-use copy is written as (zh-Hans, zh-Hant, en) triples. Guards
// that the English item never carries Chinese, including the private tables.
final _han = RegExp(r'[㐀-鿿豈-﫿　-〿＀-￯]');

/// Keys of a `'key': (` or `'key': [` map entry in a copy source file.
Iterable<String> _sourceKeys(String path) => RegExp(
  r"^\s*'([A-Za-z0-9_.]+)':\s*[\(\[]",
  multiLine: true,
).allMatches(File(path).readAsStringSync()).map((m) => m[1]!);

void main() {
  const en = OnboardingCopy(Locale('en', 'US'));
  final tables = {
    'setup': onboardingSetupWords,
    'profile': onboardingProfileWords,
    'verify': onboardingVerifyWords,
    'behaviorPrompt': onboardingBehaviorPromptWords,
  };

  test('public copy tables have Chinese-free English items', () {
    for (final MapEntry(key: table, value: words) in tables.entries) {
      for (final MapEntry(:key, :value) in words.entries) {
        // Blank in every language is a deliberate "show nothing".
        if (value.$1.isNotEmpty) {
          expect(value.$3.trim(), isNotEmpty, reason: '$table/$key');
        }
        expect(_han.hasMatch(value.$3), isFalse, reason: '$table/$key');
      }
    }
  });

  test('every OnboardingCopy key reads Chinese-free in English', () {
    final keys = _sourceKeys('lib/features/onboarding/onboarding_copy.dart');
    expect(keys.length, greaterThan(50), reason: 'source scan found the map');
    for (final key in keys) {
      final value = en.text(key);
      expect(value.trim(), isNotEmpty, reason: key);
      expect(_han.hasMatch(value), isFalse, reason: key);
    }
  });

  test('recovery dialog English items are Chinese-free', () {
    final source = File(
      'lib/features/onboarding/first_use_recovery_dialog.dart',
    ).readAsStringSync();
    final entries = RegExp(
      r"'([A-Za-z0-9_.]+)':\s*\[(.*?)\]",
      dotAll: true,
    ).allMatches(source).toList();
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      final items = RegExp(r"'((?:[^'\\]|\\.)*)'")
          .allMatches(entry[2]!)
          .map((m) => m[1]!)
          .toList();
      expect(items, hasLength(3), reason: entry[1]);
      expect(_han.hasMatch(items[2]), isFalse, reason: entry[1]);
    }
  });
}
