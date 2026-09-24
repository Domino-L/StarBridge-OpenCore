import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';

void main() {
  test('required CIG Fankit notice is bundled without rewriting', () {
    final noticeFile = File('assets/legal/CIG-FANKIT-NOTICE.txt');
    expect(noticeFile.existsSync(), isTrue);
    final normalizedNotice = noticeFile.readAsStringSync().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    expect(normalizedNotice, contains(CigFankitLegalNotice.requiredEnglish));

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/legal/'));
  });
}
