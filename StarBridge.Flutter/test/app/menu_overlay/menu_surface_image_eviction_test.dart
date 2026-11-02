import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_inline_avatar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_features.dart';

import 'dart:convert';

void main() {
  testWidgets(
    'retirement evicts organization decoder and provider while retaining member portrait',
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
      final features = {
        'organizations': MenuFeatureView(
          'ready',
          rows: [
            (
              title: 'Member',
              selected: false,
              detail: '',
              avatar: source,
              buttons: const <MenuFeatureButton>[],
            ),
          ],
          organization: MenuOrganizationView(
            tab: 'members',
            code: '',
            description: '',
            query: '',
            total: 1,
            matched: 1,
            offset: 0,
            rows: const [],
            logo: source,
          ),
        ),
      };
      late StateSetter redraw;
      final surface = MenuSurfaceFeatures(
        features: features,
        revisions: {},
        visible: {},
        timers: {},
        opening: () => 1,
        wanted: () => true,
        enabled: () => true,
        update: (action) => redraw(action),
      );
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              redraw = setState;
              return Row(
                children: [
                  MenuInlineAvatar(
                    key: const ValueKey('logo'),
                    source: features['organizations']!.organization!.logo,
                  ),
                  MenuInlineAvatar(
                    key: const ValueKey('portrait'),
                    source: features['organizations']!.rows.single.avatar,
                  ),
                ],
              );
            },
          ),
        ),
      );
      final imageWidgets = t.widgetList<Image>(find.byType(Image)).toList();
      expect(imageWidgets, hasLength(2));
      final config = createLocalImageConfiguration(t.element(find.byType(Row)));
      final keys = [
        for (final image in imageWidgets) await image.image.obtainKey(config),
      ];
      // Wait for actual codec completion, not just the widget's source property.
      for (
        var i = 0;
        i < 40 &&
            t
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image == null);
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      final before = t.widgetList<RawImage>(find.byType(RawImage)).toList();
      expect(before, hasLength(2));
      expect(before.every((image) => image.image != null), isTrue);
      expect(t.binding.imageCache.statusForKey(keys[0]).live, isTrue);
      expect(t.binding.imageCache.statusForKey(keys[1]).live, isTrue);
      final receipt = surface.retire({'schemaVersion': 1, 'resourceEpoch': 1});
      expect(receipt['resourceEpoch'], 1);
      await t.pump();
      await t.pump();
      expect(t.binding.imageCache.statusForKey(keys[0]).live, isFalse);
      expect(t.binding.imageCache.statusForKey(keys[0]).keepAlive, isFalse);
      expect(t.binding.imageCache.statusForKey(keys[1]).live, isTrue);
      expect(
        t.widgetList<RawImage>(find.byType(RawImage)).single.image,
        isNotNull,
      );
      expect(features['organizations']!.rows.single.avatar, source);
      expect(
        () => surface.retire({
          'schemaVersion': 1,
          'resourceEpoch': 2,
          'payload': Uint8List(1),
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(
        surface.retire({
          'schemaVersion': 1,
          'resourceEpoch': 1,
        })['resourceEpoch'],
        1,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
