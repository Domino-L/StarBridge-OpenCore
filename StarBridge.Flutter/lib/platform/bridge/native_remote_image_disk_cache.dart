import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../shared/diagnostics/loading_metrics.dart';
import '../../shared/remote_image_disk_cache.dart';
import 'bridge_client_session.dart';

/// No paths, URLs or renderer account identifiers cross the resource bridge.
final class NativeRemoteImageDiskCache implements RemoteImageDiskCache {
  NativeRemoteImageDiskCache(this.session);

  /// The disk cache for a native host session; none without a host.
  static NativeRemoteImageDiskCache? forSession(BridgeClientSession? session) =>
      session == null ? null : NativeRemoteImageDiskCache(session);
  final BridgeClientSession session;
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  int _writeBytes = 0;

  Future<T?> _bounded<T>(Future<T?> Function() action) async {
    if (_active >= 4) {
      if (_waiting.length >= 64) return null;
      final admitted = Completer<void>();
      _waiting.add(admitted);
      await admitted.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } on Object {
      return null;
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }

  Future<Map<String, Object?>?> _send(
    String name,
    int generation,
    Map<String, Object?> payload,
  ) async {
    if (session.isClosed ||
        session.activeGeneration != generation ||
        !session.hostCapabilities.contains('imageCache.resources.v1')) {
      return null;
    }
    final metrics = LoadingMetrics.current;
    final response = await (metrics == null
        ? session.request(
            'imageCache.$name',
            payload: {'schemaVersion': 1, ...payload},
          )
        : metrics.background(
            () => session.request(
              'imageCache.$name',
              payload: {'schemaVersion': 1, ...payload},
            ),
          ));
    if (session.isClosed ||
        session.activeGeneration != generation ||
        response.status != 'ok' ||
        response.payload['schemaVersion'] != 1) {
      return null;
    }
    return response.payload;
  }

  @override
  Future<RemoteImageDiskLease?> open(
    String source, {
    required int maxBytes,
    required bool followRedirects,
    required RemoteImageResourceKind kind,
  }) => _bounded(() async {
    if (maxBytes <= 0 || maxBytes > 4 * 1024 * 1024) return null;
    final generation = session.activeGeneration;
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([source, maxBytes, followRedirects, kind.name]),
          ),
        )
        .toString();
    final body = await _send('open', generation, {
      'key': key,
      'kind': kind.name,
    });
    final token = body?['cacheToken'];
    if (body == null ||
        token is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      return null;
    }
    final lease = _NativeImageLease(this, generation, token);
    try {
      if (body['status'] == 'miss') return lease;
      final length = body['length'];
      if (body['status'] != 'ready' ||
          length is! int ||
          length <= 0 ||
          length > maxBytes) {
        return null;
      }
      final bytes = Uint8List(length);
      var offset = 0;
      while (offset < length) {
        final chunk = await _send('read', generation, {
          'cacheToken': token,
          'offset': offset,
        });
        if (chunk == null ||
            chunk['offset'] != offset ||
            chunk['cacheToken'] != token) {
          return null;
        }
        final decoded = base64Decode(chunk['chunk'] as String);
        final count = decoded.length;
        if (count <= 0 ||
            count > 256 * 1024 ||
            count > length - offset ||
            chunk['nextOffset'] != offset + count ||
            chunk['done'] != (offset + count == length)) {
          return null;
        }
        bytes.setRange(offset, offset + count, decoded);
        offset += count;
      }
      if (sha256.convert(bytes).toString() != body['sha256']) return null;
      final maxAge = body['maxAgeSeconds'] as int;
      final storedAt = DateTime.fromMillisecondsSinceEpoch(
        body['storedAtMs'] as int,
        isUtc: true,
      );
      final freshUntil = DateTime.fromMillisecondsSinceEpoch(
        body['freshUntilMs'] as int,
        isUtc: true,
      );
      if (maxAge < 0 ||
          maxAge > remoteImageMaxStoredAgeSeconds ||
          freshUntil.isBefore(storedAt) ||
          freshUntil.difference(storedAt) > const Duration(seconds: 300)) {
        return null;
      }
      lease._snapshot = RemoteImageDiskSnapshot(
        bytes: bytes,
        storedAt: storedAt,
        freshUntil: freshUntil,
        maxAgeSeconds: maxAge,
        noCache: body['noCache'] as bool,
        mustRevalidate: body['mustRevalidate'] as bool,
        etag: body['etag'] as String?,
        validatorTarget: body['validatorTarget'] as String?,
      );
      return lease;
    } finally {
      if (lease.snapshot == null && body['status'] != 'miss') {
        await lease.close();
      }
    }
  });
}

final class _NativeImageLease implements RemoteImageDiskLease {
  _NativeImageLease(this.owner, this.generation, this.token);
  final NativeRemoteImageDiskCache owner;
  final int generation;
  final String token;
  RemoteImageDiskSnapshot? _snapshot;
  bool _closed = false;
  @override
  RemoteImageDiskSnapshot? get snapshot => _snapshot;

  @override
  Future<void> store(RemoteImageDiskSnapshot value) async {
    if (_closed) return;
    final length = value.bytes.length;
    if (length <= 0 ||
        length > 4 * 1024 * 1024 ||
        owner._writeBytes + length > 16 * 1024 * 1024) {
      await close();
      return;
    }
    owner._writeBytes += length;
    try {
      await owner._bounded<Object>(() async {
        if (_closed ||
            value.bytes.isEmpty ||
            value.bytes.length > 4 * 1024 * 1024) {
          return null;
        }
        var response = await owner._send('beginWrite', generation, {
          'cacheToken': token,
          'length': value.bytes.length,
          'sha256': sha256.convert(value.bytes).toString(),
          'storedAtMs': value.storedAt.millisecondsSinceEpoch,
          'freshUntilMs': value.freshUntil.millisecondsSinceEpoch,
          'maxAgeSeconds': value.maxAgeSeconds,
          'noCache': value.noCache,
          'mustRevalidate': value.mustRevalidate,
          'etag': value.etag,
          'validatorTarget': value.validatorTarget,
        });
        if (response?['status'] != 'writing' || response?['nextOffset'] != 0) {
          return null;
        }
        for (var offset = 0; offset < value.bytes.length;) {
          final end = (offset + 256 * 1024)
              .clamp(0, value.bytes.length)
              .toInt();
          response = await owner._send('append', generation, {
            'cacheToken': token,
            'offset': offset,
            'chunk': base64Encode(
              Uint8List.sublistView(value.bytes, offset, end),
            ),
          });
          if (response?['status'] != 'writing' ||
              response?['nextOffset'] != end) {
            return null;
          }
          offset = end;
        }
        await owner._send('commit', generation, {'cacheToken': token});
        return null;
      });
    } finally {
      owner._writeBytes -= length;
      await close();
    }
  }

  @override
  Future<void> reject() async {
    if (_closed) return;
    try {
      await owner._bounded<Object>(
        () async => owner._send('reject', generation, {'cacheToken': token}),
      );
    } finally {
      await close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _snapshot = null;
    try {
      await owner._send('close', generation, {'cacheToken': token});
    } on Object {
      /* Original Host receipt expiry is the final cleanup bound. */
    }
  }
}
