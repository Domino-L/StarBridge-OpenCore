import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';

import 'friends_test.dart' show ready;

import 'social_layout_test.dart' show app;

void main() {
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
