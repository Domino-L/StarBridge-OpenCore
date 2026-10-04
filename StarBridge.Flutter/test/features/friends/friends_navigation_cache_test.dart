import 'dart:async';

import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';

import 'friends_test.dart' show ready;
import '../direct_messages/direct_message_live_delivery_test.dart'
    show IncomingPort;

import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';

import 'social_layout_test.dart' show app;

void main() {
  testWidgets(
    'disposing outgoing chat cannot clear incoming viewport ownership',
    (tester) async {
      final owner = FriendsModule(CountingFriends());
      addTearDown(owner.dispose);
      final port = IncomingPort();
      final messages = owner.chat(() => port);
      Widget chat(String key) => DirectMessagesPage(
        key: ValueKey(key),
        createPort: () => port,
        sharedModule: messages,
        onBack: () {},
      );
      await tester.pumpWidget(app(Stack(children: [chat('old')])));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(Stack(children: [chat('old'), chat('new')])));
      await tester.pumpAndSettle();
      final incoming = messages.isViewportCurrent;
      expect(incoming, isNotNull);
      await tester.pumpWidget(app(Stack(children: [chat('new')])));
      await tester.pumpAndSettle();
      expect(messages.isViewportCurrent, same(incoming));
      await tester.pumpWidget(const SizedBox());
      expect(messages.isViewportCurrent, isNull);
    },
  );
  testWidgets(
    'friends recent entry routes to independent messages and retains draft',
    (tester) async {
      final model = FriendsModule(CountingFriends());
      addTearDown(model.dispose);
      final chat = IncomingPort();
      final messages = model.chat(() => chat);
      await messages.openFriend(chat.peer);
      messages.editDraft('retained draft');
      String? route;
      await tester.pumpWidget(
        app(
          Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (intent) {
                  route = intent.route;
                  return null;
                },
              ),
            },
            child: FriendsPage(
              createPort: () => throw StateError('shared'),
              module: model,
              createChatPort: () => chat,
              separateMessages: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('friends-recent')));
      await tester.pumpAndSettle();
      expect(route, '/messages');
      expect(find.byType(DirectMessagesPage), findsNothing);
      expect(messages.draft, 'retained draft');
      await tester.pumpWidget(
        app(
          FriendsPage(
            createPort: () => throw StateError('shared'),
            module: model,
            createChatPort: () => chat,
            separateMessages: true,
            messagesOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DirectMessagesPage), findsOneWidget);
      expect(messages.draft, 'retained draft');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'returning to friends locates new unread without losing retained chat draft',
    (tester) async {
      final model = FriendsModule(CountingFriends());
      addTearDown(model.dispose);
      final chat = IncomingPort();
      final messages = model.chat(() => chat);
      await messages.openFriend(chat.peer);
      messages.editDraft('keep unsent draft');
      chat.arrived = true;
      await tester.pumpWidget(
        app(
          FriendsPage(
            createPort: () => throw StateError('shared'),
            module: model,
            createChatPort: () => chat,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final badge = find.descendant(
        of: find.byKey(const Key('friends-recent')),
        matching: find.byType(AttentionCount),
      );
      expect(tester.widget<AttentionCount>(badge).count, 1);
      expect(messages.selected?.ref, 'peer');
      expect(messages.draft, 'keep unsent draft');
      chat.arrived = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(tester.widget<AttentionCount>(badge).count, 0);
      expect(messages.selected?.ref, 'peer');
      expect(messages.draft, 'keep unsent draft');
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'prefetch warms the shared snapshot without submitting uncommitted search',
    () async {
      final port = CountingFriends();
      final model = FriendsModule(port);
      addTearDown(model.dispose);
      await model.prefetch();
      await model.enter();
      expect(port.reads, 1);
      model.editQuery('Unsubmitted');
      await model.prefetch();
      expect(port.reads, 1);
      expect(model.query, 'Unsubmitted');
    },
  );

  test('ten quick returns reuse one read but expiry and explicit refresh remain fresh', () async {
    final port = CountingFriends();
    var now = DateTime(2026);
    final model = FriendsModule(port, now: () => now);
    addTearDown(model.dispose);
    await model.enter();
    for (var i = 0; i < 10; i++) {
      await model.enter();
    }
    expect(port.reads, 1);
    now = now.add(const Duration(seconds: 10));
    await model.enter();
    expect(port.reads, 2);
    await model.refresh();
    expect(port.reads, 3);
    now = now.subtract(const Duration(seconds: 1));
    await model.enter();
    expect(port.reads, 4);
    port.events.add(null);
    expect(model.snapshot, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 5);
  });

  test('unused shared friend module does not add startup reads; failures are not cached', () async {
    final port = CountingFriends();
    final model = FriendsModule(port);
    addTearDown(model.dispose);
    port.events.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 0);
    port.fail = true;
    await model.enter();
    await model.enter();
    expect(port.reads, 2);
    expect(model.snapshot, isNull);
    port.fail = false;
    await model.enter();
    expect(port.reads, 3);
  });

  testWidgets(
    'friend page return reuses the shared snapshot and hidden viewport pauses polls',
    (tester) async {
      final port = CountingFriends();
      final model = FriendsModule(port);
      addTearDown(model.dispose);
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      final page = FriendsPage(
        createPort: () =>
            throw StateError('Shared page must not create another port'),
        module: model,
      );
      Widget show() => app(
        ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, value, _) =>
              NativeViewportScope(active: value, child: page),
        ),
      );
      await tester.pumpWidget(show());
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(show());
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      active.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(port.reads, 1);
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(port.reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('product friend destination retains search on a quick return', (
    tester,
  ) async {
    final composition = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    addTearDown(composition.dispose);
    final friends = composition.features.byRoute('/friends');
    await tester.pumpWidget(app(Builder(builder: friends.buildDestination)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Explorer');
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(Builder(builder: friends.buildDestination)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Explorer',
    );
    await tester.pumpWidget(const SizedBox());
  });
}

class CountingFriends implements FriendsPort {
  final events = StreamController<void>.broadcast(sync: true);
  int reads = 0;
  bool fail = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) async {
    reads++;
    return fail
        ? const FriendsReadResult(FriendsReadState.unavailable)
        : ready('Example', query: query);
  }

  @override
  void cancelPending() {}
  @override
  Future<void> close() => events.close();
}
