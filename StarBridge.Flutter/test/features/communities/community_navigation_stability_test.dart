import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      for (final reduced in [false, true]) {
        testWidgets(
          'navigation stays fixed ${locale.toLanguageTag()} $width reduced=$reduced',
          (tester) async {
            tester.view.physicalSize = Size(width, 950);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final port = ExampleCommunities();
            addTearDown(port.close);
            await tester.pumpWidget(
              host(
                port,
                locale,
                target: '00000000000000000000000000000001',
                disableAnimations: reduced,
              ),
            );
            await tester.pumpAndSettle();
            Finder tab(String id) =>
                find.byKey(ValueKey('community-section-$id'));
            final ids = ['members', 'chat', 'ships', 'broadcast'];
            Map<String, Rect> rectangles() => {
              for (final id in ids) id: tester.getRect(tab(id)),
            };
            Map<String, Rect> labels() => {
              for (final id in ids)
                id: tester.getRect(
                  find
                      .descendant(of: tab(id), matching: find.byType(Text))
                      .first,
                ),
            };
            final mouse = await tester.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            addTearDown(mouse.removePointer);
            for (final detailsVisited in [false, true]) {
              if (detailsVisited) {
                await tester.tap(
                  find.byKey(const Key('community-open-details')),
                );
                await tester.pumpAndSettle();
                final dialog = find.byKey(
                  const Key('community-details-dialog'),
                );
                expect(dialog, findsOneWidget);
                await tester.tap(
                  find
                      .descendant(of: dialog, matching: find.byType(TextButton))
                      .last,
                );
                await tester.pumpAndSettle();
              }
              final expected = rectangles();
              final expectedLabels = labels();
              for (final id in [
                'chat',
                'ships',
                'members',
                'ships',
                'chat',
                'members',
              ]) {
                await mouse.moveTo(tester.getCenter(tab(id)));
                await tester.pump(const Duration(milliseconds: 30));
                expect(rectangles(), expected);
                expect(labels(), expectedLabels);
                await mouse.down(tester.getCenter(tab(id)));
                await tester.pump();
                expect(rectangles(), expected);
                await mouse.up();
                await tester.pump();
                expect(rectangles(), expected);
                await tester.pumpAndSettle();
                expect(rectangles(), expected);
                expect(labels(), expectedLabels);
                expect(tester.widget<ChoiceChip>(tab(id)).selected, isTrue);
                expect(
                  tester.widget<ChoiceChip>(tab(id)).showCheckmark,
                  isFalse,
                );
                expect(
                  find.byKey(const Key('community-header-information')),
                  findsOneWidget,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$id detailsVisited=$detailsVisited',
                );
              }
            }
            if (width == 1200 && locale.countryCode == 'CN' && !reduced) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('workspace-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final data = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                await File('build/community-stable-navigation-review.png')
                    .writeAsBytes(data.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
