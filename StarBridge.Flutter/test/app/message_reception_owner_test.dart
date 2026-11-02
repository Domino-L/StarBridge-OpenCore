import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/direct_message_refresh.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

class Backend {
  final hints = StreamController<List<String>>.broadcast(sync: true);
  final activity = StreamController<void>.broadcast(sync: true);
  final invalidations = StreamController<void>.broadcast(sync: true);
  final directories = <String, int>{}, histories = <String, int>{};
  bool healthy = true;
  int generation = 0, mode = 0, unread = 2;
  bool draining = false, arrived = false;
  String? failure;
  Completer<List<Conversation>>? pending;
  final observers = <void Function(bool)>{};
  void changeScope({bool hard = false}) {
    for (final observer in observers.toList()) {
      observer(hard);
    }
  }

  Conversation get peer => Conversation(
    'peer',
    'Peer',
    '',
    DateTime.utc(2026),
    unread,
    'friend',
    conversationKey: 'scoped-fixture',
  );
  Future<void> close() async {
    await hints.close();
    await activity.close();
    await invalidations.close();
  }
}

class Port
    implements
        DirectMessagesPort,
        DirectMessageActivityPort,
        DirectMessageHintPort,
        DirectMessageActivityHealthPort,
        DirectMessageReadScopePort {
  Port(this.backend, this.name);
  final Backend backend;
  final String name;
  int cancels = 0;
  bool closed = false;
  @override
  DirectMessageReadScope? get readScope => closed || backend.draining
      ? null
      : DirectMessageReadScope(backend, backend.generation, backend.mode);
  @override
  void Function() observeReadScope(void Function(bool hard) changed) {
    backend.observers.add(changed);
    return () => backend.observers.remove(changed);
  }

  @override
  Stream<void> get invalidations => backend.invalidations.stream;
  @override
  Stream<void> get changes => backend.activity.stream;
  @override
  Stream<List<String>> get hints => backend.hints.stream;
  @override
  bool get activityHealthy => backend.healthy;
  @override
  Future<List<Conversation>> directory() async {
    backend.directories.update(name, (v) => v + 1, ifAbsent: () => 1);
    if (backend.pending != null) return backend.pending!.future;
    if (backend.failure != null) throw DirectReadFailure(backend.failure!);
    return [backend.peer];
  }

  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    backend.histories.update(name, (v) => v + 1, ifAbsent: () => 1);
    final messages = backend.arrived && after < 1
        ? [
            DirectMessage(
              1,
              'scoped-arrival',
              true,
              'Scoped late arrival',
              DateTime.utc(2026),
              null,
            ),
          ]
        : <DirectMessage>[];
    return DirectPage(
      ref,
      messages,
      messages.isEmpty ? 0 : 1,
      messages.isEmpty ? 0 : 1,
      false,
      'friend',
    );
  }

  @override
  void cancel() {
    cancels++;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

int total(Map<String, int> values) =>
    values.values.fold(0, (sum, v) => sum + v);

class Fixture {
  Fixture() {
    ownerPort = Port(backend, 'unread');
    source = DirectMessageRefresh(ownerPort, account);
    a = source.borrow(rawA = Port(backend, 'a'));
    b = source.borrow(rawB = Port(backend, 'b'));
  }
  final backend = Backend();
  final account = ValueNotifier(
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.legacySignedIn,
    ),
  );
  late final DirectMessageRefresh source;
  late final Port ownerPort, rawA, rawB;
  late final DirectMessagesPort a, b;
  Future<void> close() async {
    await a.close();
    await b.close();
    source.dispose();
    account.dispose();
    await backend.close();
  }
}

Future<void> seconds(WidgetTester t, int count) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(seconds: 1));
    await t.pump();
  }
}

void main() {
  test('directed hints wake only matching current-account history; unknown is directory only', () async {
    final f = Fixture();
    final foreignBackend = Backend();
    final foreign = f.source.borrow(Port(foreignBackend, 'foreign'));
    final a = (f.a as DirectMessageReceptionPort).observeVisibleReception(() => true);
    final b = (f.b as DirectMessageReceptionPort).observeVisibleReception(() => true);
    final c = (foreign as DirectMessageReceptionPort).observeVisibleReception(() => true);
    await Future<void>.delayed(Duration.zero);
    await f.a.history('first');
    await f.b.history('second');
    await foreign.history('first');
    var wakesA = 0, wakesB = 0, wakesForeign = 0;
    final subscriptions = [
      (f.a as DirectMessageActivityPort).changes.listen((_) => wakesA++),
      (f.b as DirectMessageActivityPort).changes.listen((_) => wakesB++),
      (foreign as DirectMessageActivityPort).changes.listen((_) => wakesForeign++),
    ];
    final start = total(f.backend.directories);
    f.backend.hints.add(['first']);
    await Future<void>.delayed(Duration.zero);
    expect(total(f.backend.directories), start + 1);
    expect([wakesA, wakesB, wakesForeign], [1, 0, 0]);
    f.backend.hints.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(total(f.backend.directories), start + 2);
    expect([wakesA, wakesB, wakesForeign], [1, 0, 0]);
    f.backend.hints.add(['second']);
    await Future<void>.delayed(Duration.zero);
    expect([wakesA, wakesB, wakesForeign], [1, 1, 0]);
    for (final sub in subscriptions) { await sub.cancel(); }
    a.dispose(); b.dispose(); c.dispose();
    await foreign.close();
    await foreignBackend.close();
    await f.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a hint for another conversation refreshes visible directories without '
      'waking their history', () async {
    final f = Fixture();
    final a = (f.a as DirectMessageReceptionPort).observeVisibleReception(() => true);
    final b = (f.b as DirectMessageReceptionPort).observeVisibleReception(() => true);
    await Future<void>.delayed(Duration.zero);
    await f.a.history('first'); // A has a conversation open; B shows the list.
    var wakesA = 0, wakesB = 0, listA = 0, listB = 0;
    final subscriptions = [
      (f.a as DirectMessageActivityPort).changes.listen((_) => wakesA++),
      (f.b as DirectMessageActivityPort).changes.listen((_) => wakesB++),
      (f.a as DirectMessageDirectoryActivityPort).directoryChanges.listen((_) => listA++),
      (f.b as DirectMessageDirectoryActivityPort).directoryChanges.listen((_) => listB++),
    ];
    f.backend.unread = 3;
    f.backend.hints.add(['second']);
    await Future<void>.delayed(Duration.zero);
    expect([wakesA, wakesB], [0, 0], reason: 'no history pull for an unrelated hint');
    expect([listA, listB], [1, 1], reason: 'the changed directory reaches visible lists');
    f.backend.hints.add(['second']);
    await Future<void>.delayed(Duration.zero);
    expect([listA, listB], [1, 1], reason: 'an unchanged directory stays quiet');
    for (final sub in subscriptions) { await sub.cancel(); }
    a.dispose(); b.dispose();
    await f.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('foreground degraded reception has one shared budget and idle returns '
      'to the background cadence without reading history', (t) async {
    final f = Fixture();
    f.backend.healthy = false;
    var visible = true;
    final a = (f.a as DirectMessageReceptionPort).observeVisibleReception(
      () => visible,
    );
    final b = (f.b as DirectMessageReceptionPort).observeVisibleReception(
      () => visible,
    );
    await t.pump(const Duration(milliseconds: 1));
    final start = total(f.backend.directories);
    await seconds(t, 60);
    final foreground = total(f.backend.directories) - start;
    visible = false;
    await seconds(t, 2);
    final hidden = total(f.backend.directories);
    await seconds(t, 60);
    final background = total(f.backend.directories) - hidden;
    debugPrint(
      'RECEPTION_BUDGET foreground60=$foreground background60=$background byOwner=${f.backend.directories}',
    );
    a.dispose();
    b.dispose();
    await f.close();
    await t.pump();
    expect(foreground, inInclusiveRange(7, 11));
    expect(background, inInclusiveRange(3, 5));
    expect(f.backend.directories.keys, ['unread']);
    expect(f.backend.histories, isEmpty);
  });

  testWidgets('simultaneous explicit demands join one fresh directory; offered '
      'updates are consumed once and manual retry never reuses them', (
    t,
  ) async {
    final f = Fixture();
    await t.pump();
    final held = f.backend.pending = Completer();
    final start = total(f.backend.directories);
    final one = f.a.directory(), two = f.b.directory();
    await t.pump();
    expect(total(f.backend.directories) - start, 1);
    held.complete([f.backend.peer]);
    f.backend.pending = null;
    expect((await one).single.unread, 2);
    await two;
    await t.pump();
    expect(
      total(f.backend.directories) - start,
      1,
      reason: 'Joining an active read must not queue a duplicate catch-up',
    );
    // Publish a new owner update to both non-requesting borrowers.
    f.backend.unread = 5;
    f.backend.activity.add(null);
    await t.pump();
    final beforeOffer = total(f.backend.directories);
    expect(
      (await (f.a as DirectMessageDirectoryUpdatesPort).receiveDirectory())
          .single
          .unread,
      5,
    );
    expect(total(f.backend.directories), beforeOffer);
    f.backend.unread = 8;
    expect((await f.b.directory()).single.unread, 8);
    expect(total(f.backend.directories), greaterThan(beforeOffer));
    await f.close();
    await t.pump();
  });

  testWidgets(
    'cancelling a view does not cancel the source or another borrowed read',
    (t) async {
      final f = Fixture();
      await t.pump();
      final held = f.backend.pending = Completer();
      final one = f.a.directory(), two = f.b.directory();
      final rejected = expectLater(one, throwsA(isA<DirectReadFailure>()));
      final cancels = f.ownerPort.cancels;
      f.a.cancel();
      held.complete([f.backend.peer]);
      f.backend.pending = null;
      await rejected;
      expect((await two).single.unread, 2);
      expect(f.ownerPort.cancels, cancels);
      expect(f.rawA.cancels, 1);
      expect(f.rawB.cancels, 0);
      await f.a.close();
      expect((await f.b.directory()).single.unread, 2);
      await f.close();
      await t.pump();
    },
  );

  testWidgets(
    'generation fences queued offers and late responses before projection '
    'catches up; account metadata alone preserves drafts',
    (t) async {
      final f = Fixture();
      await t.pump();
      final module = DirectMessagesModule(f.a);
      await module.refresh();
      module.editDraft('keep metadata');
      f.account.value = f.account.value.copyWith(
        operation: AccountOperation.refreshing,
      );
      await t.pump();
      expect(module.draft, 'keep metadata');
      final held = f.backend.pending = Completer();
      final pending = f.b.directory();
      final rejected = expectLater(pending, throwsA(isA<DirectReadFailure>()));
      f.backend.generation++;
      f.backend.changeScope(hard: true);
      expect(f.source.unread.value, 0);
      await expectLater(
        (f.b as DirectMessageDirectoryUpdatesPort).receiveDirectory(),
        throwsA(isA<DirectReadFailure>()),
      );
      held.complete([f.backend.peer]);
      f.backend.pending = null;
      await rejected;
      await t.pump();
      expect(f.source.unread.value, 0);
      expect(module.draft, isEmpty);
      module.dispose();
      await f.close();
      await t.pump();
    },
  );

  testWidgets(
    'mode drain withdraws offers without destroying the same viewer draft',
    (t) async {
      final f = Fixture();
      await t.pump();
      final module = DirectMessagesModule(f.a);
      await module.refresh();
      module.editDraft('same viewer draft');
      f.backend.draining = true;
      f.backend.mode++;
      f.backend.changeScope();
      await module.receive();
      expect(module.draft, 'same viewer draft');
      expect(module.rows, isNotEmpty);
      f.backend.draining = false;
      f.backend.changeScope();
      await t.pump();
      await module.receive();
      expect(module.draft, 'same viewer draft');
      module.dispose();
      await f.close();
      await t.pump();
    },
  );

  testWidgets(
    'a mode drain during a pending receive is recoverable and retains '
    'the same viewer draft when the old read finally completes',
    (t) async {
      final f = Fixture();
      await t.pump();
      final module = DirectMessagesModule(f.a);
      await module.refresh();
      module.editDraft('pending same viewer draft');
      final held = f.backend.pending = Completer();
      final receive = module.receive();
      await t.pump();
      f.backend.draining = true;
      f.backend.mode++;
      f.backend.changeScope();
      f.backend.pending = null;
      held.complete([f.backend.peer]);
      final result = await receive;
      await t.pump();
      expect(result, DirectMessageReceiveResult.failed);
      expect(module.draft, 'pending same viewer draft');
      expect(module.rows, isNotEmpty);
      f.backend.draining = false;
      f.backend.changeScope();
      await t.pump();
      module.dispose();
      await f.close();
      await t.pump();
    },
  );

  for (final code in ['unavailable', 'forbidden']) {
    testWidgets(
      '$code owner failure reaches loaded views without a denial loop',
      (t) async {
        final f = Fixture();
        await t.pump();
        final module = DirectMessagesModule(f.a);
        await module.refresh();
        module.editDraft('draft');
        final lease = module.observeVisibleReception(() => true);
        f.backend.failure = code;
        f.backend.activity.add(null);
        await t.pump();
        final reads = total(f.backend.directories);
        await seconds(t, 3);
        if (code == 'forbidden') {
          expect(module.rows, isEmpty);
          expect(module.draft, isEmpty);
          expect(f.source.unread.value, 0);
        } else {
          expect(module.rows, isNotEmpty);
          expect(module.draft, 'draft');
          expect(module.directoryError, 'unavailable');
        }
        expect(total(f.backend.directories) - reads, lessThanOrEqualTo(1));
        lease.dispose();
        module.dispose();
        await f.close();
        await t.pump();
      },
    );
  }

  testWidgets('foreign sessions cannot consume a directory offer and disposed '
      'owners cannot serve old views', (t) async {
    final f = Fixture();
    await t.pump();
    final foreignBackend = Backend();
    final foreign = f.source.borrow(Port(foreignBackend, 'foreign'));
    await expectLater(foreign.directory(), throwsA(isA<DirectReadFailure>()));
    expect(foreignBackend.directories, isEmpty);
    f.source.dispose();
    await expectLater(f.a.directory(), throwsA(isA<DirectReadFailure>()));
    await foreign.close();
    await foreignBackend.close();
    await f.close();
    await t.pump();
  });

  testWidgets('healthy app unread plus main and detached owners use one directory '
      'source instead of three independent read clocks', (t) async {
    final backend = Backend();
    final account = ValueNotifier(
      const AccountProjection.loading().copyWith(
        sessionState: AccountSessionState.legacySignedIn,
      ),
    );
    final source = DirectMessageRefresh(Port(backend, 'unread'), account);
    final main = DirectMessagesModule(source.borrow(Port(backend, 'main')));
    final detached = DirectMessagesModule(
      source.borrow(Port(backend, 'detached')),
    );
    await main.openFriend(backend.peer);
    await detached.openFriend(backend.peer);
    final a = main.observeVisibleReception(() => true);
    final b = detached.observeVisibleReception(() => true);
    await t.pump(const Duration(milliseconds: 1));
    final start = total(backend.directories);
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(seconds: 1));
      await t.pump();
    }
    final count = total(backend.directories) - start;
    debugPrint(
      'MESSAGE_RECEPTION_COUNTS healthy=true virtualSeconds=60 directory=$count byOwner=${backend.directories}',
    );
    final unread = source.unread.value;
    a.dispose();
    b.dispose();
    main.dispose();
    detached.dispose();
    source.dispose();
    account.dispose();
    await backend.close();
    await t.pump();
    expect(
      count,
      lessThanOrEqualTo(1),
      reason: 'Healthy delivery must not keep a separate global unread poll or duplicate each viewport directory.',
    );
    expect(unread, 2);
    expect(
      backend.histories['unread'],
      isNull,
      reason: 'The shared background owner may not fetch private history.',
    );
  });
}
