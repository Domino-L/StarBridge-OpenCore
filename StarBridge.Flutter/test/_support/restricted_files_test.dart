import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'restricted_files.dart';

void main() {
  test(
    'a present malformed restricted sample fails parsing instead of skipping',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'restricted-sample-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final sample = File('${directory.path}/synthetic.json');
      const name = 'synthetic contract';

      expect(
        restrictedFileSkip(name, 'sample', sample.path, publicSource: true),
        startsWith('SKIP $name: open-core restricted sample '),
      );
      sample.writeAsStringSync('{');
      expect(
        restrictedFileSkip(name, 'sample', sample.path, publicSource: true),
        isNull,
      );
      expect(
        () => jsonDecode(sample.readAsStringSync()),
        throwsFormatException,
      );
    },
  );
}
