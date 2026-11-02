import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_index.dart';

class Entry extends LicenseEntry {
  Entry(this.names);
  final List<String> names;
  int decoded = 0;
  @override
  Iterable<String> get packages => names;
  @override
  Iterable<LicenseParagraph> get paragraphs {
    decoded++;
    return [const LicenseParagraph('Exact paragraph', 2)];
  }
}

void main() {
  test('first registry package is pinned, remaining identities sorted without case folding', () {
    final entries = [
      Entry(['zApp']),
      Entry(['Beta', 'alpha']),
      Entry(['ALPHA', 'Zoo']),
    ];
    final index = ThirdPartyLicenseIndex(entries);
    expect(index.packages.first.name, 'zApp');
    expect(index.packages.skip(1).map((p) => p.name.toLowerCase()), [
      'alpha',
      'alpha',
      'beta',
      'zoo',
    ]);
    expect(index.packages.map((p) => p.name).toSet(), {
      'zApp',
      'Beta',
      'alpha',
      'ALPHA',
      'Zoo',
    });
    expect(entries.map((e) => e.decoded), everyElement(0));
  });
  test(
    'many-package and duplicate bindings retain original objects and order',
    () {
      final a = Entry(['App', 'Shared', 'Shared']),
          b = Entry(['Shared']),
          c = Entry(['Other', 'Shared']);
      final index = ThirdPartyLicenseIndex([a, b, c]);
      final shared = index.packages.singleWhere((p) => p.name == 'Shared');
      expect(shared.entries, [a, a, b, c]);
      expect(identical(shared.entries.first, a), isTrue);
      expect(shared.entries.length, 4);
      expect([a, b, c].map((e) => e.decoded), everyElement(0));
    },
  );
  test('immutable projection and no eager paragraph decoding', () {
    final entry = Entry(['App']);
    final index = ThirdPartyLicenseIndex([entry]);
    expect(() => index.packages.clear(), throwsUnsupportedError);
    expect(() => index.packages.single.entries.clear(), throwsUnsupportedError);
    expect(entry.decoded, 0);
    expect(
      index.packages.single.entries.single.paragraphs.single.text,
      'Exact paragraph',
    );
    expect(entry.decoded, 1);
  });
  test('empty registry and entries without package bindings stay empty', () {
    expect(ThirdPartyLicenseIndex([]).packages, isEmpty);
    final entry = Entry([]);
    expect(ThirdPartyLicenseIndex([entry]).packages, isEmpty);
    expect(entry.decoded, 0);
  });
}
