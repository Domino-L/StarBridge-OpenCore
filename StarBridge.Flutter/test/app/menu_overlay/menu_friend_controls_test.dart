import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';

void main() {
  testWidgets(
    'confirmation is revealed after selecting a person below the fold',
    (tester) async {
      Future<void> subject(bool pending) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: MenuFriendsPanel(
                  onClose: () {},
                  onAction: (_, key, value) {},
                  embedded: true,
                  view: MenuFriendsView(
                    'ready',
                    interactive: true,
                    confirmation: pending
                        ? (
                            token: 'confirm1',
                            name: 'Fixture 20',
                            action: 'block',
                          )
                        : null,
                    rows: [
                      for (var i = 0; i < 25; i++)
                        (
                          name: 'Fixture $i',
                          key: 'f$i',
                          avatar: null,
                          presence: 'online',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await subject(false);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      await subject(true);
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const ValueKey('friends-confirm-confirm1')),
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(600));
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'requests, search and confirmation fit narrow windows at scale $scale',
      (tester) async {
        final actions = <({String action, String key, String value})>[];
        Future<void> subject({bool pending = false, bool busy = false}) =>
            tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        child: MenuFriendsPanel(
                          embedded: true,
                          onClose: () {},
                          onProfile: (_) {},
                          onAction: (action, key, value) => actions.add((
                            action: action,
                            key: key,
                            value: value,
                          )),
                          view: MenuFriendsView(
                            'ready',
                            interactive: true,
                            section: 'incoming',
                            busy: busy,
                            actions: const {
                              'f1': ['accept', 'reject'],
                            },
                            confirmation: pending
                                ? (
                                    token: 'confirm1',
                                    name: 'Fixture (handle)',
                                    action: 'accept',
                                  )
                                : null,
                            rows: const [
                              (
                                key: 'f1',
                                name: 'Fixture',
                                avatar: null,
                                presence: 'offline',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
        await subject();
        expect(
          find.text('Fixture'),
          findsOneWidget,
        ); // offline requests are not collapsed
        await tester.enterText(
          find.byKey(const ValueKey('friends-account-search')),
          'fixture',
        );
        expect(actions, isEmpty);
        await tester.ensureVisible(
          find.byKey(const ValueKey('friends-search')),
        );
        await tester.tap(find.byKey(const ValueKey('friends-search')));
        expect(actions.last, (action: 'search', key: '', value: 'fixture'));
        await tester.ensureVisible(find.byKey(const ValueKey('f1')));
        await tester.tap(find.byKey(const ValueKey('f1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('friend-accept-f1')));
        await tester.pumpAndSettle();
        expect(actions.last, (action: 'prepare', key: 'f1', value: 'accept'));
        await subject(pending: true);
        await tester.ensureVisible(
          find.byKey(const ValueKey('friends-confirm-confirm1')),
        );
        await tester.tap(
          find.byKey(const ValueKey('friends-confirm-confirm1')),
        );
        expect(actions.last, (action: 'confirm', key: 'confirm1', value: ''));
        final count = actions.length;
        await subject(pending: true, busy: true);
        await tester.ensureVisible(
          find.byKey(const ValueKey('friends-confirm-confirm1')),
        );
        await tester.tap(
          find.byKey(const ValueKey('friends-confirm-confirm1')),
        );
        expect(actions.length, count);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('malformed action projection fails closed', () {
    final valid = <String, Object?>{
      'state': 'ready',
      'rows': [],
      'incoming': 0,
      'interactive': true,
      'busy': false,
      'requiresRefresh': false,
      'section': 'friends',
      'query': '',
      'feedback': '',
      'actions': {},
    };
    for (final bad in <Map<String, Object?>>[
      {
        'actions': {
          'f1': ['delete-account'],
        },
      },
      {'query': 'x' * 129},
      {'busy': 'false'},
      {
        'confirmation': {
          'token': 'private-ref',
          'name': 'Person',
          'action': 'remove',
        },
      },
      {'section': 'admin'},
      {'feedback': 'arbitrary server error'},
    ]) {
      final view = MenuFriendsView.parse(jsonEncode({...valid, ...bad}));
      expect(view.state, 'unavailable');
      expect(view.actions, isEmpty);
      expect(view.confirmation, null);
    }
  });
}
