import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_projection.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import '../../app/menu_overlay/menu_comms_session_test.dart' as comms;
import '../../app/menu_overlay/menu_friends_session_test.dart' as friends;

class Feature extends MenuFeatureSession {
  Feature(super.publish, super.invalidations);
  final reads = <Completer<Map<String, Object?>>>[];
  int cancels = 0;
  @override
  bool get backgroundReads => true;
  @override
  Map<String, Object?>? get readingView =>
      currentView['state'] == 'ready' ? currentView : null;
  @override
  void reset() => changeScope();
  @override
  void cancelRead() => cancels++;
  @override
  Future<void> closePort() async {}
  @override
  Future<Map<String, Object?>> read() {
    final reply = Completer<Map<String, Object?>>();
    reads.add(reply);
    return reply.future;
  }
}

MenuReadFeedback? feedback(Map view) =>
    MenuReadFeedback.parse(view['readFeedback']);

void main() {
  test('synchronous provenance is nested, exception-safe, and expires before async continuations', () async {
    expect(currentMenuReadOrigin, MenuReadOrigin.programmatic);
    final seen = <MenuReadOrigin>[];
    final future = withMenuReadOrigin('pointer', () async {
      seen.add(currentMenuReadOrigin);
      withMenuReadOrigin('keyboard', () => seen.add(currentMenuReadOrigin));
      seen.add(currentMenuReadOrigin);
      await Future<void>.value();
      seen.add(currentMenuReadOrigin);
      await Future<void>.delayed(Duration.zero);
      seen.add(currentMenuReadOrigin);
    });
    expect(currentMenuReadOrigin, MenuReadOrigin.programmatic);
    await future;
    expect(seen, [
      MenuReadOrigin.pointer,
      MenuReadOrigin.keyboard,
      MenuReadOrigin.pointer,
      MenuReadOrigin.programmatic,
      MenuReadOrigin.programmatic,
    ]);
    final problem = StateError('fixture');
    expect(
      () => withMenuReadOrigin('pointer', () => throw problem),
      throwsA(same(problem)),
    );
    expect(currentMenuReadOrigin, MenuReadOrigin.programmatic);
  });
  for (final invalid in [
    null,
    {},
    true,
    {'request': 0, 'source': 'pointer'},
    {'request': 1000000001, 'source': 'pointer'},
    {'request': 1, 'source': 'reader'},
    {'request': '1', 'source': 'pointer'},
    {'request': 1, 'source': []},
    'pointer',
  ]) {
    test(
      'invalid optional read decoration is static without changing business availability: $invalid',
      () {
        expect(MenuReadFeedback.parse(invalid), isNull);
        final data = {
          'state': 'ready',
          'rows': [],
          'incoming': 0,
          'readFeedback': invalid,
        };
        final private = MenuCommsView.parse(jsonEncode(data));
        final people = MenuFriendsView.parse(jsonEncode(data));
        final feature = MenuFeatureView.parse(data);
        expect(
          [private.state, people.state, feature.state],
          ['ready', 'ready', 'ready'],
        );
        expect([
          private.readFeedback,
          people.readFeedback,
          feature.readFeedback,
        ], everyElement(isNull));
      },
    );
  }
  for (final origin in MenuReadOrigin.values) {
    test('valid $origin roundtrips only bounded display facts', () {
      final wire = MenuReadFeedback(7, origin).wire;
      expect(wire.keys, unorderedEquals(['request', 'source']));
      expect(MenuReadFeedback.parse(wire)?.origin, origin);
      expect(
        MenuCommsView.parse(
          jsonEncode({'state': 'loading', 'readFeedback': wire}),
        ).readFeedback?.request,
        7,
      );
    });
    testWidgets(
      '$origin actual private read admission retires metadata and rejects late A over B',
      (t) async {
        final port = comms.Port(), views = <Map<String, Object?>>[];
        final owner = MenuCommsSession(port, views.add);
        try {
          withMenuReadOrigin(origin.name, () => owner.show(true));
          expect(feedback(views.last)?.origin, origin);
          final first = feedback(views.last)!.request;
          port.directories.last.complete([comms.peer('A')]);
          await t.pump();
          expect(feedback(views.last), isNull);
          final key = MenuCommsView.parse(jsonEncode(views.last))
              .rows
              .single
              .key;
          withMenuReadOrigin(origin.name, () => owner.act('select', key));
          final stale = port.histories.last.reply,
              pending = feedback(views.last)!;
          expect(pending.request, greaterThan(first));
          expect(pending.origin, origin);
          withMenuReadOrigin('pointer', () => owner.act('latest', ''));
          expect(
            feedback(views.last)?.request,
            pending.request,
            reason: 'busy latest is not an admitted read',
          );
          withMenuReadOrigin('pointer', () => owner.act('retry', ''));
          final next = feedback(views.last)!;
          expect(next.origin, MenuReadOrigin.pointer);
          expect(next.request, greaterThan(pending.request));
          stale.completeError(const DirectReadFailure('unavailable'));
          await t.pump();
          expect(feedback(views.last)?.request, next.request);
          port.histories.last.reply.complete(comms.page('secret-A'));
          await t.pump();
          expect(feedback(views.last), isNull);
        } finally {
          owner.dispose();
          await t.pump(const Duration(seconds: 13));
        }
      },
    );
    testWidgets(
      '$origin actual private silent cached select, timer and identity have no borrowed source',
      (t) async {
        final port = comms.Port(), views = <Map<String, Object?>>[];
        final owner = MenuCommsSession(port, views.add)..show(true);
        try {
          port.directories.last.complete([comms.peer('A')]);
          await t.pump();
          final key = MenuCommsView.parse(jsonEncode(views.last))
              .rows
              .single
              .key;
          owner.act('select', key);
          port.histories.last.reply.complete(comms.page('secret-A'));
          await t.pump();
          withMenuReadOrigin(origin.name, () => owner.act('back', ''));
          port.directories.last.complete([comms.peer('A')]);
          await t.pump();
          final secondKey = MenuCommsView.parse(jsonEncode(views.last))
              .rows
              .single
              .key;
          withMenuReadOrigin(origin.name, () => owner.act('select', secondKey));
          expect(views.last['refreshing'], isFalse);
          expect(feedback(views.last), isNull);
          port.histories.last.reply.complete(comms.page('secret-A'));
          await t.pump();
          await t.pump(const Duration(seconds: 3));
          expect(feedback(views.last), isNull);
          expect(views.last['refreshing'], isFalse);
          port.histories.last.reply.complete(comms.page('secret-A'));
          await t.pump();
          port.events.add(null);
          await t.pump();
          expect(feedback(views.last)?.origin, MenuReadOrigin.programmatic);
          owner.show(false);
          expect(feedback(views.last), isNull);
        } finally {
          owner.dispose();
          await t.pump(const Duration(seconds: 13));
        }
      },
    );
    testWidgets(
      '$origin actual friends refresh A to B preserves B and silent failure clears decoration',
      (t) async {
        final port = friends.Port(), views = <Map<String, Object?>>[];
        final owner = MenuFriendsSession(port, views.add);
        try {
          withMenuReadOrigin(origin.name, () => owner.show(true));
          expect(feedback(views.last)?.origin, origin);
          final stale = port.reads.last;
          withMenuReadOrigin('pointer', () => owner.act('refresh', '', ''));
          final next = feedback(views.last)!;
          stale.complete(friends.ready('Old'));
          await t.pump();
          expect(feedback(views.last)?.request, next.request);
          port.reads.last.complete(friends.ready('New'));
          await t.pump();
          expect(feedback(views.last), isNull);
          await t.pump(const Duration(seconds: 10));
          port.reads.last.complete(
            const FriendsReadResult(FriendsReadState.unavailable),
          );
          await t.pump();
          expect(feedback(views.last), isNull);
          port.events.add(null);
          await t.pump();
          expect(feedback(views.last)?.origin, MenuReadOrigin.programmatic);
          owner.show(false);
          expect(feedback(views.last), isNull);
        } finally {
          owner.dispose();
          await t.pump(const Duration(seconds: 11));
        }
      },
    );
    testWidgets(
      '$origin generic feature admitted refresh, spread, failure, no-op and automatic continuation',
      (t) async {
        final events = StreamController<void>.broadcast(sync: true),
            views = <Map<String, Object?>>[];
        final owner = Feature(views.add, events.stream);
        try {
          withMenuReadOrigin(origin.name, () => owner.show(true));
          expect(feedback(views.last)?.origin, origin);
          owner.reads.last.complete({'title': 'Kept', 'rows': []});
          await t.pump();
          expect(feedback(views.last), isNull);
          withMenuReadOrigin(origin.name, () => owner.act('refresh', ''));
          final current = feedback(views.last)!;
          expect(views.last['refreshing'], isTrue);
          withMenuReadOrigin('keyboard', () => owner.act('refresh', ''));
          expect(feedback(views.last)?.request, current.request);
          owner.reads.last.completeError(StateError('fixture'));
          await t.pump();
          expect(feedback(views.last), isNull);
          owner.emit({'state': 'ready', 'readFeedback': current.wire});
          expect(
            feedback(views.last),
            isNull,
            reason: 'spreading stale metadata must not revive it',
          );
          final grant = owner.button('An accepted task', (_) async {});
          withMenuReadOrigin(
            origin.name,
            () => owner.act(grant['key'] as String, ''),
          );
          await t.pump();
          expect(feedback(views.last)?.origin, MenuReadOrigin.programmatic);
          final old = owner.reads.last;
          owner.show(false);
          expect(feedback(owner.currentView), isNull);
          withMenuReadOrigin('pointer', () => owner.show(true));
          final next = feedback(views.last)!;
          old.complete({'title': 'Old'});
          await t.pump();
          expect(feedback(views.last)?.request, next.request);
          owner.reads.last.complete({'title': 'New'});
          await t.pump();
          expect(feedback(views.last), isNull);
        } finally {
          owner.dispose();
          await events.close();
          await t.pump(const Duration(seconds: 16));
        }
      },
    );
  }
}
