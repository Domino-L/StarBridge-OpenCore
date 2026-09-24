import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../features/communities/community_image_decoder.dart';

/// Window-local media cache. Only bounded PNG thumbnails leave the primary
/// engine; no cookies, account credentials or remote URLs reach the renderer.
final class MenuProfileImages {
  MenuProfileImages({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  static const _maxBytes = 512 * 1024;
  final _entries = <String, _ProfileImage>{};
  HttpClient? _client;
  bool _disposed = false;

  String? cached(String? source) {
    final entry = _entries[source];
    // Callers only request media still present in a newly authorized profile.
    // Expiry schedules revalidation; it must not clear the displayed thumbnail.
    return !_disposed ? entry?.value : null;
  }

  Future<String?> load(String? source) {
    if (_disposed || source == null || source.length > 699120) {
      return Future.value(null);
    }
    final previous = _entries[source];
    if (previous != null && _now().isBefore(previous.expires)) {
      return previous.pending;
    }
    if (_entries.length >= 32) _entries.remove(_entries.keys.first);
    final entry = _ProfileImage(_now().add(const Duration(seconds: 10)));
    entry.value = previous?.value;
    _entries[source] = entry;
    entry.pending = _load(source).then((value) {
      if (_disposed || !identical(_entries[source], entry)) return null;
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

  Future<String?> _load(String source) async {
    try {
      final Uint8List bytes;
      if (RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,')
          .hasMatch(source)) {
        bytes = base64Decode(source.substring(source.indexOf(',') + 1));
      } else {
        final uri = remoteUri(source);
        if (uri == null) return null;
        bytes = await _download(uri);
      }
      if (_disposed || bytes.isEmpty || bytes.length > _maxBytes) return null;
      final image = await decodeCommunityImage(bytes, 64);
      try {
        if (_disposed) return null;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (_disposed || data == null || data.lengthInBytes > 20000) {
          return null;
        }
        return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
      } finally {
        image.dispose();
      }
    } on Object {
      return null;
    }
  }

  static Uri? remoteUri(String source) {
    if (source.length > 2048) return null;
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasFragment) {
      return null;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (!host.contains('.') ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return null;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      final b = address.rawAddress;
      if (address.type != InternetAddressType.IPv4 ||
          b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          b[0] == 169 && b[1] == 254 ||
          b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
          b[0] == 192 && b[1] == 168) {
        return null;
      }
    }
    return uri;
  }

  Future<Uint8List> _download(Uri uri) async {
    HttpClientRequest? request;
    var canceled = false;
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    Future<Uint8List> read() async {
      request = await client.getUrl(uri);
      if (_disposed || canceled) {
        request!.abort();
        throw StateError('closed');
      }
      request!.followRedirects = false;
      final response = await request!.close();
      if (response.statusCode != 200 || response.contentLength > _maxBytes) {
        throw const FormatException('Image response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (_disposed || bytes.length + chunk.length > _maxBytes) {
          throw const FormatException('Image size');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      return await read().timeout(const Duration(seconds: 5));
    } on Object {
      canceled = true;
      request?.abort();
      rethrow;
    }
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void clear() {
    _entries.clear();
    _client?.close(force: true);
    _client = null;
  }
}

final class _ProfileImage {
  _ProfileImage(this.expires);
  DateTime expires;
  String? value;
  late Future<String?> pending;
}
