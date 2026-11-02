import 'dart:typed_data';
import 'dart:ui' as ui;

typedef CommunityImageDecoder = Future<ui.Image> Function(Uint8List, int);

/// A synchronously available decoded frame (caller owns it), or null.
typedef CommunityImagePeek = ui.Image? Function(Uint8List, int);

/// The caller owns the returned first frame. Reject oversized source images
/// before decoding and bound both output dimensions.
Future<ui.Image> decodeCommunityImage(Uint8List bytes, int maxWidth) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width * descriptor.height > 16 * 1024 * 1024) {
      throw const FormatException('Image dimensions');
    }
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = (maxWidth / longest).clamp(0.0, 1.0);
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(1, maxWidth),
      targetHeight: (descriptor.height * scale).round().clamp(1, maxWidth),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Conversation-local decoded images, never Flutter's global image cache.
/// Each widget receives a cheap clone and owns its handle independently.
class CommunityImageDecodeCache {
  CommunityImageDecodeCache({
    this.decoder = decodeCommunityImage,
    this.now = DateTime.now,
    this.capacity = 64,
  });
  final CommunityImageDecoder decoder;
  final DateTime Function() now;

  /// Decoded first frames kept for reuse; a long member list scrolled back
  /// and forth must not decode (and show loading) again (2026-10-21 report).
  final int capacity;
  final _entries = <(Uint8List, int), _ImageEntry>{};
  bool _disposed = false;

  /// An already decoded frame for exactly these bytes, without waiting a frame.
  /// The caller owns the returned clone. Null when not decoded yet.
  ui.Image? peek(Uint8List bytes, int maxWidth) {
    if (_disposed) return null;
    final key = (bytes, maxWidth);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    final image = entry.image;
    return entry.retired || image == null ? null : image.clone();
  }

  Future<ui.Image> decode(Uint8List bytes, int maxWidth) async {
    if (_disposed) throw StateError('Disposed images');
    final key = (bytes, maxWidth);
    var entry = _entries.remove(key);
    if (entry?.retryAt case final retryAt? when !now().isBefore(retryAt)) {
      entry!.retire();
      entry = null;
    }
    if (entry == null) {
      if (_entries.length >= capacity) {
        _entries.remove(_entries.keys.first)!.retire();
      }
      entry = _ImageEntry(
        Future<ui.Image>.sync(() => decoder(bytes, maxWidth)),
        now,
      );
    }
    _entries[key] = entry;
    entry.readers++;
    try {
      final image = await entry.future;
      if (_disposed) throw StateError('Disposed images');
      return image.clone();
    } finally {
      entry.readers--;
      entry.release();
    }
  }

  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.retire();
    }
    _entries.clear();
  }
}

class _ImageEntry {
  _ImageEntry(this.future, DateTime Function() now) {
    future.then(
      (value) {
        image = value;
        release();
      },
      onError: (Object _) {
        // Failed decoding is not a permanent image. Coalesce a short backoff,
        // then let the next caller retry without timers or background work.
        retryAt = now().add(const Duration(seconds: 10));
      },
    );
  }
  final Future<ui.Image> future;
  ui.Image? image;
  DateTime? retryAt;
  int readers = 0;
  bool retired = false;
  void retire() {
    retired = true;
    release();
  }

  void release() {
    if (retired && readers == 0) {
      image?.dispose();
      image = null;
    }
  }
}
