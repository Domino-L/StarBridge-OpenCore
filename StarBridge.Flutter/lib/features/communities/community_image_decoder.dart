import 'dart:typed_data';
import 'dart:ui' as ui;

typedef CommunityImageDecoder = Future<ui.Image> Function(Uint8List, int);

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
  CommunityImageDecodeCache({this.decoder = decodeCommunityImage});
  final CommunityImageDecoder decoder;
  final _entries = <(Uint8List, int), _ImageEntry>{};
  bool _disposed = false;

  Future<ui.Image> decode(Uint8List bytes, int maxWidth) async {
    if (_disposed) throw StateError('Disposed images');
    final key = (bytes, maxWidth);
    var entry = _entries.remove(key);
    if (entry == null) {
      if (_entries.length >= 64) {
        _entries.remove(_entries.keys.first)!.retire();
      }
      entry = _ImageEntry(decoder(bytes, maxWidth));
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
  _ImageEntry(this.future) {
    future.then((value) {
      image = value;
      release();
    }, onError: (Object _) {});
  }
  final Future<ui.Image> future;
  ui.Image? image;
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
