import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'static_state_rule.dart';

void main() {
  final packageRoot = Directory.current;
  final libRoot = Directory('${packageRoot.path}${Platform.pathSeparator}lib');

  test('main.dart is a small composition entry and imports no feature', () {
    final mainFile = File('${libRoot.path}${Platform.pathSeparator}main.dart');
    final source = mainFile.readAsStringSync();
    expect(source.split('\n').length, lessThanOrEqualTo(100));
    expect(source, isNot(contains('features/')));
    expect(source, isNot(contains('MaterialApp')));
  });

  test('production Dart files stay within the architecture size gate', () {
    final violations = <String>[];
    for (final file in _dartFiles(libRoot)) {
      final lines = file.readAsLinesSync().length;
      if (lines > 800) {
        violations.add('${_relative(file, packageRoot)}: $lines lines');
      }
      if (lines > 500) {
        stderr.writeln(
          'ARCHITECTURE WARNING ${_relative(file, packageRoot)}: $lines lines',
        );
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Files over 800 lines require an explicit reviewed exception.',
    );
  });

  test('non-generated production files do not use part or part of', () {
    final violations = <String>[];
    for (final file in _dartFiles(libRoot)) {
      if (_isGenerated(file)) {
        continue;
      }
      final source = file.readAsStringSync();
      if (RegExp(r'^\s*part(?:\s+of)?\s+', multiLine: true).hasMatch(source)) {
        violations.add(_relative(file, packageRoot));
      }
    }
    expect(violations, isEmpty);
  });

  test('shell does not import feature implementation directories', () {
    final shellRoot = Directory(
      '${libRoot.path}${Platform.pathSeparator}app${Platform.pathSeparator}shell',
    );
    if (!shellRoot.existsSync()) {
      return;
    }
    final violations = <String>[];
    for (final file in _dartFiles(shellRoot)) {
      final source = file.readAsStringSync();
      if (source.contains('/features/') || source.contains('../../features/')) {
        violations.add(_relative(file, packageRoot));
      }
    }
    expect(violations, isEmpty);
  });

  test('features do not import another feature implementation', () {
    final featureRoot = Directory(
      '${libRoot.path}${Platform.pathSeparator}features',
    );
    final violations = <String>[];
    for (final file in _dartFiles(featureRoot)) {
      final ownFeature = _featureName(file, featureRoot);
      for (final import in _relativeImports(file.readAsStringSync())) {
        final normalized = import.replaceAll('\\', '/');
        final marker = '/features/';
        final markerIndex = normalized.indexOf(marker);
        if (markerIndex < 0) {
          continue;
        }
        final importedFeature = normalized
            .substring(markerIndex + marker.length)
            .split('/')
            .first;
        if (importedFeature != ownFeature) {
          violations.add('${_relative(file, packageRoot)} -> $import');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('no mutable global static business state is introduced', () {
    final violations = <String>[];
    for (final file in _dartFiles(libRoot)) {
      if (hasMutableStaticField(file.readAsStringSync())) {
        violations.add(_relative(file, packageRoot));
      }
    }
    expect(violations, isEmpty);
  });

  test('raw visual assets stay behind design-system resolvers', () {
    final violations = <String>[];
    for (final file in _dartFiles(libRoot)) {
      final relative = _relative(file, packageRoot);
      final source = file.readAsStringSync();
      if (source.contains('Color(0x') &&
          !relative.startsWith('lib/design_system/styles/')) {
        violations.add('$relative contains a raw color literal');
      }
      final insideIconModule = relative.startsWith('lib/design_system/icons/');
      if (source.contains('Icons.') && !insideIconModule) {
        violations.add('$relative selects a raw Material icon');
      }
      if (RegExp(r'\bIconData\b').hasMatch(source) && !insideIconModule) {
        violations.add('$relative uses raw IconData');
      }
      if (source.contains('StarBridgeIconSet.resolve') && !insideIconModule) {
        violations.add('$relative bypasses StarBridgeIcon');
      }
    }
    expect(violations, isEmpty);
  });

  test('Windows Native Host transport stays overlapped and bounded', () {
    final source = File(
      'windows${Platform.pathSeparator}runner${Platform.pathSeparator}'
      'native_host_bridge.cpp',
    ).readAsStringSync();

    expect(source, contains('FILE_FLAG_OVERLAPPED'));
    expect(source, contains('OVERLAPPED operation'));
    expect(source, contains('CancelIoEx'));
    expect(source, contains('kMaximumFrameBytes'));
    expect(source, contains('kMaximumQueuedFrames'));
  });
}

Iterable<File> _dartFiles(Directory root) sync* {
  if (!root.existsSync()) {
    return;
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

bool _isGenerated(File file) =>
    file.path.endsWith('.g.dart') || file.path.endsWith('.freezed.dart');

String _relative(File file, Directory root) =>
    file.path.substring(root.path.length + 1).replaceAll('\\', '/');

String _featureName(File file, Directory featureRoot) {
  return file.path
      .substring(featureRoot.path.length + 1)
      .split(Platform.pathSeparator)
      .first;
}

Iterable<String> _relativeImports(String source) sync* {
  final pattern = RegExp("^\\s*import\\s+['\"]([^'\"]+)['\"]", multiLine: true);
  for (final match in pattern.allMatches(source)) {
    final value = match.group(1)!;
    if (!value.startsWith('package:') && !value.startsWith('dart:')) {
      yield value;
    }
  }
}
