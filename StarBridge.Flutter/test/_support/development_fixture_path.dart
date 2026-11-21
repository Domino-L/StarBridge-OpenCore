import 'dart:io';

/// Resolves optional development fixtures within the checkout that owns the tests.
String developmentFixturePath(String relative) {
  for (var directory = Directory.current; ; directory = directory.parent) {
    final root = directory.uri;
    if (File.fromUri(root.resolve('StarBridge.Flutter/pubspec.yaml'))
        .existsSync()) {
      final fixture = root.resolveUri(Uri.file(relative)).normalizePath();
      final rootPath = root.toFilePath();
      final fixturePath = fixture.toFilePath();
      final inside = Platform.isWindows
          ? fixturePath.toLowerCase().startsWith(rootPath.toLowerCase())
          : fixturePath.startsWith(rootPath);
      if (!inside || fixturePath.length <= rootPath.length) {
        throw ArgumentError.value(relative, 'relative', 'Outside the checkout');
      }
      return fixturePath;
    }
    final git = root.resolve('.git');
    if (Directory.fromUri(git).existsSync() ||
        File.fromUri(git).existsSync() ||
        directory.parent.path == directory.path) {
      throw StateError('StarBridge test checkout not found');
    }
  }
}
