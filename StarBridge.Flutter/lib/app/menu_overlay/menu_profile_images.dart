import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../features/communities/community_image_decoder.dart';
import '../../shared/remote_image_loader.dart';

/// Window-local media cache. Only bounded PNG thumbnails leave the primary
/// engine; no cookies, account credentials or remote URLs reach the renderer.
final class MenuProfileImages {
  MenuProfileImages({
    DateTime Function()? now,
    this.remoteImages,
    this.kind = RemoteImageResourceKind.other,
    CommunityImageDecoder? decoder,
  }) : _now = now ?? DateTime.now,
       _decoder = decoder ?? decodeCommunityImage {
    final remote = remoteImages;
    if (remote != null && !remote.retired) {
      remote.addListener(_remoteChanged);
    }
  }
  final RemoteImageLoader? remoteImages;
  final RemoteImageResourceKind kind;
  final DateTime Function() _now;
  final CommunityImageDecoder _decoder;
  static const _maxBytes = 512 * 1024;
  final _entries = <String, _ProfileImage>{};
  bool _disposed = false;
  static final _inline = RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,');

  void _remoteChanged() => _entries.clear();

  bool _current(String source, _ProfileImage entry) {
    if (_disposed || !identical(_entries[source], entry)) return false;
    final remote = remoteImages;
    return !entry.remote ||
        remote != null &&
            !remote.retired &&
            remote.readEpoch == entry.readEpoch;
  }

  bool _retains(String source, Uint8List bytes) =>
      remoteImages?.retains(
        source,
        bytes,
        maxBytes: _maxBytes,
        followRedirects: false,
        kind: kind,
      ) ??
      false;

  String? cached(String? source) {
    final entry = _entries[source];
    if (_disposed || entry == null) return null;
    if (!entry.remote) return entry.value;
    final uri = source == null ? null : remoteUri(source);
    final bytes = uri == null
        ? null
        : remoteImages?.cached(
            uri.toString(),
            maxBytes: _maxBytes,
            followRedirects: false,
            kind: kind,
          );
    // Transformed data cannot outlive its raw retention/display policy.
    return bytes != null && identical(entry.sourceBytes?.target, bytes)
        ? entry.value
        : null;
  }

  Future<String?> load(String? source) {
    if (_disposed || source == null || source.length > 699120) {
      return Future.value(null);
    }
    final remote = !_inline.hasMatch(source);
    if (remote && remoteUri(source) == null) return Future.value(null);
    final previous = _entries[source];
    if (previous != null &&
        (previous.loading || !remote && _now().isBefore(previous.expires))) {
      return previous.pending;
    }
    if (_entries.length >= 32) _entries.remove(_entries.keys.first);
    final entry =
        _ProfileImage(_now().add(const Duration(seconds: 10)), remote: remote)
          ..value = previous?.value
          ..sourceBytes = previous?.sourceBytes
          ..failedBytes = previous?.failedBytes
          ..readEpoch = remoteImages?.readEpoch;
    _entries[source] = entry;
    entry.pending = _load(source, entry, previous).then((value) {
      entry.loading = false;
      if (!_current(source, entry)) {
        if (identical(_entries[source], entry)) _entries.remove(source);
        return null;
      }
      if (!entry.retain) {
        _entries.remove(source);
        return value;
      }
      entry.value = value ?? entry.value;
      entry.expires = _now().add(
        value == null
            ? const Duration(seconds: 10)
            : const Duration(minutes: 5),
      );
      return value;
    });
    return entry.pending;
  }

  Future<String?> _load(
    String source,
    _ProfileImage entry,
    _ProfileImage? previous,
  ) async {
    Uint8List? remoteBytes;
    try {
      final Uint8List bytes;
      if (!entry.remote) {
        bytes = base64Decode(source.substring(source.indexOf(',') + 1));
      } else {
        final uri = remoteUri(source);
        if (uri == null) return null;
        final downloaded = await remoteImages?.load(
          uri.toString(),
          maxBytes: _maxBytes,
          followRedirects: false,
          kind: kind,
        );
        if (!_current(source, entry)) return null;
        if (downloaded == null) {
          final oldBytes =
              previous?.sourceBytes?.target ?? previous?.failedBytes?.target;
          entry.retain = oldBytes != null && _retains(uri.toString(), oldBytes);
          return null;
        }
        bytes = downloaded;
        remoteBytes = downloaded;
        entry.retain = _retains(uri.toString(), bytes);
        final oldValue = previous?.value;
        if (entry.retain &&
            oldValue != null &&
            identical(previous?.sourceBytes?.target, bytes)) {
          entry.sourceBytes = previous?.sourceBytes;
          entry.failedBytes = null;
          return oldValue;
        }
        if (identical(previous?.failedBytes?.target, bytes) &&
            previous != null &&
            _now().isBefore(previous.expires)) {
          return null;
        }
      }
      if (!_current(source, entry) ||
          bytes.isEmpty ||
          bytes.length > _maxBytes) {
        return null;
      }
      final image = await _decoder(bytes, 64);
      try {
        if (!_current(source, entry)) return null;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (!_current(source, entry) ||
            data == null ||
            data.lengthInBytes > 20000) {
          return null;
        }
        if (entry.remote && entry.retain) {
          final uri = remoteUri(source)!;
          if (!_retains(uri.toString(), bytes)) return null;
          entry.sourceBytes = WeakReference(bytes);
          entry.failedBytes = null;
        }
        return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
      } finally {
        image.dispose();
      }
    } on Object {
      if (entry.remote &&
          remoteBytes != null &&
          entry.retain &&
          _current(source, entry)) {
        entry.failedBytes = WeakReference(remoteBytes);
      }
      return null;
    }
  }

  static Uri? remoteUri(String source) {
    return remoteImageUri(source);
  }

  void dispose() {
    _disposed = true;
    remoteImages?.removeListener(_remoteChanged);
    remoteImages?.dispose();
    clear();
  }

  void clear() {
    _entries.clear();
    remoteImages?.clear();
  }
}

final class _ProfileImage {
  _ProfileImage(this.expires, {required this.remote}) : retain = !remote;
  final bool remote;
  bool retain, loading = true;
  int? readEpoch;
  WeakReference<Uint8List>? sourceBytes, failedBytes;
  DateTime expires;
  String? value;
  late Future<String?> pending;
}
