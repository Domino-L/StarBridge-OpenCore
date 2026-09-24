import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/embedded_avatar.dart';

const photo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  testWidgets(
    'unchanged avatar reuses its decoded image across parent updates',
    (tester) async {
      Widget build() => MaterialApp(
        home: SizedBox(
          width: 40,
          height: 40,
          child: EmbeddedAvatar(
            source: photo,
            fallback: const Text('fallback'),
          ),
        ),
      );
      await tester.pumpWidget(build());
      final first = tester.widget<Image>(find.byType(Image)).image;
      await tester.pumpWidget(build());
      final second = tester.widget<Image>(find.byType(Image)).image;
      expect(first, isA<ResizeImage>());
      expect(second, isA<ResizeImage>());
      expect(
        (second as ResizeImage).imageProvider,
        same((first as ResizeImage).imageProvider),
      );
      expect(
        await second.obtainKey(ImageConfiguration.empty),
        await first.obtainKey(ImageConfiguration.empty),
      );
    },
  );
  testWidgets(
    'WPF-sized account photo is not rejected by the smaller room budget',
    (tester) async {
      final bytes = List<int>.filled(300000, 0);
      final original = base64Decode(photo.split(',').last);
      bytes.setRange(0, original.length, original);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 40,
            height: 40,
            child: EmbeddedAvatar(
              source: 'data:image/png;base64,${base64Encode(bytes)}',
              fallback: const Text('fallback'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(find.byType(Image)).image,
          tester.element(find.byType(Image)),
        ),
      );
      await tester.pump();
      expect(find.text('fallback'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  Widget avatar(String? source) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 40,
        height: 40,
        child: EmbeddedAvatar(source: source, fallback: const Text('fallback')),
      ),
    ),
  );

  testWidgets(
    'uses the original embedded photo and clears it on account removal',
    (tester) async {
      await tester.pumpWidget(avatar(photo));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      await tester.runAsync(
        () => precacheImage(image.image, tester.element(find.byType(Image))),
      );
      await tester.pump();
      expect(image.image, isA<ResizeImage>());
      final original = (image.image as ResizeImage).imageProvider;
      expect(original, isA<MemoryImage>());
      expect(
        (original as MemoryImage).bytes,
        base64Decode(photo.split(',').last),
      );
      expect(find.text('fallback'), findsNothing);
      await tester.pumpWidget(avatar(null));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final source in [
    null,
    '',
    'https://example.invalid/photo.png',
    'C:/private/photo.png',
    'data:image/svg+xml;base64,PHN2Zz4=',
    'data:image/png;base64,%%%',
    'data:image/png;base64,${'a' * (704 * 1024)}',
  ]) {
    testWidgets('rejects unsupported or oversized source ${source?.length}', (
      tester,
    ) async {
      await tester.pumpWidget(avatar(source));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
