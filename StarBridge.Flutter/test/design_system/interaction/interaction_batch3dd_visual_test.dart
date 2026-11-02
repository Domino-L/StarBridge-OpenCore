import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/friends/friends_waiting_indicator.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort, ready;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3db_actions_test.dart' show SearchFixture;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> capture(WidgetTester t, GlobalKey key, String? name) =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        if (name != null) {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
          final file = File('build/reviews/interaction-batch3dd/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png);
        }
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite light=$light scale=$scale live wait pixels and static alternatives',
          (t) async {
            size(t, const Size(1000, 800));
            final settings = ValueNotifier((false, InteractionSource.pointer));
            final frame = GlobalKey();
            final sem = t.ensureSemantics();
            try {
              await t.pumpWidget(
                ValueListenableBuilder<(bool, InteractionSource)>(
                  valueListenable: settings,
                  builder: (_, value, _) => scopedApp(
                    MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Center(
                        child: RepaintBoundary(
                          key: frame,
                          child: Material(
                            child: SizedBox(
                              width: 600,
                              height: 240,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FriendsWaitingIndicator(
                                      label: '正在读取好友…',
                                      source: value.$2,
                                      controlKey: const Key('initial-wait'),
                                      showLabel: true,
                                    ),
                                    const SizedBox(height: 30),
                                    FriendsWaitingIndicator(
                                      label: '正在更新好友…',
                                      source: value.$2,
                                      controlKey: const Key('refresh-wait'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                    reduce: value.$1,
                  ),
                ),
              );
              await t.pump();
              await t.pump();
              await t.pump(const Duration(milliseconds: 16));
              await t.pump(const Duration(milliseconds: 16));
              final prefix =
                  '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
              final before = await capture(t, frame, '$prefix-initial');
              await t.pump(const Duration(milliseconds: 160));
              expect(await capture(t, frame, '$prefix-moving'), isNot(before));
              final node = t
                  .getSemantics(find.byKey(const Key('initial-wait')))
                  .getSemanticsData();
              expect(node.label, '正在读取好友…');
              expect(node.value, isEmpty);
              settings.value = (true, InteractionSource.pointer);
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              final reduced = await capture(t, frame, '$prefix-reduce');
              await t.pump(const Duration(milliseconds: 200));
              expect(await capture(t, frame, null), reduced);
              settings.value = (false, InteractionSource.keyboard);
              await t.pump();
              await t.pump();
              final keyboard = await capture(t, frame, '$prefix-keyboard');
              await t.pump(const Duration(milliseconds: 200));
              expect(await capture(t, frame, null), keyboard);
              expect(find.byType(SuiteProgressBar), findsNothing);
              settings.value = (false, InteractionSource.pointer);
              await t.pump();
              await t.pump(const Duration(milliseconds: 200));
              await capture(t, frame, '$prefix-restored');
              expect(find.byType(SuiteProgressBar), findsNWidgets(2));
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await t.pumpWidget(const SizedBox());
              settings.dispose();
            }
          },
        );
      }
    }
    for (final input in ['pointer', 'keyboard']) {
      testWidgets(
        '$suite $input actual pending refresh follows live reduce without another request',
        (t) async {
          final h = SearchFixture();
          try {
            await h.mount(t, suite);
            await fire(t, input, 'friends-refresh');
            await t.pump();
            await t.pump();
            Widget page(bool reduce) => scopedApp(
              FriendsPage(
                createPort: () => throw StateError('borrowed'),
                module: h.owner,
              ),
              suite,
              reduce: reduce,
            );
            await t.pumpWidget(page(true));
            await t.pump();
            await t.pump();
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
            await t.pumpWidget(page(false));
            await t.pump();
            await t.pump();
            expect(
              find.byType(SuiteProgressBar),
              input == 'pointer' ? findsOneWidget : findsNothing,
            );
            expect(h.port.requests, hasLength(2));
            h.port.requests.last.complete(ready('Confirmed'));
            await t.pumpAndSettle();
            expect(find.byType(FriendsWaitingIndicator), findsNothing);
          } finally {
            await h.close(t);
          }
        },
      );
    }
    testWidgets(
      '$suite real owned page disposal retires pending wait before late response',
      (t) async {
        size(t, const Size(1400, 1000));
        final port = PendingPort();
        await t.pumpWidget(
          scopedApp(FriendsPage(createPort: () => port), suite),
        );
        await t.pump();
        await t.pump();
        expect(port.requests, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(port.closed, isTrue);
        port.requests.single.complete(ready('Retired'));
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
  }
}
