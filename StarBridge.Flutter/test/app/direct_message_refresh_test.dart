import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/direct_message_refresh.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

final class InboxPort implements DirectMessagesPort, DirectMessageActivityPort {
  final activity = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => activity.stream;
  final events = StreamController<void>.broadcast();
  int reads = 0, cancels = 0, histories = 0;
  bool fail = false, closed = false;
  Completer<List<Conversation>>? pending;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() async {
    reads++;
    if (fail) throw const DirectReadFailure('unavailable');
    return pending == null ? [] : await pending!.future;
  }
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) async {
    histories++; throw StateError('Background source must not read history');
  }
  @override
  void cancel() { cancels++; }
  @override
  Future<void> close() async { closed = true; await events.close(); await activity.close(); }
}

void main() {
  final signedOut = const AccountProjection.loading().copyWith(sessionState: AccountSessionState.signedOut);
  final signedIn = signedOut.copyWith(sessionState: AccountSessionState.legacySignedIn);
  testWidgets('invalidated pending directory cannot restore former account unread', (tester) async {
    final account = ValueNotifier(signedIn);
    final port = InboxPort()..pending = Completer();
    final source = DirectMessageRefresh(port, account);
    await tester.pump(const Duration(milliseconds: 1));
    final old = port.pending!;
    port.events.add(null);
    await tester.pump();
    port.pending = null;
    old.complete([Conversation('old', 'Old', '', DateTime.utc(2026), 9, 'friend')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.unread.value, 0);
    expect(port.reads, 2);
    source.dispose(); account.dispose();
    await tester.pump();
  });
  testWidgets('global unread follows directory without opening friends and clears on logout', (tester) async {
    final account = ValueNotifier(signedIn);
    final port = InboxPort()..pending = Completer();
    final source = DirectMessageRefresh(port, account);
    await tester.pump(const Duration(milliseconds: 1));
    port.pending!.complete([
      Conversation('peer', 'Peer', '', DateTime.utc(2026), 2, 'friend'),
    ]);
    await tester.pump();
    expect(source.unread.value, 2);
    account.value = signedOut;
    expect(source.unread.value, 0);
    source.dispose(); account.dispose();
    await tester.pump();
  });
  testWidgets('activity wake bypasses polling and queues a change during an active read', (tester) async {
    final account = ValueNotifier(signedIn);
    final port = InboxPort();
    final source = DirectMessageRefresh(port, account);
    await tester.pump(const Duration(milliseconds: 1));
    expect(port.reads, 1);
    port.pending = Completer();
    port.activity.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(port.reads, 2);
    port.activity.add(null);
    await tester.pump();
    final pending = port.pending!;
    port.pending = null;
    pending.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(port.reads, 3);
    source.dispose(); account.dispose();
    await tester.pump();
  });
  testWidgets('app lifetime inbox refresh is read-only, serialized and stopped on logout', (tester) async {
    final account = ValueNotifier(signedOut);
    final port = InboxPort();
    final source = DirectMessageRefresh(port, account);
    await tester.pump(const Duration(seconds: 30));
    expect(port.reads, 0);
    account.value = signedIn;
    await tester.pump(const Duration(milliseconds: 1));
    expect(port.reads, 1);
    port.pending = Completer();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 45));
    expect(port.reads, 2);
    account.value = signedOut;
    port.pending!.complete([]);
    await tester.pump(const Duration(seconds: 30));
    expect(port.reads, 2);
    expect(port.histories, 0);
    expect(port.cancels, greaterThan(0));
    source.dispose(); account.dispose();
    await tester.pump();
    expect(port.closed, isTrue);
  });
  testWidgets('failed inbox reads back off and disposal cancels the timer', (tester) async {
    final account = ValueNotifier(signedIn);
    final port = InboxPort()..fail = true;
    final source = DirectMessageRefresh(port, account);
    await tester.pump(const Duration(milliseconds: 1));
    expect(port.reads, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(port.reads, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(port.reads, 2);
    source.dispose(); account.dispose();
    await tester.pump(const Duration(minutes: 3));
    expect(port.reads, 2);
  });
}
