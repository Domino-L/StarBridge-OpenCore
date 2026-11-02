// Original server policy must survive persistence independently of the local
// five-minute freshness cap. No production account or live HTTP is used here.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/remote_image_disk_cache.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../app/menu_overlay/menu_profile_images_test.dart'
    show ImageClient, ImageRequest, ImageResponse;
import '../support/remote_image_fixture.dart';

class _Headers extends Fake implements HttpHeaders {
  @override
  List<String>? operator [](String name) => switch (name) {
    HttpHeaders.cacheControlHeader => ['max-age=3600'],
    HttpHeaders.ageHeader => ['400'],
    _ => null,
  };
}

class _Response extends ImageResponse {
  _Response() : super([1, 2, 3], 200, 3);
  @override
  HttpHeaders get headers => _Headers();
}

class _Request extends ImageRequest {
  _Request() : super(Future.value([1, 2, 3]), 200, 3);
  @override
  Future<HttpClientResponse> close() async => _Response();
}

class _Client extends ImageClient {
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    reads++;
    return _Request();
  }
}

class _Lease implements RemoteImageDiskLease {
  RemoteImageDiskSnapshot? stored;
  @override
  RemoteImageDiskSnapshot? get snapshot => null;
  @override
  Future<void> store(RemoteImageDiskSnapshot value) async { stored = value; }
  @override
  Future<void> reject() async {}
  @override
  Future<void> close() async {}
}

class _Disk implements RemoteImageDiskCache {
  final lease = _Lease();
  @override
  Future<RemoteImageDiskLease?> open(String source, {required int maxBytes,
      required bool followRedirects, required RemoteImageResourceKind kind}) async => lease;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('disk metadata preserves original max-age while local freshness stays capped', () async {
    final mode = ImageMode(), disk = _Disk(), client = _Client();
    final loader = RemoteImageLoader(mode: mode, diskCache: disk, createClient: () => client);
    try {
      expect(await loader.load('https://images.example.test/long-lived.png'), Uint8List.fromList([1, 2, 3]));
      await loader.retireAsync();
      final stored = disk.lease.stored;
      expect(stored, isNotNull);
      expect(client.reads, 1);
      expect(stored!.freshUntil.difference(stored.storedAt), const Duration(seconds: 300),
        reason: 'The local retention cap applies to freshness, not server policy metadata');
      expect(stored.maxAgeSeconds, 3600,
        reason: 'A later 304 with Age=400 and no Cache-Control must inherit the original 3600, not become immediately stale');
    } finally { await loader.retireAsync(); loader.dispose(); mode.dispose(); }
  });
}
