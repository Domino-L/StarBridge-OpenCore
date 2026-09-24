import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Content-addressed, memory-only cache. Callers must still supply authorized
/// image bytes; this is never an identity/URL lookup or permission cache.
final class InlineImageCache {
  final _entries = <String, MemoryImage>{};
  int _bytes = 0;
  static const maxBytes = 8 * 1024 * 1024;
  static const maxEntries = 64;
  static const decodeWidth = 128;
  static final _prefix = RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,');

  MemoryImage? resolve(String? source) {
    if (source == null || source.length > 699120 || !_prefix.hasMatch(source)) {
      return null;
    }
    final existing = _entries.remove(source);
    if (existing != null) {
      _entries[source] = existing;
      return existing;
    }
    try {
      final bytes = base64Decode(source.substring(source.indexOf(',') + 1));
      if (bytes.isEmpty || bytes.length > 512 * 1024) return null;
      final image = MemoryImage(bytes);
      _entries[source] = image;
      _bytes += source.length * 2 + bytes.length;
      while (_entries.length > maxEntries || _bytes > maxBytes) {
        _remove(_entries.keys.first);
      }
      return image;
    } on FormatException {
      return null;
    }
  }

  void _remove(String source) {
    final image = _entries.remove(source)!;
    _bytes -= source.length * 2 + image.bytes.length;
    unawaited(ResizeImage.resizeIfNeeded(decodeWidth, null, image).evict());
  }

  /// Session/account boundaries purge retained bytes and decoded frames.
  void clear() {
    for (final source in _entries.keys.toList()) {
      _remove(source);
    }
  }
}

/// The application owns cache lifetime; stand-alone widgets decode without
/// retaining a process-global cache. This scope contains no account lookup.
class InlineImageCacheScope extends InheritedWidget {
  const InlineImageCacheScope({
    required this.cache,
    required super.child,
    super.key,
  });
  final InlineImageCache cache;

  static MemoryImage? resolve(BuildContext context, String? source) =>
      (context
                  .dependOnInheritedWidgetOfExactType<InlineImageCacheScope>()
                  ?.cache ??
              InlineImageCache())
          .resolve(source);

  @override
  bool updateShouldNotify(InlineImageCacheScope oldWidget) =>
      cache != oldWidget.cache;
}
