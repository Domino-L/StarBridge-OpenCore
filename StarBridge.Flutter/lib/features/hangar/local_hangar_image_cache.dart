import 'dart:convert';
import 'dart:typed_data';

import 'local_hangar_images.dart';

/// Bounded decoded images for one page owner. Null results are cached too.
class LocalHangarImageCache {
  final _entries = <String, Future<Uint8List?>>{};
  int _epoch = 0;

  void clear() {
    ++_epoch;
    _entries.clear();
  }

  Future<Uint8List?> read(String key, LocalHangarImagePort port) {
    final previous = _entries.remove(key);
    if (previous != null) return _entries[key] = previous;
    if (_entries.length >= 16) _entries.remove(_entries.keys.first);
    final epoch = _epoch;
    late final Future<Uint8List?> pending;
    pending = () async {
      try {
        final result = decode(await port.readImage());
        return epoch == _epoch ? result : null;
      } catch (_) {
        if (identical(_entries[key], pending)) _entries.remove(key);
        rethrow;
      }
    }();
    return _entries[key] = pending;
  }

  static Uint8List? decode(String? value) {
    const prefix = 'data:image/png;base64,';
    if (value == null) return null;
    if (!value.startsWith(prefix) || value.length > 700000) {
      throw const FormatException('Invalid ship image');
    }
    final bytes = base64Decode(value.substring(prefix.length));
    if (bytes.length > 512 * 1024) {
      throw const FormatException('Ship image exceeds limit');
    }
    return bytes;
  }
}
