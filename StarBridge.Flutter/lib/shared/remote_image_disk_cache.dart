import 'dart:typed_data';

enum RemoteImageResourceKind { avatar, ship, organization, other }

/// Host-owned resources. A receipt never grants access to an image URL.
abstract interface class RemoteImageDiskCache {
  Future<RemoteImageDiskLease?> open(
    String source, {
    required int maxBytes,
    required bool followRedirects,
    required RemoteImageResourceKind kind,
  });
}

abstract interface class RemoteImageDiskLease {
  RemoteImageDiskSnapshot? get snapshot;
  Future<void> store(RemoteImageDiskSnapshot value);
  Future<void> reject();
  Future<void> close();
}

/// Original HTTP max-age is stored losslessly up to one year so a later 304
/// without Cache-Control inherits it. Local freshness stays capped separately
/// (freshUntil <= storedAt + 5 minutes).
const remoteImageMaxStoredAgeSeconds = 31536000;

final class RemoteImageDiskSnapshot {
  const RemoteImageDiskSnapshot({
    required this.bytes,
    required this.storedAt,
    required this.freshUntil,
    required this.maxAgeSeconds,
    required this.noCache,
    required this.mustRevalidate,
    this.etag,
    this.validatorTarget,
  });
  final Uint8List bytes;
  final DateTime storedAt, freshUntil;
  final int maxAgeSeconds;
  final bool noCache, mustRevalidate;
  final String? etag, validatorTarget;
}
