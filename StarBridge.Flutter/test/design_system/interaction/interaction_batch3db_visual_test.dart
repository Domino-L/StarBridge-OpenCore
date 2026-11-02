import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3db_actions_test.dart' show SearchFixture;
import 'interaction_batch3db_fields_test.dart' show capture;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<Uint8List> buttonPixels(WidgetTester t, GlobalKey boundary) async {
  final bytes = await pixels(t, boundary);
  final root = t.getRect(find.byKey(boundary));
  final rect = t
      .getRect(find.byKey(const Key('friends-search')))
      .shift(-root.topLeft);
  final result = BytesBuilder();
  final width = root.width.round();
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
    result.add(
      bytes.sublist(
        (y * width + rect.left.ceil()) * 4,
        (y * width + rect.right.floor()) * 4,
      ),
    );
  }
  return result.toBytes();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite light=$light scale=$scale actual search press visible and live reduce settles without read',
          (t) async {
            final h = SearchFixture();
            final boundary = GlobalKey();
            var reduce = false;
            late StateSetter update;
            try {
              await h.mount(t, suite);
              await t.pumpWidget(
                StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return RepaintBoundary(
                      key: boundary,
                      child: scopedApp(
                        Builder(
                          builder: (context) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(textScaler: TextScaler.linear(scale)),
                            child: FriendsPage(
                              createPort: () =>
                                  throw StateError('Borrowed owner'),
                              module: h.owner,
                            ),
                          ),
                        ),
                        suite,
                        light: light,
                        reduce: reduce,
                      ),
                    );
                  },
                ),
              );
              await t.pumpAndSettle();
              await t.enterText(h.input, 'Pilot');
              await t.pumpAndSettle();
              final name = 'search-${suite.name}-$light-$scale';
              await capture(t, boundary, '$name-idle');
              final idle = await buttonPixels(t, boundary);
              final press = await t.startGesture(
                t.getCenter(find.byKey(const Key('friends-search'))),
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 30));
              expect(
                await buttonPixels(t, boundary),
                isNot(orderedEquals(idle)),
              );
              await capture(t, boundary, '$name-pressed');
              expect(h.port.requests, hasLength(1));
              update(() => reduce = true);
              await t.pump();
              await t.pump();
              final still = await buttonPixels(t, boundary);
              await t.pump(const Duration(milliseconds: 80));
              expect(await buttonPixels(t, boundary), orderedEquals(still));
              await capture(t, boundary, '$name-reduced');
              await press.cancel();
              await t.pumpAndSettle();
              expect(h.port.requests, hasLength(1));
              expect(h.owner.query, 'Pilot');
              expect(t.takeException(), isNull);
            } finally {
              await h.close(t);
            }
          },
        );
      }
    }
  }
}
