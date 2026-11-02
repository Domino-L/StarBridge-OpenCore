import 'dart:io';
import 'dart:typed_data';

import 'remote_image_disk_cache.dart';

// Store only bounded validators, never arbitrary response headers or URLs from
// redirect destinations. This metadata has the original entry's exact key and
// account/window/mode retirement lifetime.
String? imageEtag(HttpHeaders headers) {
  final raw = singleImageHeader(headers, HttpHeaders.etagHeader, 1024);
  if (raw == null) return null;
  final value = raw.trim();
  return RegExp(r'^(?:W/)?"[\x21\x23-\x7E\x80-\xFF]*"$').hasMatch(value)
      ? value
      : null;
}

String? singleImageHeader(HttpHeaders headers, String name, int limit) {
  final values = headers[name];
  if (values == null || values.length != 1 || values.single.length > limit) {
    return null;
  }
  return values.single;
}

String opaqueImageEtag(String value) =>
    value.startsWith('W/') ? value.substring(2) : value;

final class RemoteImageCachePolicy {
  const RemoteImageCachePolicy({
    this.retain = true,
    this.maxAgeSeconds = 300,
    this.noCache = false,
    this.mustRevalidate = false,
  });
  final bool retain, noCache, mustRevalidate;
  final int maxAgeSeconds;
  bool get requiresValidation => noCache || mustRevalidate;

  RemoteImageCachePolicy restrict(RemoteImageCachePolicy? other) {
    if (other == null) return this;
    return RemoteImageCachePolicy(
      retain: retain && other.retain,
      noCache: noCache || other.noCache,
      mustRevalidate: mustRevalidate || other.mustRevalidate,
      maxAgeSeconds: maxAgeSeconds < other.maxAgeSeconds
          ? maxAgeSeconds
          : other.maxAgeSeconds,
    );
  }

  static RemoteImageCachePolicy read(
    HttpHeaders headers, {
    RemoteImageCachePolicy? previous,
  }) {
    final values = headers[HttpHeaders.cacheControlHeader];
    if (values == null) return previous ?? const RemoteImageCachePolicy();
    var retain = true, noCache = false, mustRevalidate = false, maxAge = 300;
    for (final raw in values) {
      if (raw.length > 4096) return const RemoteImageCachePolicy(retain: false);
      for (final part in raw.split(',')) {
        final fields = part.split('=');
        final name = fields.first.trim().toLowerCase();
        if (name == 'no-store') retain = false;
        if (name == 'no-cache') noCache = true;
        if (name == 'must-revalidate') mustRevalidate = true;
        if (name == 'max-age') {
          var argument = fields.length == 2 ? fields[1].trim() : '';
          if (argument.length >= 2 &&
              argument.startsWith('"') &&
              argument.endsWith('"')) {
            argument = argument.substring(1, argument.length - 1);
          }
          final number = RegExp(r'^[0-9]+$').hasMatch(argument)
              ? int.tryParse(argument)
              : null;
          maxAge = number != null && number >= 0 ? number : 0;
        }
      }
    }
    return RemoteImageCachePolicy(
      retain: retain,
      maxAgeSeconds: maxAge,
      noCache: noCache,
      mustRevalidate: mustRevalidate,
    );
  }

  Duration freshness(HttpHeaders headers) {
    final rawAge = singleImageHeader(headers, HttpHeaders.ageHeader, 64);
    final age = rawAge != null && RegExp(r'^[0-9]+$').hasMatch(rawAge)
        ? int.tryParse(rawAge)
        : null;
    if (headers[HttpHeaders.ageHeader] != null && age == null) {
      return Duration.zero;
    }
    final remaining = maxAgeSeconds - (age ?? 0);
    return Duration(seconds: noCache ? 0 : remaining.clamp(0, 300).toInt());
  }
}

final class RemoteImageFetch {
  // Revisit aliases on each read; unchanged final bodies still use their ETag.
  // Do not cache a redirect's authorization or target selection.
  RemoteImageFetch(
    this.bytes,
    this.etag,
    this.policy,
    HttpHeaders headers, {
    required this.validatorTarget,
    bool redirected = false,
  }) : isDenied = false,
       fromDisk = false,
       freshness = redirected ? Duration.zero : policy.freshness(headers);
  RemoteImageFetch.denied(
    this.policy,
    HttpHeaders headers, {
    bool redirected = false,
  }) : bytes = null,
       fromDisk = false,
       etag = null,
       isDenied = true,
       validatorTarget = null,
       freshness = redirected ? Duration.zero : policy.freshness(headers);
  RemoteImageFetch.disk(RemoteImageDiskSnapshot value, DateTime now)
    : bytes = value.bytes,
      etag = value.etag,
      validatorTarget = value.validatorTarget,
      isDenied = false,
      fromDisk = true,
      freshness = value.freshUntil.difference(now).isNegative
          ? Duration.zero
          : value.freshUntil.difference(now),
      policy = RemoteImageCachePolicy(
        maxAgeSeconds: value.maxAgeSeconds,
        noCache: value.noCache,
        mustRevalidate: value.mustRevalidate,
      );
  final Uint8List? bytes;
  final String? etag;
  final String? validatorTarget;
  final bool isDenied;
  final bool fromDisk;
  final RemoteImageCachePolicy policy;
  final Duration freshness;
}
