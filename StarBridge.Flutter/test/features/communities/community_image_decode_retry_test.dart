import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import '../../app/menu_overlay/menu_chat_media_test.dart' show photo;
import '../friends/social_layout_test.dart' show app, loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'reopening an image can recover after a transient cached decode failure',
    (tester) async {
      final bytes = Uint8List.fromList(base64Decode(photo.split(',').last));
      var now = DateTime.utc(2026, 10, 17);
      final seed = (await tester.runAsync(
        () => decodeCommunityImage(bytes, 96),
      ))!;
      addTearDown(seed.dispose);
      var decodes = 0;
      Future<ui.Image> decoder(Uint8List bytes, int width) async {
        decodes++;
        if (decodes == 1) throw StateError('temporary fixture decoder failure');
        return seed.clone();
      }

      final cache = CommunityImageDecodeCache(decoder: decoder, now: () => now);
      addTearDown(cache.dispose);
      Widget scene() => app(
        SizedBox.square(
          dimension: 96,
          child: CommunityWorkspaceImage(
            bytes: bytes,
            icon: StandardIconSemantic.person,
            decoder: cache.decode,
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(decodes, 1);
      expect(find.byType(RawImage), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is StandardIcon &&
              widget.semantic == StandardIconSemantic.brokenImage,
        ),
        findsOneWidget,
        reason: 'Reopen only after the first decode has actually failed in the component.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      now = now.add(const Duration(seconds: 11));
      await tester.pumpWidget(scene());
      await tester.pump();
      expect(
        decodes,
        2,
        reason: 'A previous failed future cannot permanently pin a recoverable image.',
      );
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'decode failures coalesce briefly and retry at the bounded deadline',
    () async {
      var now = DateTime.utc(2026, 10, 17), decodes = 0;
      final bytes = Uint8List(1);
      final cache = CommunityImageDecodeCache(
        now: () => now,
        decoder: (_, _) {
          decodes++;
          return Future.error(StateError('fixture failure'));
        },
      );
      addTearDown(cache.dispose);
      await expectLater(
        Future.wait([cache.decode(bytes, 96), cache.decode(bytes, 96)]),
        throwsStateError,
      );
      expect(decodes, 1);
      now = now.add(const Duration(milliseconds: 9999));
      await expectLater(cache.decode(bytes, 96), throwsStateError);
      expect(
        decodes,
        1,
        reason: 'Repeated rebuilds must not hammer a failing decoder.',
      );
      now = now.add(const Duration(milliseconds: 1));
      await expectLater(cache.decode(bytes, 96), throwsStateError);
      expect(decodes, 2);
      await expectLater(cache.decode(bytes, 96), throwsStateError);
      expect(
        decodes,
        2,
        reason: 'A failed retry starts a new bounded backoff.',
      );
    },
  );

  test('synchronous decoder failures obey the same backoff', () async {
    var now = DateTime.utc(2026, 10, 17), decodes = 0;
    final bytes = Uint8List(1);
    final cache = CommunityImageDecodeCache(
      now: () => now,
      decoder: (_, _) {
        decodes++;
        throw StateError('synchronous fixture failure');
      },
    );
    addTearDown(cache.dispose);
    await expectLater(cache.decode(bytes, 96), throwsStateError);
    await expectLater(cache.decode(bytes, 96), throwsStateError);
    expect(decodes, 1);
    now = now.add(const Duration(seconds: 10));
    await expectLater(cache.decode(bytes, 96), throwsStateError);
    expect(decodes, 2);
  });

  test(
    'retry delay starts at failure rather than the start of a slow decode',
    () async {
      var now = DateTime.utc(2026, 10, 17), decodes = 0;
      final gate = Completer<ui.Image>(), bytes = Uint8List(1);
      final cache = CommunityImageDecodeCache(
        now: () => now,
        decoder: (_, _) {
          decodes++;
          return gate.future;
        },
      );
      addTearDown(cache.dispose);
      final failed = expectLater(cache.decode(bytes, 96), throwsStateError);
      now = now.add(const Duration(minutes: 1));
      gate.completeError(StateError('late fixture failure'));
      await failed;
      now = now.add(const Duration(milliseconds: 9999));
      await expectLater(cache.decode(bytes, 96), throwsStateError);
      expect(decodes, 1);
      now = now.add(const Duration(milliseconds: 1));
      await expectLater(cache.decode(bytes, 96), throwsStateError);
      expect(decodes, 2);
    },
  );

  test('successful frames stay reusable beyond the failure backoff', () async {
    var now = DateTime.utc(2026, 10, 17), decodes = 0;
    final bytes = Uint8List(1);
    final cache = CommunityImageDecodeCache(
      now: () => now,
      decoder: (_, _) {
        decodes++;
        return pixel();
      },
    );
    final first = await cache.decode(bytes, 96);
    now = now.add(const Duration(days: 1));
    final second = await cache.decode(bytes, 96);
    expect(decodes, 1);
    expect(first.isCloneOf(second), isTrue);
    cache.dispose();
    expect(await second.toByteData(), isNotNull);
    first.dispose();
    second.dispose();
  });

  test(
    'an evicted late failure does not poison a replacement for the same bytes',
    () async {
      var now = DateTime.utc(2026, 10, 17), decodes = 0;
      final gate = Completer<ui.Image>(), bytes = Uint8List(1);
      final cache = CommunityImageDecodeCache(
        now: () => now,
        decoder: (_, _) {
          decodes++;
          return decodes == 1 ? gate.future : pixel();
        },
      );
      addTearDown(cache.dispose);
      final failed = expectLater(cache.decode(bytes, 96), throwsStateError);
      for (var i = 0; i < 64; i++) {
        (await cache.decode(Uint8List.fromList([i]), 96)).dispose();
      }
      (await cache.decode(bytes, 96)).dispose();
      expect(decodes, 66);
      gate.completeError(StateError('evicted fixture failure'));
      await failed;
      now = now.add(const Duration(minutes: 1));
      (await cache.decode(bytes, 96)).dispose();
      expect(decodes, 66);
    },
  );

  test('expired failure cannot revive a disposed cache', () async {
    var now = DateTime.utc(2026, 10, 17), decodes = 0;
    final bytes = Uint8List(1);
    final cache = CommunityImageDecodeCache(
      now: () => now,
      decoder: (_, _) {
        decodes++;
        return Future.error(StateError('fixture failure'));
      },
    );
    await expectLater(cache.decode(bytes, 96), throwsStateError);
    cache.dispose();
    now = now.add(const Duration(days: 1));
    await expectLater(cache.decode(bytes, 96), throwsStateError);
    expect(decodes, 1);
  });
}

Future<ui.Image> pixel() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}
