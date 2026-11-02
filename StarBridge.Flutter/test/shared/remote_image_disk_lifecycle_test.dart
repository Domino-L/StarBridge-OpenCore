import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image_disk_cache.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../app/menu_overlay/menu_profile_images_test.dart' show ImageClient;
import '../support/remote_image_fixture.dart';

const source = 'https://images.example.test/fixture.png';
final bytes = Uint8List.fromList([1, 2, 3]);

class _Lease implements RemoteImageDiskLease {
  _Lease(this.snapshot);
  @override
  final RemoteImageDiskSnapshot? snapshot;
  final storing = Completer<void>(), release = Completer<void>();
  int closes = 0;
  @override
  Future<void> store(RemoteImageDiskSnapshot value) async {
    storing.complete();
    await release.future;
  }

  @override
  Future<void> reject() async {}
  @override
  Future<void> close() async {
    closes++;
  }
}

class _Disk implements RemoteImageDiskCache {
  _Disk(this.lease, {this.avatar});
  final _Lease lease;
  final _Lease? avatar;
  Completer<void>? blocked;
  int opens = 0;
  @override
  Future<RemoteImageDiskLease?> open(
    String source, {
    required int maxBytes,
    required bool followRedirects,
    required RemoteImageResourceKind kind,
  }) async {
    opens++;
    await blocked?.future;
    return kind == RemoteImageResourceKind.avatar ? avatar ?? lease : lease;
  }
}

RemoteImageDiskSnapshot snapshot({
  bool noCache = false,
  bool mustRevalidate = false,
  bool expired = false,
}) {
  final now = DateTime.now().toUtc();
  return RemoteImageDiskSnapshot(
    bytes: bytes,
    storedAt: now.subtract(Duration(seconds: expired ? 301 : 30)),
    freshUntil: now.add(Duration(seconds: expired ? -1 : 30)),
    maxAgeSeconds: 300,
    noCache: noCache,
    mustRevalidate: mustRevalidate,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'retirement waits for an admitted disk read and rejects its late bytes',
    () async {
      final mode = ImageMode(),
          disk = _Disk(_Lease(snapshot()))..blocked = Completer<void>();
      final loader = RemoteImageLoader(mode: mode, diskCache: disk);
      final reading = loader.load(source);
      var retired = false;
      final retiring = loader.retireAsync().then((_) => retired = true);
      await Future<void>.delayed(Duration.zero);
      expect(retired, isFalse);
      disk.blocked!.complete();
      expect(await reading, isNull);
      await retiring;
      expect(disk.lease.closes, 1);
      loader.dispose();
      mode.dispose();
    },
  );

  test(
    'accepted publication does not delay paint; retirement joins it',
    () async {
      final mode = ImageMode(), lease = _Lease(null);
      final client = ImageClient()..bytes.complete(bytes);
      final loader = RemoteImageLoader(
        mode: mode,
        diskCache: _Disk(lease),
        createClient: () => client,
      );
      expect(await loader.load(source), bytes);
      await lease.storing.future;
      var retired = false;
      final retiring = loader.retireAsync().then((_) => retired = true);
      await Future<void>.delayed(Duration.zero);
      expect(retired, isFalse);
      lease.release.complete();
      await retiring;
      expect(lease.closes, 1);
      loader.dispose();
      mode.dispose();
    },
  );

  test(
    'maintenance drains eligible publication and preserves an excluded avatar',
    () async {
      final mode = ImageMode(), lease = _Lease(null);
      final client = ImageClient()..bytes.complete(bytes);
      final loader = RemoteImageLoader(
        mode: mode,
        diskCache: _Disk(lease, avatar: _Lease(snapshot())),
        createClient: () => client,
      );
      expect(
        await loader.load(source, kind: RemoteImageResourceKind.avatar),
        bytes,
      );
      expect(
        await loader.load(source, kind: RemoteImageResourceKind.ship),
        bytes,
      );
      await lease.storing.future;
      loader.beginImageMaintenance();
      expect(loader.cached(source, kind: RemoteImageResourceKind.ship), isNull);
      expect(
        loader.cached(source, kind: RemoteImageResourceKind.avatar),
        bytes,
      );
      final child = loader.fork();
      expect(
        await child.load(source, kind: RemoteImageResourceKind.organization),
        isNull,
      );
      var settled = false;
      final settling = loader.imageMaintenanceSettled.then(
        (_) => settled = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      lease.release.complete();
      await settling;
      loader.endImageMaintenance();
      await loader.retireAsync();
      loader.dispose();
      mode.dispose();
    },
  );

  for (final rule in [
    'no-cache',
    'expired-must-revalidate',
    'ordinary-stale',
  ]) {
    test('offline disk display respects $rule without HTTP', () async {
      final mode = ImageMode()..state = ConnectionModeState.offline;
      final disk = _Disk(
        _Lease(
          snapshot(
            noCache: rule == 'no-cache',
            mustRevalidate: rule == 'expired-must-revalidate',
            expired: true,
          ),
        ),
      );
      var network = 0;
      final loader = RemoteImageLoader(
        mode: mode,
        diskCache: disk,
        createClient: () {
          network++;
          return ImageClient();
        },
      );
      expect(
        await loader.load(source),
        rule == 'ordinary-stale' ? bytes : isNull,
      );
      expect(network, 0);
      expect(disk.opens, 1);
      await loader.retireAsync();
      loader.dispose();
      mode.dispose();
    });
  }
}
