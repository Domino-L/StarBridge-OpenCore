import 'dart:async';
import 'dart:io';

/// One active transfer per client isolates forced cancellation, while idle
/// clients keep their existing connection pools for subsequent images. The
/// root and its borrowed loaders share this bounded pool, not credentials.
final class RemoteImageTransportPool {
  RemoteImageTransportPool(this._createClient);
  final HttpClient Function() _createClient;
  final _idle = <HttpClient>[];
  final _queue = <RemoteImageTransport>[];
  final _all = <RemoteImageTransport>{};
  final _active = <RemoteImageTransport>{};
  bool _closed = false;

  RemoteImageTransport? take() {
    if (_closed || _all.length >= 64) return null;
    final work = RemoteImageTransport._(this);
    _all.add(work);
    _queue.add(work);
    _pump();
    return work;
  }

  void _pump() {
    while (!_closed && _active.length < 6 && _queue.isNotEmpty) {
      final work = _queue.removeAt(0);
      try {
        work._client = _idle.isEmpty ? _createClient() : _idle.removeLast();
        _active.add(work);
        work._ready.complete(work._client);
      } on Object {
        _all.remove(work);
        work._ready.complete(null);
      }
    }
  }

  void closeIdle() {
    for (final client in _idle) {
      client.close(force: true);
    }
    _idle.clear();
  }

  void dispose() {
    _closed = true;
    for (final work in _all.toList()) {
      work.cancel();
    }
    closeIdle();
  }
}

final class RemoteImageTransport {
  RemoteImageTransport._(this._pool);
  final RemoteImageTransportPool _pool;
  final _ready = Completer<HttpClient?>();
  Future<HttpClient?> get ready => _ready.future;
  HttpClient? _client;
  bool _cancelled = false, _released = false;

  void cancel() {
    if (_cancelled || _released) return;
    _cancelled = true;
    final current = _client;
    if (current != null) {
      // Keep the active permit until the caller's actual IO exits and releases
      // it. Closing a client is cancellation, not proof of a drained future.
      current.close(force: true);
    } else {
      _pool._queue.remove(this);
      _pool._all.remove(this);
      if (!_ready.isCompleted) _ready.complete(null);
      _pool._pump();
    }
  }

  void release({required bool reuse}) {
    if (_released) return;
    _released = true;
    if (_pool._active.remove(this)) {
      final current = _client!;
      if (reuse && !_cancelled && !_pool._closed) {
        _pool._idle.add(current);
      } else {
        current.close(force: true);
      }
    } else {
      _pool._queue.remove(this);
      if (!_ready.isCompleted) _ready.complete(null);
    }
    _pool._all.remove(this);
    _pool._pump();
  }
}
