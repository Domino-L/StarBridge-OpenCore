import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort, ready;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final reduce in [false, true]) {
      testWidgets(
        '$suite reduce=$reduce actual initial wait uses approved path',
        (t) async {
          size(t, const Size(1400, 1000));
          final port = PendingPort();
          final owner = FriendsModule(port);
          try {
            await t.pumpWidget(
              scopedApp(
                FriendsPage(
                  createPort: () => throw StateError('borrowed'),
                  module: owner,
                ),
                suite,
                reduce: reduce,
              ),
            );
            await t.pump();
            await t.pump();
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              find.byKey(const Key('friends-initial-wait')),
              findsOneWidget,
            );
            expect(
              find.byType(SuiteProgressBar),
              reduce ? findsNothing : findsOneWidget,
            );
            if (!reduce) {
              expect(
                t.getSize(find.byType(SuiteProgressBar)).width,
                greaterThan(0),
              );
            }
            port.requests.single.complete(ready('Confirmed'));
            await t.pumpAndSettle();
            expect(find.byKey(const Key('friends-initial-wait')), findsNothing);
            expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
          } finally {
            await t.pumpWidget(const SizedBox());
            owner.dispose();
          }
        },
      );
      testWidgets(
        '$suite reduce=$reduce same-query refresh keeps original rows',
        (t) async {
          size(t, const Size(1400, 1000));
          final port = PendingPort();
          final owner = FriendsModule(port, now: () => DateTime.utc(2026));
          final read = owner.enter();
          port.requests.single.complete(ready('Current'));
          await read;
          try {
            await t.pumpWidget(
              scopedApp(
                FriendsPage(
                  createPort: () => throw StateError('borrowed'),
                  module: owner,
                ),
                suite,
                reduce: reduce,
              ),
            );
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('friends-refresh')));
            await t.pump();
            await t.pump();
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(find.byKey(const Key('friends-syncing')), findsOneWidget);
            expect(
              find.byType(SuiteProgressBar),
              reduce ? findsNothing : findsOneWidget,
            );
            expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
            port.requests.last.complete(ready('New'));
            await t.pumpAndSettle();
            expect(find.byKey(const Key('friends-syncing')), findsNothing);
          } finally {
            await t.pumpWidget(const SizedBox());
            owner.dispose();
          }
        },
      );
    }
  }
}
