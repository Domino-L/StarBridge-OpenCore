import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const openCoreTestSource = bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE');

bool restrictedFileIsAbsent(String path) {
  // existsSync also returns false for some I/O errors. Only missing paths qualify.
  try {
    File(path).openSync().closeSync();
    return false;
  } on PathNotFoundException {
    return true;
  }
}

String? restrictedFileSkip(
  String testName,
  String kind,
  String path, {
  bool publicSource = openCoreTestSource,
}) => publicSource && restrictedFileIsAbsent(path)
    ? 'SKIP $testName: open-core restricted $kind $path absent'
    : null;

void restrictedTestWidgets(
  String name,
  WidgetTesterCallback callback, {
  required String kind,
  required String path,
}) {
  final skip = restrictedFileSkip(name, kind, path);
  if (skip != null) {
    // testWidgets only accepts a bool. A skipped test preserves the reason.
    test(name, () {}, skip: skip);
  } else {
    testWidgets(name, callback);
  }
}
