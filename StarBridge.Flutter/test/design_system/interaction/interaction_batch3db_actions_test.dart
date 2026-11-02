import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort, ready;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3i_test.dart' show scopedApp;

class SearchPort extends PendingPort {
  final sources = <InteractionSource>[];
  @override
  Future<FriendsReadResult> read({String? query}) {
    sources.add(currentStarBridgeActivationSource);
    return super.read(query: query);
  }
}

class SearchFixture {
  final port = SearchPort();
  late final owner = FriendsModule(port, now: () => DateTime.utc(2026, 10, 15));
  Widget page(InteractionSuite suite) => scopedApp(
    FriendsPage(
      createPort: () => throw StateError('Borrowed owner'),
      module: owner,
    ),
    suite,
  );
  Future<void> mount(WidgetTester t, InteractionSuite suite) async {
    size(t, const Size(1400, 1000));
    final first = owner.enter();
    port.requests.single.complete(ready('初始好友'));
    await first;
    await t.pumpWidget(page(suite));
    await t.pumpAndSettle();
  }

  Finder get input => find.byType(TextField).first;
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    owner.dispose();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final action in ['search', 'refresh', 'clear-query', 'retry']) {
        testWidgets(
          '$suite $source actual friends $action preserves read intent and confirmation',
          (t) async {
            final h = SearchFixture();
            final semantics = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              if (action != 'refresh') {
                await t.enterText(h.input, 'Pilot');
                await t.pump();
                expect(h.port.queries, [
                  null,
                ], reason: 'Typing must not submit a nonempty query');
              }
              if (action == 'retry') {
                final read = h.owner.refresh();
                h.port.requests.last.complete(
                  const FriendsReadResult(FriendsReadState.unavailable),
                );
                await read;
                await t.pumpAndSettle();
                expect(find.byKey(const Key('friends-retry')), findsOneWidget);
              }
              final before = h.port.requests.length;
              await fire(t, source, 'friends-$action');
              expect(h.port.requests, hasLength(before + 1));
              expect(
                h.port.queries.last,
                action == 'refresh' || action == 'clear-query' ? null : 'Pilot',
              );
              expect(
                h.port.sources.last,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(h.owner.reading, isTrue);
              if (action == 'refresh') {
                expect(h.owner.rows.single.callsign, '初始好友');
              } else {
                expect(
                  h.owner.rows,
                  isEmpty,
                  reason: 'No optimistic search success',
                );
              }
              await t.pump();
              if (action == 'refresh' || action == 'search') {
                await t.tapAt(t.getCenter(find.byKey(Key('friends-$action'))));
                await t.pump();
                expect(h.port.requests, hasLength(before + 1));
              }
              h.port.requests.last.complete(
                ready('确认好友', query: h.port.queries.last),
              );
              await t.pumpAndSettle();
              expect(h.owner.rows.single.callsign, '确认好友');
              expect(h.owner.reading, isFalse);
              expect(
                captureStarBridgeActivationSource()(),
                InteractionSource.programmatic,
              );
              expect(t.takeException(), isNull);
            } finally {
              await h.close(t);
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite IME submit reports keyboard and invalid query does not read',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await t.enterText(h.input, 'x');
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump();
          expect(h.port.requests, hasLength(1));
          await t.enterText(h.input, 'Pilot');
          await t.testTextInput.receiveAction(TextInputAction.done);
          expect(h.port.queries, [null, 'Pilot']);
          expect(h.port.sources.last, InteractionSource.keyboard);
          h.port.requests.last.complete(ready('键盘确认', query: 'Pilot'));
          await t.pumpAndSettle();
          expect(h.owner.rows.single.callsign, '键盘确认');
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite newer query retires old search response without swapping editor',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await t.enterText(h.input, 'Older');
          await fire(t, 'pointer', 'friends-search');
          final old = h.port.requests.last;
          final controller = t.widget<TextField>(h.input).controller;
          await t.pump();
          await t.enterText(h.input, 'Latest');
          await t.pump();
          await fire(t, 'keyboard', 'friends-search');
          h.port.requests.last.complete(ready('最新确认', query: 'Latest'));
          await t.pumpAndSettle();
          old.complete(ready('已退休', query: 'Older'));
          await t.pumpAndSettle();
          expect(h.owner.query, 'Latest');
          expect(h.owner.rows.single.callsign, '最新确认');
          expect(t.widget<TextField>(h.input).controller, same(controller));
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite refresh failure retains rows and explicit retry recovers',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await fire(t, 'pointer', 'friends-refresh');
          h.port.requests.last.completeError(
            TimeoutException('Synthetic timeout'),
          );
          await t.pumpAndSettle();
          expect(h.owner.refreshFailed, isTrue);
          expect(h.owner.rows.single.callsign, '初始好友');
          expect(find.byKey(const Key('friends-sync-failed')), findsOneWidget);
          await fire(t, 'keyboard', 'friends-refresh');
          h.port.requests.last.complete(ready('重试确认'));
          await t.pumpAndSettle();
          expect(h.owner.refreshFailed, isFalse);
          expect(h.owner.rows.single.callsign, '重试确认');
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite leaving pending read keeps owner and fresh reopening does not duplicate',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await fire(t, 'pointer', 'friends-refresh');
          await t.pumpWidget(scopedApp(const SizedBox(), suite));
          h.port.requests.last.complete(ready('离开后确认'));
          await t.pumpAndSettle();
          expect(h.owner.rows.single.callsign, '离开后确认');
          await t.pumpWidget(h.page(suite));
          await t.pumpAndSettle();
          expect(h.port.requests, hasLength(2));
          expect(h.owner.rows.single.callsign, '离开后确认');
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
    );
  }
}
