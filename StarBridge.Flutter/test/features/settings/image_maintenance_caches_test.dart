import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/image_maintenance_caches.dart';
import 'package:starbridge_flutter/shared/downloadable_image_cache.dart';

class CacheOwner
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  int began = 0, ended = 0, confirmations = 0;
  bool failBegin = false, failEnd = false;
  void Function()? onBegin, onEnd;
  Future<void> receipt = Future.value();
  @override
  void beginImageMaintenance() {
    began++;
    onBegin?.call();
    if (failBegin) {
      throw StateError('begin');
    }
  }

  @override
  void endImageMaintenance() {
    ended++;
    onEnd?.call();
    if (failEnd) {
      throw StateError('end');
    }
  }

  @override
  Future<void> get imageMaintenanceSettled {
    confirmations++;
    return receipt;
  }
}

void main() {
  test('all confirmation barriers start before waiting for a held peer', () async {
    final a = CacheOwner(), b = CacheOwner();
    final first = Completer<void>(), second = Completer<void>();
    a.receipt = first.future;
    b.receipt = second.future;
    final caches = ImageMaintenanceCaches([a, b]);
    caches.beginImageMaintenance();
    caches.endImageMaintenance();
    final waiting = caches.imageMaintenanceSettled;
    await Future<void>.delayed(Duration.zero);
    final observed = (a.confirmations, b.confirmations);
    first.complete();
    second.complete();
    await waiting;
    expect(
      observed,
      (1, 1),
      reason:
          'Independent windows must not multiply their confirmation deadlines.',
    );
    caches.dispose();
  });
  test(
    'reentrant registration of an existing peer enters it only once',
    () async {
      final a = CacheOwner(), b = CacheOwner();
      final caches = ImageMaintenanceCaches([a, b]);
      a.onBegin = () => caches.attach(b);
      caches.beginImageMaintenance();
      expect(b.began, 1);
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(b.ended, 1);
      expect(b.confirmations, 1);
      caches.dispose();
    },
  );
  test(
    'late registration inherits pause and its confirmation joins the operation',
    () async {
      final a = CacheOwner(), b = CacheOwner();
      final gate = Completer<void>();
      b.receipt = gate.future;
      final caches = ImageMaintenanceCaches([a]);
      caches.beginImageMaintenance();
      final detach = caches.attach(b);
      expect(b.began, 1);
      detach();
      detach();
      expect(b.ended, 0);
      caches.endImageMaintenance();
      var done = false;
      final waiting = caches.imageMaintenanceSettled.then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(b.ended, 1);
      expect(b.confirmations, 1);
      gate.complete();
      await waiting;
      caches.beginImageMaintenance();
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(b.began, 1);
      caches.dispose();
    },
  );
  test(
    'failed entry releases all peers and a later operation can retry',
    () async {
      final a = CacheOwner()..failBegin = true, b = CacheOwner();
      final caches = ImageMaintenanceCaches([a, b]);
      expect(caches.beginImageMaintenance, throwsStateError);
      expect(b.began, 1);
      expect(caches.endImageMaintenance, throwsStateError);
      await expectLater(caches.imageMaintenanceSettled, throwsStateError);
      expect(a.ended, 1);
      expect(b.ended, 1);
      a.failBegin = false;
      caches.beginImageMaintenance();
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(a.began, 2);
      caches.dispose();
    },
  );
  test(
    'failed late entry cannot be reported as successful or remain registered',
    () async {
      final a = CacheOwner(), b = CacheOwner()..failBegin = true;
      final caches = ImageMaintenanceCaches([a]);
      caches.beginImageMaintenance();
      expect(() => caches.attach(b), throwsStateError);
      expect(caches.endImageMaintenance, throwsStateError);
      await expectLater(caches.imageMaintenanceSettled, throwsStateError);
      expect(b.ended, 1);
      caches.beginImageMaintenance();
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(b.began, 1);
      caches.dispose();
    },
  );
  test('duplicate registrations release their independent leases without early removal', () async {
    final a = CacheOwner();
    final caches = ImageMaintenanceCaches([]);
    final first = caches.attach(a), second = caches.attach(a);
    first();
    first();
    caches.beginImageMaintenance();
    second();
    caches.endImageMaintenance();
    await caches.imageMaintenanceSettled;
    expect(a.began, 1);
    expect(a.ended, 1);
    caches.beginImageMaintenance();
    caches.endImageMaintenance();
    await caches.imageMaintenanceSettled;
    expect(a.began, 1);
    caches.dispose();
  });
  test(
    'release callbacks do not pause newly registered post-purge owners',
    () async {
      final a = CacheOwner(), b = CacheOwner();
      final caches = ImageMaintenanceCaches([a]);
      a.onEnd = () => caches.attach(b);
      caches.beginImageMaintenance();
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(b.began, 0);
      expect(b.ended, 0);
      caches.beginImageMaintenance();
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(b.began, 1);
      caches.dispose();
    },
  );
  test(
    'disposing registrations still releases and confirms the entered operation',
    () async {
      final a = CacheOwner();
      final caches = ImageMaintenanceCaches([a]);
      caches.beginImageMaintenance();
      caches.dispose();
      expect(() => caches.attach(CacheOwner()), throwsStateError);
      caches.endImageMaintenance();
      await caches.imageMaintenanceSettled;
      expect(a.ended, 1);
      expect(a.confirmations, 1);
    },
  );
}
