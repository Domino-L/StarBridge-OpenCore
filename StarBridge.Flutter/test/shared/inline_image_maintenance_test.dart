import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/shared/inline_image_cache.dart';

import '../design_system/interaction/interaction_batch3do_test.dart'
    show scopedApp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const logo = 'data:image/png;base64,AQID',
      portrait = 'data:image/png;base64,BAUG';
  test('only exclusively downloaded bytes are retired, preserved owners remain reusable', () {
    final cache = InlineImageCache();
    final admission = Object();
    final old = cache.resolve(logo, downloadedBy: admission);
    final kept = cache.resolve(portrait);
    cache.beginImageMaintenance();
    expect(cache.resolve(logo, downloadedBy: admission), isNull);
    expect(cache.resolve(portrait), same(kept));
    cache.endImageMaintenance();
    expect(cache.resolve(logo, downloadedBy: admission), isNull);
    expect(cache.resolve(logo, downloadedBy: Object()), isNot(same(old)));
    expect(
      cache.resolve(logo, downloadedBy: admission),
      isNull,
      reason:
          'An old snapshot cannot borrow pixels admitted by a later reader.',
    );
    expect(cache.resolve(portrait), same(kept));
    cache.dispose();
  });
  test(
    'shared content remains preserved without inventing a second buffer',
    () {
      final cache = InlineImageCache();
      final admission = Object();
      final first = cache.resolve(logo, downloadedBy: admission);
      expect(cache.resolve(logo), same(first));
      cache.beginImageMaintenance();
      expect(cache.resolve(logo, downloadedBy: admission), isNull);
      expect(cache.resolve(logo), same(first));
      cache.endImageMaintenance();
      expect(cache.resolve(logo, downloadedBy: admission), isNull);
      expect(cache.resolve(logo, downloadedBy: Object()), same(first));
      cache.clear();
      expect(cache.resolve(logo), isNot(same(first)));
      cache.dispose();
    },
  );
  test(
    'overlapping composition purges cannot release the next pause early',
    () {
      final cache = InlineImageCache();
      final admission = Object();
      cache.beginImageMaintenance();
      cache.beginImageMaintenance();
      cache.endImageMaintenance();
      expect(cache.resolve(logo, downloadedBy: admission), isNull);
      expect(cache.resolve(portrait), isNotNull);
      cache.endImageMaintenance();
      expect(cache.resolve(logo, downloadedBy: admission), isNull);
      expect(cache.resolve(logo, downloadedBy: Object()), isNotNull);
      cache.dispose();
    },
  );
  testWidgets(
    'an unavailable retirement frame is bounded rather than a false success',
    (t) async {
      final cache = InlineImageCache();
      cache.beginImageMaintenance();
      cache.endImageMaintenance();
      final failure = expectLater(
        cache.imageMaintenanceSettled,
        throwsA(isA<TimeoutException>()),
      );
      await t.pump(const Duration(seconds: 4));
      await failure;
      cache.dispose();
    },
  );
  test(
    'unqualified primitive labels cannot stand in for a source snapshot',
    () {
      final cache = InlineImageCache();
      for (final label in <Object>['source', 1, true]) {
        expect(cache.resolve(logo, downloadedBy: label), isNull);
      }
      expect(cache.resolve(logo), isNotNull);
      cache.dispose();
    },
  );
  testWidgets(
    'standalone logo retires actual providers on null and dispose without a root scope',
    (t) async {
      final source = await t.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 3, 3),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(3, 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
      });
      Future<Object> mountedKey() async {
        final finder = find.byType(Image);
        final provider = t.widget<Image>(finder).image;
        final key = await provider.obtainKey(
          createLocalImageConfiguration(t.element(finder)),
        );
        for (
          var i = 0;
          i < 60 && !t.binding.imageCache.statusForKey(key).keepAlive;
          i++
        ) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump();
        }
        expect(t.binding.imageCache.statusForKey(key).keepAlive, isTrue);
        return key;
      }

      var admission = Object();
      Widget scene(String? data) => scopedApp(
        CommunityLogo(data: data, downloadedBy: admission),
        InteractionSuite.values.first,
      );
      expect(source, isNotNull);
      await t.pumpWidget(scene(source));
      await t.pump();
      final first = await mountedKey();
      admission = Object();
      await t.pumpWidget(scene(source));
      await t.pump();
      expect(
        await mountedKey(),
        first,
        reason: 'Fresh metadata with identical bytes must reuse the decoder.',
      );
      await t.pumpWidget(scene(null));
      await t.pump();
      expect(t.binding.imageCache.statusForKey(first).keepAlive, isFalse);
      expect(find.byType(Image), findsNothing);
      admission = Object();
      await t.pumpWidget(scene(source));
      await t.pump();
      final next = await mountedKey();
      expect(next, isNot(first));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      expect(t.binding.imageCache.statusForKey(next).keepAlive, isFalse);
    },
  );
}
