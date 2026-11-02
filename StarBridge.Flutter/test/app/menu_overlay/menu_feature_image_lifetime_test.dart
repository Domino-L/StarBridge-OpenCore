import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_feature_lease.dart';
import 'package:starbridge_flutter/platform/window/menu_feature_sessions.dart';
import 'package:starbridge_flutter/shared/downloadable_image_cache.dart';

class ImageLease implements MenuFeatureLease, DownloadableImageCache {
  int begins = 0, ends = 0, disposals = 0;
  bool failBegin = false, failEnd = false;
  void Function()? onEnd;
  @override
  void beginImageMaintenance() {
    begins++;
    if (failBegin) throw StateError('Fixture begin');
  }

  @override
  void endImageMaintenance() {
    ends++;
    onEnd?.call();
    if (failEnd) throw StateError('Fixture end');
  }

  @override
  void show(bool visible) {}
  @override
  void act(String key, String value) {}
  @override
  void dispose() {
    disposals++;
  }
}

void main() {
  for (final beginning in [true, false]) {
    test(
      'one ${beginning ? 'begin' : 'release'} failure cannot leave peer sessions unvisited or later owners paused',
      () {
        final first = ImageLease(), second = ImageLease(), third = ImageLease();
        final owners = MenuFeatureSessions({
          'a': (_) => first,
          'b': (_) => second,
          'c': (_) => third,
        }, (_) {});
        try {
          owners.obtain('a');
          owners.obtain('b');
          first.failBegin = beginning;
          first.failEnd = !beginning;
          if (beginning) {
            expect(owners.beginImageMaintenance, throwsStateError);
          } else {
            owners.beginImageMaintenance();
          }
          expect(second.begins, 1);
          if (beginning) {
            owners.endImageMaintenance();
          } else {
            expect(owners.endImageMaintenance, throwsStateError);
          }
          expect(second.ends, 1);
          owners.obtain('c');
          expect(third.begins, 0);
        } finally {
          owners.dispose();
        }
      },
    );
  }
  test('a session created during release observes the completed phase', () {
    final first = ImageLease(), late = ImageLease();
    final owners = MenuFeatureSessions({
      'a': (_) => first,
      'late': (_) => late,
    }, (_) {});
    try {
      owners.obtain('a');
      owners.beginImageMaintenance();
      first.onEnd = () => owners.obtain('late');
      owners.endImageMaintenance();
      expect(late.begins, 0);
    } finally {
      owners.dispose();
    }
  });
  test('failed admission of a new paused owner disposes it and never retains an unreachable session', () {
    final lease = ImageLease()..failBegin = true;
    final owners = MenuFeatureSessions({'a': (_) => lease}, (_) {});
    try {
      owners.beginImageMaintenance();
      expect(() => owners.obtain('a'), throwsStateError);
      expect(lease.disposals, 1);
      expect(owners.current, isEmpty);
      owners.endImageMaintenance();
    } finally {
      owners.dispose();
    }
  });
}
