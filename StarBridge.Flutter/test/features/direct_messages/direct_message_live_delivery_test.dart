import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';

import 'direct_messages_test.dart' as fixtures;

// Local transport fixture: no account, network traffic or real message content.
class IncomingPort implements DirectMessagesPort, DirectMessageActivityPort {
  final activity = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => activity.stream;
  final time = DateTime.utc(2026, 9, 25);
  bool arrived = false;
  int reads = 0;
  bool fail = false;
  Completer<DirectPage>? pending;
  Conversation get peer => Conversation('peer', 'Peer', '', time, 0, 'friend');
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async => [
    peer,
    if (arrived) Conversation('other', 'Other', '', time, 1, 'friend'),
  ];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    reads++;
    if (fail) throw const DirectReadFailure('unavailable');
    if (pending != null) return pending!.future;
    return DirectPage(
      ref,
      [
        if (arrived && after < 1)
          DirectMessage(
            1,
            'fixture-message',
            true,
            'Incoming fixture',
            time,
            null,
          ),
      ],
      arrived ? 1 : 0,
      arrived ? 1 : 0,
      false,
      'friend',
    );
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => activity.close();
}

class ScrollPort extends IncomingPort {
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => DirectPage(
    ref,
    List.generate(
      40,
      (i) => DirectMessage(
        i + 1,
        'scroll-$i',
        false,
        'Scroll fixture $i',
        time,
        null,
      ),
    ),
    1,
    40,
    false,
    'friend',
  );
}

void main() {
  testWidgets(
    'shared conversation restores actual viewport after page remount',
    (tester) async {
      final port = ScrollPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(port.peer);
      final base = fixtures.app(const Locale('en'), () => port) as MaterialApp;
      Widget page() => MaterialApp(
        theme: base.theme,
        locale: base.locale,
        supportedLocales: base.supportedLocales,
        localizationsDelegates: base.localizationsDelegates,
        home: Scaffold(
          body: DirectMessagesPage(
            createPort: () => port,
            sharedModule: module,
            initialConversation: port.peer,
            onBack: () {},
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final list = find.byWidgetPredicate(
        (widget) => widget is ListView && widget.reverse,
      );
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.position.maxScrollExtent, greaterThan(300));
      controller.jumpTo(250);
      await tester.pump();
      expect(module.scrollOffset, 250);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.widget<ListView>(list).controller!.offset, 250);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('shared conversation keeps draft when page is remounted', (
    tester,
  ) async {
    final port = IncomingPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.openFriend(port.peer);
    module.editDraft('retained draft');
    final base = fixtures.app(const Locale('en'), () => port) as MaterialApp;
    Widget page() => MaterialApp(
      theme: base.theme,
      locale: base.locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      home: Scaffold(
        body: DirectMessagesPage(
          createPort: () => port,
          sharedModule: module,
          initialConversation: port.peer,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(module.draft, 'retained draft');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(module.draft, 'retained draft');
    await tester.pumpWidget(const SizedBox());
  });
  test('received history advances directory summary without changing unread or identity', () async {
    final port = IncomingPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.openFriend(port.peer);
    port.arrived = true;
    await module.receive();
    final received = module.rows.singleWhere((row) => row.ref == 'peer');
    expect(received.preview, 'Incoming fixture');
    expect(module.selected!.preview, 'Incoming fixture');
    expect(received.time, port.time);
    expect(received.unread, 0);
    expect(received.ref, 'peer');
    expect(module.rows.singleWhere((row) => row.ref == 'other').unread, 1);
  });

  test(
    'activity refreshes directory immediately without a loading state',
    () async {
      final port = IncomingPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      port.arrived = true;
      port.activity.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(module.rows, hasLength(2));
      expect(module.busy, isFalse);
    },
  );
  test(
    'background receipt retains draft and a transient failure retains history',
    () async {
      final port = IncomingPort()..arrived = true;
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(port.peer);
      module.editDraft('unsent fixture');
      await module.receive();
      expect(module.draft, 'unsent fixture');
      expect(module.messages, hasLength(1));
      port.fail = true;
      await module.receive();
      expect(module.error, isNull);
      expect(module.messages, hasLength(1));
      expect(module.draft, 'unsent fixture');
      expect(module.busy, isFalse);
    },
  );

  test(
    'slow receipt is serialized and cannot restore a departed conversation',
    () async {
      final port = IncomingPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(port.peer);
      port.pending = Completer<DirectPage>();
      final receipt = module.receive();
      await module.receive();
      expect(port.reads, 2);
      expect(module.busy, isFalse);
      module.back();
      port.pending!.complete(
        DirectPage(
          'peer',
          [DirectMessage(1, 'late', true, 'late fixture', port.time, null)],
          1,
          1,
          false,
          'friend',
        ),
      );
      await receipt;
      expect(module.selected, isNull);
      expect(module.messages, isEmpty);
    },
  );

  testWidgets(
    'open conversation displays incoming message without manual refresh',
    (tester) async {
      final port = IncomingPort();
      final base = fixtures.app(const Locale('en'), () => port) as MaterialApp;
      await tester.pumpWidget(
        MaterialApp(
          theme: base.theme,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: Scaffold(
            body: DirectMessagesPage(
              createPort: () => port,
              initialConversation: port.peer,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      port.arrived = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final received = find.text('Incoming fixture').evaluate().isNotEmpty;
      await tester.pumpWidget(const SizedBox());
      expect(
        received,
        isTrue,
        reason: 'Incoming message must become visible without pressing refresh',
      );
    },
  );
}
