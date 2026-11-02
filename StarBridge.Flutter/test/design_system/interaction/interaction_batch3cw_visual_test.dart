import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cw_test.dart' show sampleFrame, fire;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cw');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final scale in [1.0, 2.0]) {
      for (final rtl in [false, true]) {
        for (final end in [false, true]) {
          testWidgets(
            '$suite native wide return geometry scale=$scale rtl=$rtl end=$end',
            (t) async {
              t.view.devicePixelRatio = 1;
              t.view.physicalSize = const Size(1200, 700);
              Future<(Size, Rect, Rect)> sample(bool original) async {
                await t.pumpWidget(
                  host(
                    Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: Directionality(
                          textDirection: rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              textButtonTheme: TextButtonThemeData(
                                style: TextButtonTheme.of(context).style!
                                    .copyWith(
                                      iconAlignment: end
                                          ? IconAlignment.end
                                          : IconAlignment.start,
                                    ),
                              ),
                            ),
                            child: original
                                ? Center(
                                    child: TextButton.icon(
                                      key: const ValueKey('menu-return'),
                                      onPressed: () {},
                                      icon: const StarBridgeIcon(
                                        StarBridgeIconSemantic.windowClose,
                                      ),
                                      label: const Text('返回游戏'),
                                    ),
                                  )
                                : sampleFrame((_) {}),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    reduce: true,
                  ),
                );
                await t.pumpAndSettle();
                final target = find.byKey(const ValueKey('menu-return'));
                final r = t.getRect(target);
                final text = find.descendant(
                  of: target,
                  matching: find.text('返回游戏'),
                );
                final icon = find.descendant(
                  of: target,
                  matching: find.byType(StarBridgeIcon),
                );
                expect(text, findsOneWidget);
                expect(icon, findsOneWidget);
                return (
                  r.size,
                  t.getRect(text).shift(-r.topLeft),
                  t.getRect(icon).shift(-r.topLeft),
                );
              }

              try {
                final native = await sample(true);
                final actual = await sample(false);
                expect(actual, native);
                expect(t.takeException(), isNull);
              } finally {
                await detach(t);
                t.view.reset();
              }
            },
          );
        }
      }
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source settings visible feedback follows input policy',
        (t) async {
          final semantics = t.ensureSemantics();
          final boundary = GlobalKey();
          var calls = 0;
          try {
            await t.pumpWidget(
              host(
                RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 750,
                    height: 500,
                    child: sampleFrame((_) => calls++),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final target = find.byKey(const ValueKey('menu-settings'));
            await fire(t, source, target, '设置');
            await t.pump();
            final before = await pixels(t, boundary);
            await capture(t, boundary, '${suite.name}-$source-before');
            await t.pump(const Duration(milliseconds: 75));
            final after = await pixels(t, boundary);
            if (source == 'pointer') {
              expect(after, isNot(orderedEquals(before)));
            } else {
              expect(after, orderedEquals(before));
            }
            expect(calls, 1);
            await capture(t, boundary, '${suite.name}-$source-after');
          } finally {
            semantics.dispose();
            await detach(t);
          }
        },
      );
    }
    for (final width in [320.0, 1600.0]) {
      testWidgets(
        '$suite $width frame fits 200percent and captures approved shape',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(width, 850);
          final boundary = GlobalKey();
          try {
            await t.pumpWidget(
              host(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: RepaintBoundary(
                      key: boundary,
                      child: sampleFrame((_) {}),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            for (final key in [
              'menu-return',
              'menu-settings',
              'menu-tool-probe',
            ]) {
              final rect = t.getRect(find.byKey(ValueKey(key)));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.height, greaterThanOrEqualTo(40));
            }
            expect(t.takeException(), isNull);
            await capture(t, boundary, '${suite.name}-$width-200percent');
          } finally {
            await detach(t);
            t.view.reset();
          }
        },
      );
    }
  }
}
