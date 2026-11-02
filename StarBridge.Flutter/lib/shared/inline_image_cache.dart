import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'downloadable_image_cache.dart';

enum _InlineImagePurpose { preserved, downloadable }

/// Content-addressed, memory-only cache. Callers must still supply authorized
/// image bytes; this is never an identity/URL lookup or permission cache.
final class InlineImageCache extends ChangeNotifier
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  final _entries =
      <String, ({MemoryImage image, Set<_InlineImagePurpose> purposes})>{};
  final _admissions = Expando<int>();
  int _imageEpoch = 0;
  int _maintenanceDepth = 0;
  bool _closed = false;
  int _bytes = 0;
  static const maxBytes = 8 * 1024 * 1024;
  static const maxEntries = 64;
  static const decodeWidth = 128;
  static final _prefix = RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,');

  MemoryImage? resolve(String? source, {Object? downloadedBy}) {
    if (_closed) {
      return null;
    }
    if (downloadedBy != null) {
      // Borrow an immutable source snapshot, never an account or permission.
      // Observe paused arrivals too: they cannot become fresh just by waiting.
      try {
        final admitted = _admissions[downloadedBy] ??= _imageEpoch;
        if (_maintenanceDepth > 0 || admitted != _imageEpoch) {
          return null;
        }
      } on ArgumentError {
        return null; // Strings/numbers/records are not weak snapshot identities.
      }
    }
    final purpose = downloadedBy == null
        ? _InlineImagePurpose.preserved
        : _InlineImagePurpose.downloadable;
    if (source == null || source.length > 699120 || !_prefix.hasMatch(source)) {
      return null;
    }
    final existing = _entries.remove(source);
    if (existing != null) {
      _entries[source] = existing;
      existing.purposes.add(purpose);
      return existing.image;
    }
    try {
      final bytes = base64Decode(source.substring(source.indexOf(',') + 1));
      if (bytes.isEmpty || bytes.length > 512 * 1024) return null;
      final image = MemoryImage(bytes);
      _entries[source] = (image: image, purposes: {purpose});
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
    final image = _entries.remove(source)!.image;
    _bytes -= source.length * 2 + image.bytes.length;
    unawaited(ResizeImage.resizeIfNeeded(decodeWidth, null, image).evict());
  }

  /// Session/account boundaries purge retained bytes and decoded frames.
  void clear() {
    _imageEpoch++;
    for (final source in _entries.keys.toList()) {
      _remove(source);
    }
  }

  void _retireDownloaded() {
    _imageEpoch++;
    for (final key in _entries.keys.toList()) {
      final entry = _entries[key]!;
      if (entry.purposes.remove(_InlineImagePurpose.downloadable) &&
          entry.purposes.isEmpty) {
        _remove(key);
      }
    }
    notifyListeners();
  }

  @override
  void beginImageMaintenance() {
    if (_closed) {
      return;
    }
    _maintenanceDepth++;
    _retireDownloaded();
  }

  @override
  void endImageMaintenance() {
    if (_closed) {
      return;
    }
    if (_maintenanceDepth > 0) {
      _maintenanceDepth--;
    }
    _retireDownloaded();
  }

  @override
  Future<void> get imageMaintenanceSettled => _closed
      ? Future.value()
      : WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 3));
  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    clear();
    super.dispose();
  }
}

/// The application owns cache lifetime; stand-alone widgets decode without
/// retaining a process-global cache. This scope contains no account lookup.
class InlineImageCacheScope extends InheritedNotifier<InlineImageCache> {
  const InlineImageCacheScope({
    required InlineImageCache cache,
    required super.child,
    super.key,
  }) : super(notifier: cache);
  InlineImageCache get cache => notifier!;

  static InlineImageCache? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InlineImageCacheScope>()
      ?.cache;

  static MemoryImage? resolve(
    BuildContext context,
    String? source, {
    Object? downloadedBy,
  }) => (maybeOf(context) ?? InlineImageCache()).resolve(
    source,
    downloadedBy: downloadedBy,
  );
}
