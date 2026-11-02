import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_busy.dart';
import 'package:starbridge_flutter/features/communities/community_section_navigation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cv_test.dart' show roomFixture;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cv');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> showChat(WidgetTester t) async {
  if (find.byKey(const Key('menu-room-message-refresh')).evaluate().isEmpty) {
    t
        .widget<CommunitySectionNavigation>(
          find.byType(CommunitySectionNavigation),
        )
        .onSelected('chat');
    await t.pumpAndSettle();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in InteractionSource.values) {
      testWidgets(
        '$suite $source waiting pixels retain pointer motion and static alternatives',
        (t) async {
          final boundary = GlobalKey();
          try {
            await t.pumpWidget(
              host(
                RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 300,
                    child: MenuRecoveryBusy(source: source),
                  ),
                ),
                suite,
              ),
            );
            await t.pump();
            final before = await pixels(t, boundary);
            await capture(
              t,
              boundary,
              '${suite.name}-${source.name}-wait-before',
            );
            await t.pump(const Duration(milliseconds: 150));
            final after = await pixels(t, boundary);
            if (source == InteractionSource.pointer) {
              expect(after, isNot(orderedEquals(before)));
            } else {
              expect(after, orderedEquals(before));
            }
            await capture(
              t,
              boundary,
              '${suite.name}-${source.name}-wait-after',
            );
            expect(t.takeException(), isNull);
          } finally {
            await detach(t);
          }
        },
      );
    }
    testWidgets(
      '$suite pointer waiting settles visibly on live reduce and resumes only when allowed',
      (t) async {
        final boundary = GlobalKey();
        var reduce = false;
        late StateSetter update;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  RepaintBoundary(
                    key: boundary,
                    child: const SizedBox(
                      width: 300,
                      child: MenuRecoveryBusy(
                        source: InteractionSource.pointer,
                      ),
                    ),
                  ),
                  suite,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 100));
          final state = t.state(find.byType(SuiteBusyFrame));
          update(() => reduce = true);
          await t.pump();
          await t.pump();
          final still = await pixels(t, boundary);
          await capture(t, boundary, '${suite.name}-live-reduce-static');
          await t.pump(const Duration(milliseconds: 170));
          expect(await pixels(t, boundary), orderedEquals(still));
          expect(t.state(find.byType(SuiteBusyFrame)), same(state));
          update(() => reduce = false);
          await t.pump();
          await t.pump(const Duration(milliseconds: 150));
          expect(await pixels(t, boundary), isNot(orderedEquals(still)));
          await capture(t, boundary, '${suite.name}-live-reduce-resumed');
        } finally {
          await detach(t);
        }
      },
    );

    for (final width in [320.0, 1600.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite room native sizing and visible bounds width=$width text=$scale',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 1100);
            final (view, session) = await roomFixture(t, compatible: true);
            final boundary = GlobalKey();
            Widget frame(Widget child) => host(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: boundary, child: child),
                ),
              ),
              suite,
              reduce: true,
            );
            try {
              await t.pumpWidget(
                frame(MenuRoomsPanel(view: view, onAction: (_, _) {})),
              );
              await t.pumpAndSettle();
              final sizes = <String, Size>{};
              final offsets = <String, Offset>{};
              void remember(String id, String label) {
                final target = find.byKey(ValueKey(id));
                // Key and ValueKey intentionally differ for existing settings.
                final actual = id == 'menu-room-settings'
                    ? target
                    : find.byKey(Key(id));
                final rect = t.getRect(actual);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(rect.bottom, lessThanOrEqualTo(1100));
                sizes[label] = rect.size;
                offsets[label] =
                    t.getTopLeft(
                      find.descendant(of: actual, matching: find.text(label)),
                    ) -
                    rect.topLeft;
              }

              remember('menu-room-refresh', '刷新房间');
              remember('menu-room-settings', '房间设置');
              await capture(
                t,
                boundary,
                '${suite.name}-${width.toInt()}-$scale-members',
              );
              await showChat(t);
              remember('menu-room-message-refresh', '刷新消息');
              await capture(
                t,
                boundary,
                '${suite.name}-${width.toInt()}-$scale-chat',
              );
              expect(t.takeException(), isNull);
              if (suite == InteractionSuite.standard) {
                // Original public native controls, not a copied room controller.
                await detach(t);
                await t.pumpWidget(
                  frame(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final label in ['刷新房间', '刷新消息'])
                          TextButton(
                            key: ValueKey(label),
                            onPressed: () {},
                            child: Text(label),
                          ),
                        OutlinedButton(
                          key: const ValueKey('房间设置'),
                          onPressed: () {},
                          child: const Text('房间设置'),
                        ),
                      ],
                    ),
                  ),
                );
                await t.pumpAndSettle();
                for (final label in sizes.keys) {
                  final target = find.byKey(ValueKey(label));
                  expect(t.getSize(target), sizes[label]);
                  expect(
                    t.getTopLeft(
                          find.descendant(
                            of: target,
                            matching: find.text(label),
                          ),
                        ) -
                        t.getTopLeft(target),
                    offsets[label],
                  );
                }
              }
            } finally {
              await detach(t);
              session.dispose();
              await t.pump();
              t.view.reset();
            }
          },
        );
      }
    }
  }
}
