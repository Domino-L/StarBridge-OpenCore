import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/callsign_rules.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_controller.dart';

Map<String, Object?> _scm([Map<String, Object?> extra = const {}]) => {
  'schemaVersion': 1,
  'revision': 1,
  'locations': 4,
  'canConfigure': true,
  'identityStamp': 'a' * 64,
  'callsign': '飞鹰',
  'mirror': 'synced',
  ...extra,
};

void main() {
  test('callsign weight counts UTF-16 units like the Relay and the Host', () {
    expect(CallsignRules.weight('飞鹰'), 4);
    expect(CallsignRules.weight('Ace'), 3);
    // A supplementary-plane emoji is two code units, as in .NET.
    expect(CallsignRules.weight('🚀'), 2);
    expect(CallsignRules.valid('🚀🚀🚀🚀🚀'), isTrue);
    expect(CallsignRules.valid('🚀🚀🚀🚀🚀🚀'), isFalse);
    expect(CallsignRules.valid('中文中文中'), isTrue);
    expect(CallsignRules.valid('中文中文中文'), isFalse);
    expect(CallsignRules.valid('  '), isTrue, reason: 'blank clears');
  });

  test('control characters follow .NET char.IsControl', () {
    // Inside the name: trimming (Dart and .NET alike) removes them at the ends.
    for (final bad in ['A\u0001B', 'A\u007fB', 'A\u0085B', 'A\nB']) {
      expect(CallsignRules.valid(bad), isFalse, reason: bad.codeUnits.join(','));
    }
    expect(CallsignRules.valid('A B'), isTrue);
  });

  test('seven-field SCM snapshot needs exactly the expected keys', () {
    expect(GameIdVisibilityController.validate(_scm()), isNotEmpty);
    final missing = _scm()..remove('callsign');
    expect(
      () => GameIdVisibilityController.validate({...missing, 'extra': 1}),
      throwsFormatException,
    );
    expect(
      () => GameIdVisibilityController.validate(_scm({'mirror': 'maybe'})),
      throwsFormatException,
    );
    expect(
      () => GameIdVisibilityController.validate(_scm({'callsign': '中文中文中文'})),
      throwsFormatException,
    );
    expect(
      () => GameIdVisibilityController.validate(_scm({'callsign': ' 飞鹰'})),
      throwsFormatException,
    );
    for (final state in ['synced', 'pending', 'restorePending', 'unknown']) {
      expect(
        GameIdVisibilityController.validate(_scm({'mirror': state}))['mirror'],
        state,
      );
    }
  });
}
