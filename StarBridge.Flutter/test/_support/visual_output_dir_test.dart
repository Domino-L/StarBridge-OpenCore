import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'visual_output_dir.dart';

void main() {
  final environment = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
  const define = String.fromEnvironment('STARBRIDGE_TEST_VISUAL_DIR');
  final configured = environment != null && environment.isNotEmpty
      ? environment
      : define;

  test('visual output uses the configured root or the legacy visual path', () {
    final expected = configured.isNotEmpty
        ? '$configured/example/visual'
        : '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path}/Documents/SC Fleet Command/work/example/visual';
    expect(visualOutputDir('example'), expected);
  });

  test('legacy review and batch-root locations survive without configuration', () {
    for (final directory in ['review', 'review-primary', '']) {
      final suffix = directory.isEmpty ? '' : '/$directory';
      final expected = configured.isNotEmpty
          ? '$configured/example/visual'
          : '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path}/Documents/SC Fleet Command/work/example$suffix';
      expect(
        visualOutputDir('example', legacySubdirectory: directory),
        expected,
      );
    }
  });
}
