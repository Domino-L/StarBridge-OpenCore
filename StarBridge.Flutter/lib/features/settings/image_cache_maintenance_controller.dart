import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/downloadable_image_cache.dart';
import 'image_maintenance_caches.dart';

/// Application-owned maintenance survives route disposal. It does not own the
/// borrowed Bridge or caches and never repeats an uncertain Native operation.
final class ImageCacheMaintenanceController extends ChangeNotifier {
  ImageCacheMaintenanceController(
    this.session, {
    Iterable<DownloadableImageCache> caches = const [],
  }) : _caches = ImageMaintenanceCaches(caches);

  final BridgeClientSession? session;
  final ImageMaintenanceCaches _caches;
  VoidCallback registerCache(DownloadableImageCache cache) =>
      _caches.attach(cache);
  Future<int>? _pending;
  bool _closed = false;
  bool get busy => _pending != null;
  String? _result;
  String? get result => _result;

  Future<int> clear() {
    if (_closed) return Future.error(StateError('Maintenance disposed'));
    final pending = _pending;
    if (pending != null) return pending;
    final completion = Completer<int>();
    _pending = completion.future;
    _result = null;
    notifyListeners();
    unawaited(_run(completion));
    return completion.future;
  }

  Future<void> _run(Completer<int> completion) async {
    Object? failure;
    StackTrace? trace;
    var count = 0;
    try {
      _caches.beginImageMaintenance();
      if (_closed || session == null) {
        throw StateError('Unavailable maintenance');
      }
      final reply = await session!.request(
        'diagnostics.clearImageCache',
        payload: const {'schemaVersion': 1},
      );
      final payload = reply.payload;
      if (payload.length != 2 ||
          payload['schemaVersion'] != 1 ||
          payload['count'] is! int ||
          (payload['count'] as int) < 0) {
        throw StateError('Invalid maintenance receipt');
      }
      count = payload['count'] as int;
    } catch (error, stack) {
      failure = error;
      trace = stack;
    } finally {
      // A failed/ambiguous purge still retires earlier image generations; every
      // participant is released, even if another participant's cleanup fails.
      try {
        _caches.endImageMaintenance();
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
      try {
        await _caches.imageMaintenanceSettled;
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
      _pending = null;
      _result = failure == null ? 'cleared' : 'failed';
      if (failure == null) {
        completion.complete(count);
      } else {
        completion.completeError(failure, trace);
      }
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _caches.dispose();
    super.dispose();
  }
}
