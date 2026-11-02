import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import 'direct_messages_test.dart' as fixtures;

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'directory retry retains visible history and draft in $locale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(960, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final port = _RefreshPort();
        final module = await _open(port);
        addTearDown(module.dispose);
        final base = fixtures.app(locale, () => port) as MaterialApp;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: base.supportedLocales,
            localizationsDelegates: base.localizationsDelegates,
            theme: base.theme,
            home: Scaffold(
              body: DirectMessagesPage(
                createPort: () => port,
                sharedModule: module,
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final historyKey = ValueKey(module.selected!.ref);
        final history = tester.widget<ListView>(find.byKey(historyKey));
        final controller = history.controller!;
        final offset = controller.offset;
        final draftRevision = module.draftRevision;
        final reply = Completer<List<Conversation>>();
        port.nextDirectory = reply;
        final refreshing = module.refresh();
        await tester.pump();
        expect(find.byKey(historyKey), findsOneWidget);
        expect(find.text('synthetic unsaved draft'), findsOneWidget);
        expect(controller.offset, offset);
        expect(module.draftRevision, draftRevision);
        reply.completeError(const DirectReadFailure('unavailable'));
        await refreshing;
        await tester.pumpAndSettle();
        expect(find.byKey(historyKey), findsOneWidget);
        expect(find.text('synthetic unsaved draft'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-directory-sync-failed')),
          findsOneWidget,
        );
        expect(find.textContaining('{time}'), findsNothing);
        expect(controller.offset, offset);
        expect(tester.takeException(), isNull);
        port.directoryFailure = null;
        await tester.tap(find.byKey(const ValueKey('chat-refresh-directory')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-directory-sync-failed')),
          findsNothing,
        );
        expect(find.text('synthetic unsaved draft'), findsOneWidget);
        expect(find.byKey(historyKey), findsOneWidget);
        expect(controller.offset, offset);
        expect(module.draftRevision, draftRevision);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'directory refresh retains the open chat, draft, history and viewport',
    () async {
      final port = _RefreshPort();
      final module = await _open(port);
      addTearDown(module.dispose);
      final selected = module.selected!.ref;
      final messages = module.messages;
      final reply = Completer<List<Conversation>>();
      port.nextDirectory = reply;
      addTearDown(() {
        if (!reply.isCompleted) reply.complete(const []);
      });
      final refreshing = module.refresh();
      expect(module.draft, 'synthetic unsaved draft');
      expect(module.selected?.ref, selected);
      expect(module.messages, same(messages));
      expect(module.scrollOffset, 144);
      expect(module.loaded, isTrue);
      expect(module.busy, isFalse);
      reply.complete(await port.base.directory());
      await refreshing;
      expect(module.draft, 'synthetic unsaved draft');
      expect(module.selected?.ref, selected);
      expect(module.messages, same(messages));
      expect(module.scrollOffset, 144);
    },
  );

  test(
    'a transient directory failure retains cached rows and unsaved input',
    () async {
      final port = _RefreshPort();
      final module = await _open(port);
      addTearDown(module.dispose);
      final messages = module.messages;
      final selected = module.selected!.ref;
      port.directoryFailure = const DirectReadFailure('unavailable');
      await module.refresh();
      expect(module.rows, isNotEmpty);
      expect(module.loaded, isTrue);
      expect(module.selected?.ref, selected);
      expect(module.messages, same(messages));
      expect(module.draft, 'synthetic unsaved draft');
      expect(module.scrollOffset, 144);
      expect(module.rows.every((row) => row.presence == null), isTrue);
    },
  );

  test(
    'refresh cannot discard an outgoing message awaiting confirmation',
    () async {
      final port = _RefreshPort()..unknownSend = true;
      final module = await _open(port);
      addTearDown(module.dispose);
      await module.send();
      await pumpEventQueue();
      expect(module.outgoing.single.text, 'synthetic unsaved draft');
      await module.refresh();
      expect(module.outgoing.single.text, 'synthetic unsaved draft');
      expect(port.sends, 1);
    },
  );

  test(
    'overlapping refresh calls do not duplicate the directory transport',
    () async {
      final port = _RefreshPort();
      final module = await _open(port);
      addTearDown(module.dispose);
      final baseline = port.directoryReads;
      final reply = Completer<List<Conversation>>();
      port.nextDirectory = reply;
      final first = module.refresh();
      final second = module.refresh();
      reply.complete(await port.base.directory());
      await Future.wait([first, second]);
      expect(port.directoryReads, baseline + 1);
    },
  );

  test(
    'account invalidation discards view state and ignores a late old directory',
    () async {
      final port = _RefreshPort();
      final module = await _open(port);
      addTearDown(module.dispose);
      final oldRows = module.rows;
      final reply = Completer<List<Conversation>>();
      port.nextDirectory = reply;
      final refreshing = module.refresh();
      port.directoryValue = const [];
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      reply.complete(oldRows);
      await refreshing;
      expect(module.rows, isEmpty);
      expect(module.messages, isEmpty);
      expect(module.selected, isNull);
      expect(module.draft, isEmpty);
      expect(module.scrollOffset, 0);
    },
  );

  test(
    'leaving a chat during refresh cannot strand the synchronization flag',
    () async {
      final port = _RefreshPort();
      final module = await _open(port);
      addTearDown(module.dispose);
      final reply = Completer<List<Conversation>>();
      port.nextDirectory = reply;
      final refreshing = module.refresh();
      expect(module.directoryRefreshing, isTrue);
      module.back();
      reply.complete(await port.base.directory());
      await refreshing;
      expect(module.directoryRefreshing, isFalse);
      expect(module.busy, isFalse);
      expect(module.selected, isNull);
    },
  );

  for (final failure in [
    'forbidden',
    'identity_unavailable',
    'target_changed',
  ]) {
    test(
      '$failure directory failure discards inaccessible cached conversations',
      () async {
        final port = _RefreshPort();
        final module = await _open(port);
        addTearDown(module.dispose);
        port.directoryFailure = DirectReadFailure(failure);
        await module.receive(directoryOnly: true);
        expect(module.rows, isEmpty);
        expect(module.messages, isEmpty);
        expect(module.selected, isNull);
        expect(module.canSend, isFalse);
        expect(module.error, failure);
      },
    );
  }
}

Future<DirectMessagesModule> _open(_RefreshPort port) async {
  final module = DirectMessagesModule(port);
  await module.refresh();
  await module.open(module.rows.first);
  module.editDraft('synthetic unsaved draft');
  module.scrollOffset = 144;
  return module;
}

final class _RefreshPort implements DirectMessagesPort, DirectMessageSender {
  final base = ExampleDirectMessages();
  final events = StreamController<void>.broadcast(sync: true);
  Completer<List<Conversation>>? nextDirectory;
  List<Conversation>? directoryValue;
  Object? directoryFailure;
  int directoryReads = 0, sends = 0;
  bool unknownSend = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() {
    directoryReads++;
    final pending = nextDirectory;
    nextDirectory = null;
    if (pending != null) return pending.future;
    if (directoryFailure case final Object failure) {
      return Future.error(failure);
    }
    return directoryValue == null
        ? base.directory()
        : Future.value(directoryValue);
  }

  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) =>
      base.history(ref, before: before, after: after);
  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) {
    sends++;
    return unknownSend
        ? Future.value(const DirectSendResult('unknown'))
        : base.send(ref, text, clientMessageId);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}
