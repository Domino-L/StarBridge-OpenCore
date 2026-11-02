import 'dart:async';
import 'dart:io';

import 'diagnostics/loading_metrics.dart';

/// Observes consumed HTTP body only; never headers, TLS or total wire traffic.
/// A partial/discarded or decoded body has no known encoded-byte total.
final class RemoteImageTransferMetrics {
  RemoteImageTransferMetrics._(this._metrics, this._id);
  static void present() =>
      LoadingMetrics.current?.imageTransferRecorderPresent();
  static RemoteImageTransferMetrics? start(int hop) {
    final metrics = LoadingMetrics.current;
    final id = metrics?.imageTransferStarted(hop: hop);
    return id == null ? null : RemoteImageTransferMetrics._(metrics!, id);
  }

  final LoadingMetrics _metrics;
  final int _id;
  int _statusCode = 0, _consumed = 0;
  bool _complete = false, _finished = false;
  LoadingImageBodyEncoding _encoding = LoadingImageBodyEncoding.unknown;

  Stream<List<int>> observe(HttpClientResponse response) {
    try {
      _statusCode = response.statusCode;
      _encoding = switch (response.compressionState) {
        HttpClientResponseCompressionState.notCompressed ||
        HttpClientResponseCompressionState.compressed =>
          LoadingImageBodyEncoding.encoded,
        HttpClientResponseCompressionState.decompressed =>
          LoadingImageBodyEncoding.decoded,
      };
    } on Object {
      // An incomplete test/custom response cannot make observation affect IO.
      _encoding = LoadingImageBodyEncoding.unknown;
    }
    return StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        if (!_metrics.stopped) _consumed += chunk.length;
        sink.add(chunk);
      },
      handleDone: (sink) {
        _complete = true;
        sink.close();
      },
    ).bind(response);
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _metrics.imageTransferFinished(
      id: _id,
      statusCode: _statusCode,
      consumedBodyBytes: _consumed,
      bodyComplete: _complete,
      encoding: _encoding,
    );
  }
}
