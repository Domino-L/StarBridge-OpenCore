import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/example_friends_adapter.dart';

import 'friends_test.dart' as fixtures;

FriendsReadResult actionable() => FriendsReadResult(
  FriendsReadState.ready,
  snapshot: parseFriendsSnapshot(
    fixtures.directory()
      ..['friends'] = [
        fixtures.row('呼号')
          ..['targetRef'] = '00000000000000000000000000000001'
          ..['actions'] = ['remove', 'block'],
      ],
  ),
);

class CommandPort extends fixtures.PendingPort implements FriendsCommandPort {
  @override
  bool get commandsAvailable => true;
  final commands = <String>[];
  final reply = Completer<FriendCommandResult>();
  @override
  Future<FriendCommandResult> execute(String action, String reference) {
    commands.add('$action:$reference');
    return reply.future;
  }
}

void main() {
  for (final entry in {
    'send': ('none', FriendsSection.outgoing),
    'accept': ('incoming', FriendsSection.friends),
    'reject': ('incoming', FriendsSection.incoming),
    'cancel': ('outgoing', FriendsSection.outgoing),
    'remove': ('friend', FriendsSection.friends),
    'block': ('friend', FriendsSection.blocked),
    'unblock': ('blocked', FriendsSection.blocked),
  }.entries) {
    test(
      'example ${entry.key} confirms authoritative group and leaves a new instance untouched',
      () async {
        final module = FriendsModule(ExampleFriendsAdapter());
        if (entry.value.$1 == 'none') module.editQuery('示例用户');
        await module.refresh();
        final row = entry.value.$1 == 'none'
            ? module.rows.single
            : module.snapshot!.groups.values
                  .expand((r) => r)
                  .firstWhere((r) => r.relationship == entry.value.$1);
        if (entry.value.$1 != 'none') {
          module.select(
            module.snapshot!.groups.entries
                .firstWhere((e) => e.value.contains(row))
                .key,
          );
        }
        await module.execute(row, entry.key);
        expect(module.feedback, 'success.${entry.key}');
        expect(module.section, entry.value.$2);
        expect(module.query, isEmpty);
        expect(module.canExecute(row, entry.key), isFalse);
        final other = FriendsModule(ExampleFriendsAdapter());
        await other.refresh();
        expect(other.snapshot!.groups[FriendsSection.friends], hasLength(1));
        module.dispose();
        other.dispose();
      },
    );
  }
  test('unknown result blocks repeats; no optimistic relation change or hidden refresh', () async {
    final port = CommandPort();
    final module = FriendsModule(port);
    final read = module.refresh();
    port.requests.single.complete(actionable());
    await read;
    final row = module.rows.single;
    final action = module.execute(row, 'remove');
    expect(module.busy, isTrue);
    expect(module.rows.single, same(row));
    await module.execute(row, 'remove');
    module.select(FriendsSection.blocked);
    module.editQuery('other');
    await module.refresh();
    expect(port.commands, hasLength(1));
    expect(port.requests, hasLength(1));
    expect(module.query, isEmpty);
    port.reply.complete(
      const FriendCommandResult('unknown', error: 'outcomeUnknown'),
    );
    await action;
    expect(module.snapshot, isNull);
    expect(module.feedback, 'outcomeUnknown');
    expect(module.state, FriendsReadState.unavailable);
    await module.execute(row, 'remove');
    expect(port.commands, hasLength(1));
    module.dispose();
  });
  test('command completion cannot restore a signed-out account', () async {
    final port = CommandPort();
    final module = FriendsModule(port);
    final read = module.refresh();
    port.requests.single.complete(actionable());
    await read;
    final action = module.execute(module.rows.single, 'remove');
    port.events.add(null);
    port.requests.last.complete(
      const FriendsReadResult(FriendsReadState.signedOut),
    );
    port.reply.complete(
      FriendCommandResult(
        'accepted',
        directory: fixtures.ready('old').snapshot,
      ),
    );
    await action;
    await Future<void>.delayed(Duration.zero);
    expect(module.state, FriendsReadState.signedOut);
    expect(module.feedback, isNull);
    expect(module.snapshot, isNull);
    module.dispose();
  });
  test('actions require a current opaque reference and match the relation', () {
    for (final bad in [
      fixtures.row('x')..['actions'] = ['remove'],
      fixtures.row('x')
        ..['targetRef'] = '00000000000000000000000000000001'
        ..['actions'] = ['accept'],
      fixtures.row('x')
        ..['targetRef'] = 'private-id'
        ..['actions'] = ['remove'],
    ]) {
      expect(
        () => parseFriendsSnapshot(fixtures.directory()..['friends'] = [bad]),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'remove and block require explicit confirmation; cancel preserves relationship',
    (tester) async {
      await tester.pumpWidget(
        fixtures.page(const Locale('zh', 'CN'), ExampleFriendsAdapter.new),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('不影响真实好友'), findsOneWidget);
      await tester.tap(find.text('删除好友'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不会改变对方资料或舰队关系'), findsOneWidget);
      await tester.tap(find.text('保留好友'));
      await tester.pumpAndSettle();
      expect(find.text('示例好友 (Example)'), findsOneWidget);
      await tester.tap(find.text('屏蔽用户'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, '屏蔽用户'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('用户已屏蔽。'), findsOneWidget);
      expect(find.text('解除屏蔽'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'switching account dismisses confirmation and clears the old identity',
    (tester) async {
      final port = CommandPort();
      await tester.pumpWidget(
        fixtures.page(const Locale('zh', 'CN'), () => port),
      );
      for (var i = 0; i < 10 && port.requests.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      port.requests.single.complete(actionable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除好友'));
      await tester.pumpAndSettle();
      port.events.add(null);
      port.requests.last.complete(
        const FriendsReadResult(FriendsReadState.signedOut),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('呼号 (Example)'), findsNothing);
      expect(port.commands, isEmpty);
      expect(find.textContaining('登录 SCM'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
