import 'dart:io';

/// Finds an optional sibling fixture without embedding a developer drive path.
/// Explicit absolute overrides remain usable; unconfigured exports need no data.
String developmentFixturePath(String relative) {
  if (File(relative).isAbsolute) return relative;
  var ancestor = Directory.current;
  var prefix = '';
  final sibling = relative.split('/').first;
  while (true) {
    if (Directory('$prefix$sibling').existsSync()) return '$prefix$relative';
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
    prefix = '../$prefix';
  }
  return '../../$relative';
}
