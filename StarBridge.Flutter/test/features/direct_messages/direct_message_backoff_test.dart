import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_direct_messages_test.dart' as wire;
import 'direct_message_live_delivery_test.dart' show IncomingPort;
import 'direct_messages_test.dart' as fixtures;

class FallbackPort extends IncomingPort
    implements DirectMessageActivityHealthPort {
  int directoryReads = 0;
  bool healthy = false;
  String? directoryFailure;
  bool rotateTargets = false;
  String reference = 'peer';
  final contexts = StreamController<void>.broadcast(sync: true);
  int cancellations = 0;
  @override
  Stream<void> get invalidations => contexts.stream;
  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<void> close() async {
    await contexts.close();
    await super.close();
  }

  @override
  Conversation get peer => Conversation(
    reference,
    'Peer',
    '',
    time,
    0,
    'friend',
    conversationKey: rotateTargets ? 'fixture-scope-peer' : null,
  );
  @override
  bool get activityHealthy => healthy;
  @override
  Future<List<Conversation>> directory() {
    directoryReads++;
    if (directoryFailure != null) {
      throw DirectReadFailure(directoryFailure!);
    }
    if (!rotateTargets) return super.directory();
    return Future.value([
      Conversation(
        'lease-$directoryReads',
        peer.name,
        peer.preview,
        peer.time,
        peer.unread,
        peer.state,
        conversationKey: peer.conversationKey,
      ),
    ]);
  }
}

void report(String phase, FallbackPort port, int directory, int history) {
  debugPrint(
    'DM_FALLBACK_COUNTS ${jsonEncode({'phase': phase, 'virtualSeconds': 60, 'directory': port.directoryReads - directory, 'history': port.reads - history})}',
  );
}

class RotatingBridgeHarness extends wire.Harness {
  int directories = 0, histories = 0;
  @override
  Future<void> reply(BridgeEnvelope request) {
    if (request.name == 'account.getCurrent') return super.reply(request);
    final Map<String, Object?> payload;
    if (!request.payload.containsKey('targetRef')) {
      directories++;
      payload = wire.directory();
      final row = (payload['conversations'] as List).single as Map;
      row['targetRef'] = directories.toRadixString(16).padLeft(32, '0');
      row['conversationKey'] = 'A' * 64;
    } else {
      histories++;
      payload = wire.history()..['targetRef'] = request.payload['targetRef'];
      if ((request.payload['after'] as int? ?? 0) > 0) {
        payload['messages'] = [];
        payload['oldestSequence'] = 0;
      }
    }
    return connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: request.accountContext,
        status: 'ok',
        payload: payload,
      ),
    );
  }
}

Future<DirectMessagesModule> mount(
  WidgetTester t,
  FallbackPort port, {
  ValueNotifier<bool>? visible,
}) async {
  final module = DirectMessagesModule(port);
  addTearDown(module.dispose);
  final viewport = visible ?? ValueNotifier(true);
  if (visible == null) addTearDown(viewport.dispose);
  await module.openFriend(port.peer);
  final base = fixtures.app(const Locale('en'), () => port) as MaterialApp;
  await t.pumpWidget(
    MaterialApp(
      theme: base.theme,
      locale: base.locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: viewport,
          builder: (_, active, child) =>
              NativeViewportScope(active: active, child: child!),
          child: DirectMessagesPage(
            createPort: () => port,
            sharedModule: module,
            onBack: () {},
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return module;
}

Future<void> seconds(WidgetTester t, int count) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(seconds: 1));
    await t.pump();
  }
}

void main() {
  testWidgets('late old-context receive cannot overwrite a new conversation or '
      'its draft', (t) async {
    final port = FallbackPort();
    final module = await mount(t, port);
    final old = Completer<DirectPage>();
    port.pending = old;
    await seconds(t, 1);
    port.pending = null;
    port.reference = 'new-context-peer';
    port.contexts.add(null);
    await t.pump();
    await module.openFriend(port.peer);
    module.editDraft('New-context draft');
    old.complete(
      DirectPage(
        'peer',
        [
          DirectMessage(
            1,
            'old-context-message',
            true,
            'Retired fixture',
            port.time,
            null,
          ),
        ],
        1,
        1,
        false,
        'friend',
      ),
    );
    await t.pump();
    expect(module.selected!.ref, 'new-context-peer');
    expect(module.messages, isEmpty);
    expect(module.draft, 'New-context draft');
    expect(module.rows.single.ref, 'new-context-peer');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('hard context invalidation retires the healthy quiet schedule', (
    t,
  ) async {
    final port = FallbackPort()..healthy = true;
    final module = await mount(t, port);
    await seconds(t, 10);
    final before = port.directoryReads;
    port.reference = 'new-context-peer';
    port.contexts.add(null);
    await t.pump();
    await module.openFriend(port.peer);
    await seconds(t, 1);
    expect(
      port.directoryReads,
      before + 2,
      reason: 'The new context refreshes and admits its own catch-up.',
    );
    final caughtUp = port.directoryReads;
    await seconds(t, 30);
    expect(port.directoryReads, caughtUp);
    expect(module.selected!.ref, 'new-context-peer');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('last viewport release does not cancel a borrowed module read', (
    t,
  ) async {
    final port = FallbackPort();
    final module = await mount(t, port);
    module.editDraft('Keep detached-read draft');
    final pending = Completer<DirectPage>();
    port.pending = pending;
    await seconds(t, 1);
    final cancellations = port.cancellations;
    await t.pumpWidget(const SizedBox());
    expect(port.cancellations, cancellations);
    pending.complete(DirectPage(port.peer.ref, [], 0, 0, false, 'friend'));
    await t.pump();
    expect(module.selected!.ref, port.peer.ref);
    expect(module.draft, 'Keep detached-read draft');
    final before = port.reads;
    await seconds(t, 30);
    expect(port.reads, before);
  });

  testWidgets('after sustained idle, degraded delivery still catches up within '
      'eight seconds without a push event', (t) async {
    final port = FallbackPort();
    final module = await mount(t, port);
    await seconds(t, 46);
    port.arrived = true;
    await seconds(t, 8);
    await t.pumpWidget(const SizedBox());
    expect(module.messages.single.text, 'Incoming fixture');
    expect(module.selected!.ref, port.peer.ref);
  });

  testWidgets('production Bridge adapter keeps fresh account reads and rotating '
      'targets while unchanged polling backs off', (t) async {
    final harness = RotatingBridgeHarness();
    final module = DirectMessagesModule(harness.adapter);
    addTearDown(() async {
      module.dispose();
      await harness.close();
    });
    await module.refresh();
    await module.open(module.rows.single);
    final selectedRef = module.selected!.ref;
    final lease = module.observeVisibleReception(() => true);
    final directories = harness.directories, histories = harness.histories;
    final roots = harness.requests
        .where((r) => r.name == 'account.getCurrent')
        .length;
    await seconds(t, 60);
    lease.dispose();
    final directoryReads = harness.directories - directories;
    final historyReads = harness.histories - histories;
    final accountReads =
        harness.requests.where((r) => r.name == 'account.getCurrent').length -
        roots;
    debugPrint(
      'DM_FALLBACK_COUNTS ${jsonEncode({'phase': 'bridge-capability-rotation', 'virtualSeconds': 60, 'directory': directoryReads, 'history': historyReads, 'accountRoots': accountReads})}',
    );
    expect(directoryReads, inInclusiveRange(4, 10));
    expect(historyReads, directoryReads);
    expect(
      accountReads,
      directoryReads + historyReads,
      reason: 'Completed account responses must never become a polling cache.',
    );
    expect(module.selected!.ref, selectedRef);
    expect(module.rows.single.ref, isNot(selectedRef));
    expect(module.messages.single.id, 'message-1');
    expect(module.rows.single.conversationKey, 'A' * 64);
    expect(await module.receive(), DirectMessageReceiveResult.unchanged);
  });

  testWidgets(
    'two visible borrowers share one clock and last release stops it',
    (t) async {
      final port = FallbackPort();
      final module = await mount(t, port);
      final other = module.observeVisibleReception(() => true);
      final directories = port.directoryReads, histories = port.reads;
      await seconds(t, 60);
      report('two-borrowers', port, directories, histories);
      expect(port.directoryReads - directories, inInclusiveRange(4, 10));
      expect(port.reads - histories, port.directoryReads - directories);
      await t.pumpWidget(const SizedBox());
      final before = port.reads;
      await seconds(t, 30);
      expect(
        port.reads,
        greaterThan(before),
        reason: 'The other borrower still owns reception.',
      );
      other.dispose();
      final stopped = port.reads;
      await seconds(t, 30);
      expect(port.reads, stopped);
    },
  );

  testWidgets('a disposed owner cannot register a new receive timer', (
    t,
  ) async {
    final port = FallbackPort();
    final module = DirectMessagesModule(port);
    await module.openFriend(port.peer);
    module.dispose();
    final before = port.reads;
    final lease = module.observeVisibleReception(() => true);
    lease.wake();
    await seconds(t, 60);
    lease.dispose();
    expect(port.directoryReads, 0);
    expect(port.reads, before);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'resume catches up immediately while paused time makes no reads',
    (t) async {
      final port = FallbackPort();
      final module = await mount(t, port);
      module.editDraft('Keep resume draft');
      await seconds(t, 40);
      final before = port.reads;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await seconds(t, 30);
      expect(port.reads, before);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(port.reads, before + 1);
      expect(module.draft, 'Keep resume draft');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'restored push health revalidates once then resumes bounded fallback',
    (t) async {
      final port = FallbackPort();
      await mount(t, port);
      await seconds(t, 40);
      final before = port.reads;
      port.healthy = true;
      await seconds(t, 1);
      expect(port.reads, before + 1);
      final caughtUp = port.reads;
      await seconds(t, 60);
      expect(
        port.reads,
        caughtUp + 1,
        reason: 'Healthy push reconciles once per minute after catch-up.',
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unhealthy visible chat backs off unchanged reads over 60 seconds '
    'without dropping the selected conversation or draft',
    (t) async {
      final port = FallbackPort();
      final module = await mount(t, port);
      module.editDraft('Unsent local fixture');
      final directory = port.directoryReads, history = port.reads;
      await seconds(t, 60);
      final result = (
        directory: port.directoryReads - directory,
        history: port.reads - history,
      );
      report('unchanged', port, directory, history);
      await t.pumpWidget(const SizedBox());
      expect(
        result.directory,
        lessThanOrEqualTo(10),
        reason: 'Push downtime must not trigger 60 unchanged directory reads.',
      );
      expect(
        result.history,
        lessThanOrEqualTo(10),
        reason:
            'The visible unchanged history must back off with its directory.',
      );
      expect(result.directory, greaterThanOrEqualTo(4));
      expect(result.history, result.directory);
      expect(module.selected!.ref, port.peer.ref);
      expect(module.draft, 'Unsent local fixture');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('history failures back off even when the directory succeeds', (
    t,
  ) async {
    final port = FallbackPort();
    final module = await mount(t, port);
    module.editDraft('Keep failed-receive draft');
    port.fail = true;
    final directory = port.directoryReads, history = port.reads;
    await seconds(t, 60);
    report('history-failed', port, directory, history);
    await t.pumpWidget(const SizedBox());
    expect(port.reads - history, inInclusiveRange(4, 6));
    expect(port.directoryReads - directory, port.reads - history);
    expect(module.selected!.ref, port.peer.ref);
    expect(module.draft, 'Keep failed-receive draft');
  });

  testWidgets(
    'directory failure backs off without suppressing available history',
    (t) async {
      final port = FallbackPort();
      final module = await mount(t, port);
      module.editDraft('Keep directory-failure draft');
      port.directoryFailure = 'unavailable';
      final directory = port.directoryReads, history = port.reads;
      await seconds(t, 60);
      report('directory-failed', port, directory, history);
      await t.pumpWidget(const SizedBox());
      expect(port.directoryReads - directory, inInclusiveRange(4, 6));
      expect(port.reads - history, port.directoryReads - directory);
      expect(module.rows, isNotEmpty);
      expect(module.draft, 'Keep directory-failure draft');
    },
  );

  testWidgets('rotating read capabilities with the same scoped conversation '
      'do not reset unchanged fallback', (t) async {
    final port = FallbackPort()..rotateTargets = true;
    final module = await mount(t, port);
    final selected = module.selected;
    final directory = port.directoryReads, history = port.reads;
    await seconds(t, 60);
    report('capability-rotation', port, directory, history);
    await t.pumpWidget(const SizedBox());
    expect(port.directoryReads - directory, lessThanOrEqualTo(10));
    expect(port.reads - history, port.directoryReads - directory);
    expect(
      module.selected!.ref,
      selected!.ref,
      reason:
          'Directory capability rotation must not replace the history cursor.',
    );
    expect(module.rows.single.ref, isNot(selected.ref));
    expect(module.rows.single.conversationKey, selected.conversationKey);
  });

  testWidgets('one pending history has no overlapping or queued timer reads', (
    t,
  ) async {
    final port = FallbackPort();
    await mount(t, port);
    port.pending = Completer();
    final directory = port.directoryReads, history = port.reads;
    await seconds(t, 15);
    expect(port.directoryReads - directory, 1);
    expect(port.reads - history, 1);
    port.pending!.complete(
      DirectPage(port.peer.ref, [], 0, 0, false, 'friend'),
    );
    await t.pump();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('push bypasses fallback cooldown and keeps the unsent draft', (
    t,
  ) async {
    final port = FallbackPort();
    final module = await mount(t, port);
    module.editDraft('Keep push draft');
    await seconds(t, 40);
    final history = port.reads;
    port.arrived = true;
    port.activity.add(null);
    await t.pump();
    expect(port.reads, history + 1);
    expect(module.messages.single.text, 'Incoming fixture');
    expect(module.rows.length, 2);
    expect(module.draft, 'Keep push draft');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('visibility pauses reads and return catches up within one tick', (
    t,
  ) async {
    final port = FallbackPort();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await mount(t, port, visible: visible);
    await seconds(t, 30);
    visible.value = false;
    await t.pump();
    final directory = port.directoryReads, history = port.reads;
    await seconds(t, 60);
    expect(port.directoryReads, directory);
    expect(port.reads, history);
    visible.value = true;
    await t.pump();
    await seconds(t, 1);
    expect(port.directoryReads, directory + 1);
    expect(port.reads, history + 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('healthy fallback stays bounded and health loss catches up', (
    t,
  ) async {
    final port = FallbackPort()..healthy = true;
    await mount(t, port);
    await seconds(t, 60);
    expect(
      port.directoryReads,
      1,
      reason: 'A healthy viewport catches up once and relies on activity.',
    );
    final history = port.reads;
    port.healthy = false;
    await seconds(t, 1);
    expect(port.reads, history + 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hard denial during cooldown withdraws the old read context immediately',
    (t) async {
      final port = FallbackPort();
      final module = await mount(t, port);
      module.editDraft('Old denied context');
      await seconds(t, 40);
      port.directoryFailure = 'forbidden';
      port.activity.add(null);
      await t.pump();
      expect(module.selected, isNull);
      expect(module.rows, isEmpty);
      expect(module.messages, isEmpty);
      expect(module.draft, isEmpty);
      expect(module.error, 'forbidden');
      await t.pumpWidget(const SizedBox());
    },
  );
}
