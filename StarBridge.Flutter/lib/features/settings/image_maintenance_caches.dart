import 'package:flutter/foundation.dart';

import '../../shared/downloadable_image_cache.dart';

/// Borrows existing resource owners. Registration never creates/disposes an
/// owner; admission during a purge joins its pause and confirmation phase.
final class ImageMaintenanceCaches
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  ImageMaintenanceCaches(Iterable<DownloadableImageCache> caches) {
    for (final cache in caches) {
      _registered[cache] = 1;
    }
  }
  final _registered = Map<DownloadableImageCache, int>.identity();
  final _entered = <DownloadableImageCache>[];
  bool _paused = false, _closed = false;
  Object? _failure;
  StackTrace? _trace;

  VoidCallback attach(DownloadableImageCache cache) {
    if (_closed) {
      throw StateError('Maintenance owners disposed');
    }
    _registered[cache] = (_registered[cache] ?? 0) + 1;
    var attached = true;
    void detach() {
      if (!attached) {
        return;
      }
      attached = false;
      final count = _registered[cache];
      if (count == null) {
        return;
      }
      if (count <= 1) {
        _registered.remove(cache);
      } else {
        _registered[cache] = count - 1;
      }
    }

    if (_paused && !_entered.any((owner) => identical(owner, cache))) {
      final failed = _enter(cache);
      if (failed != null) {
        detach();
        Error.throwWithStackTrace(failed.$1, failed.$2);
      }
    }
    return detach;
  }

  (Object, StackTrace)? _enter(DownloadableImageCache cache) {
    if (_entered.any((owner) => identical(owner, cache))) {
      return null;
    }
    _entered.add(cache);
    try {
      cache.beginImageMaintenance();
    } catch (error, stack) {
      _record(error, stack);
      return (error, stack);
    }
    return null;
  }

  void _record(Object error, StackTrace stack) {
    _failure ??= error;
    _trace ??= stack;
  }

  void _throwFailure() {
    if (_failure != null) {
      Error.throwWithStackTrace(_failure!, _trace!);
    }
  }

  @override
  void beginImageMaintenance() {
    if (_closed) {
      throw StateError('Maintenance owners disposed');
    }
    _failure = _trace = null;
    _entered.clear();
    _paused = true;
    for (final cache in _registered.keys.toList()) {
      _enter(cache);
    }
    _throwFailure();
  }

  @override
  void endImageMaintenance() {
    _paused = false;
    for (final cache in _entered.reversed.toList()) {
      try {
        cache.endImageMaintenance();
      } catch (error, stack) {
        _record(error, stack);
      }
    }
    _throwFailure();
  }

  @override
  Future<void> get imageMaintenanceSettled async {
    final waiting = <Future<(Object?, StackTrace?)>>[];
    for (final cache in _entered.toList()) {
      if (cache case final ImageCacheMaintenanceBarrier barrier) {
        waiting.add(_confirm(barrier));
      }
    }
    for (final receipt in await Future.wait(waiting)) {
      if (receipt.$1 != null) {
        _record(receipt.$1!, receipt.$2!);
      }
    }
    _entered.clear();
    final failure = _failure, trace = _trace;
    _failure = _trace = null;
    if (failure != null) {
      Error.throwWithStackTrace(failure, trace!);
    }
  }

  Future<(Object?, StackTrace?)> _confirm(
    ImageCacheMaintenanceBarrier barrier,
  ) async {
    try {
      await barrier.imageMaintenanceSettled;
      return (null, null);
    } catch (error, stack) {
      return (error, stack);
    }
  }

  void dispose() {
    _closed = true;
    _registered.clear();
  }
}
