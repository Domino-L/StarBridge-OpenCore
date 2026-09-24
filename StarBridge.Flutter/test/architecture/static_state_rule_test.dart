import 'package:flutter_test/flutter_test.dart';

import 'static_state_rule.dart';

void main() {
  test('expression getters are not mutable static fields', () {
    expect(hasMutableStaticField('static String get name => "name";'), isFalse);
    expect(
      hasMutableStaticField('static List<String> get values => ["one"];'),
      isFalse,
    );
  });

  test('mutable static fields remain rejected', () {
    for (final source in [
      'static int count = 0;',
      'static bool registered = false;',
      'static Object? value;',
      'static late String value;',
      'static Map<String, int> values = {};',
    ]) {
      expect(hasMutableStaticField(source), isTrue, reason: source);
    }
  });

  test('immutable declarations and methods are not fields', () {
    for (final source in [
      'static const count = 1;',
      'static final values = <String>[];',
      'static String name(String id) => id;',
    ]) {
      expect(hasMutableStaticField(source), isFalse, reason: source);
    }
  });
}
