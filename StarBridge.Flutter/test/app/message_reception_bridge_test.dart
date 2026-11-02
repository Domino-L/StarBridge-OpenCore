import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/composition/direct_message_refresh.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../features/direct_messages/bridge_direct_messages_test.dart' as wire;

class Host extends wire.Harness implements NativeHostLease {
  final _terminated = Completer<NativeHostTermination>();
  bool closed = false;
  @override
  Future<NativeHostTermination> get terminated => _terminated.future;
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await super.close();
  }
}

ValueNotifier<AccountProjection> account(int generation) => ValueNotifier(
  const AccountProjection.loading().copyWith(
    generation: generation,
    sessionState: AccountSessionState.signedIn,
  ),
);

void main() {
  testWidgets('disposing reception fences new borrowed writes without closing '
      'the independent view transport', (t) async {
    final h = wire.Harness(sendCapability: true, receiptCapability: true),
        projection = account(4);
    final owner = DirectMessageRefresh(
      BridgeDirectMessages(h.session),
      projection,
    );
    final raw = BridgeDirectMessages(h.session), view = owner.borrow(raw);
    expect((view as DirectMessageSender).supportsSending, true);
    owner.dispose();
    final start = h.requests.length;
    final sending = (view as DirectMessageSender).supportsSending;
    final receipts = (view as DirectReadReceiptPort).supportsReadReceipts;
    final result = await (view as DirectMessageSender).send(
      wire.reference,
      'fixture',
      wire.reference,
    );
    await t.pump();
    final writes = h.requests
        .skip(start)
        .where((request) => request.name == 'directMessages.send')
        .length;
    await t.runAsync(() async {
      await view.close();
      await h.close();
    });
    projection.dispose();
    await t.pump();
    expect(sending, false);
    expect(receipts, false);
    expect(result.status, 'rejected');
    expect(writes, 0);
  });

  testWidgets('production factories borrow one reception owner while raw view '
      'history ports keep independent fresh account reads', (t) async {
    final host = Host();
    final preferences = InMemoryAppPreferences();
    final composition = AppComposition.forConnectedProduct(
      nativeHost: host,
      preferences: preferences,
      windowChrome: InMemoryWindowChrome(),
    );
    var initialized = false;
    final initialization = composition.account.initialize().then((value) {
      initialized = true;
      return value;
    });
    for (var i = 0; i < 100 && !initialized; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(
      initialized,
      true,
      reason:
          'Account read must complete through the normal phased metadata queue',
    );
    await initialization;
    await t.pump();
    expect(composition.account.projection.value.isSignedIn, true);
    final main = composition.createUserMessages(),
        window = composition.createWindowMessagesPort();
    expect(main, isA<DirectMessageReceptionPort>());
    expect(window, isA<DirectMessageReceptionPort>());
    final routePorts = <DirectMessagesPort>[];
    await t.pumpWidget(
      Builder(
        builder: (context) {
          for (final route in ['/friends', '/messages']) {
            final page =
                composition.features.byRoute(route).buildDestination(context)
                    as FriendsPage;
            final port = page.createChatPort!();
            routePorts.add(port);
            expect(port, isA<DirectMessageReceptionPort>());
          }
          return const SizedBox();
        },
      ),
    );
    await main.directory();
    final start = host.requests.length;
    await window.directory();
    final cycle = host.requests.skip(start).toList();
    expect(cycle.where((r) => r.name == 'account.getCurrent'), hasLength(1));
    expect(cycle.where((r) => r.name == 'directMessages.read'), hasLength(1));
    await main.history(wire.reference);
    await window.history(wire.reference);
    expect(
      host.requests.skip(start).where((r) => r.name == 'account.getCurrent'),
      hasLength(3),
    );
    // Stream subscription cancellation may complete in the root zone. Finish
    // real asynchronous teardown outside the widget test's fake timer zone.
    await t.runAsync(() async {
      await main.close();
      await window.close();
      for (final port in routePorts) {
        await port.close();
      }
    });
    composition.dispose();
    await t.pump();
    await t.runAsync(host.close);
    preferences.dispose();
    expect(t.takeException(), isNull);
  });

  testWidgets('real Bridge mode drain retires an unfinished owner read, fences '
      'offers and reconciles even when the attempted mode change is rejected', (
    t,
  ) async {
    final h = wire.Harness(hold: true), projection = account(4);
    final owner = DirectMessageRefresh(h.adapter, projection);
    final view = owner.borrow(BridgeDirectMessages(h.session));
    final read = view.directory();
    final rejected = expectLater(read, throwsA(isA<DirectReadFailure>()));
    await h.arrived.future;
    final scope = h.adapter.readScope;
    await expectLater(
      h.session.runConnectionModeChange(() async {
        expect(h.adapter.readScope, isNull);
        throw StateError('Synthetic rejected mode attempt');
      }),
      throwsStateError,
    );
    await rejected;
    await t.pump();
    expect(h.adapter.readScope, isNot(scope));
    expect(h.adapter.readScope!.transport, same(h.session));
    // A late pre-drain reply cannot restore former unread or be offered.
    await h.reply(
      h.requests.firstWhere((r) => r.name == 'directMessages.read'),
    );
    await t.pump();
    expect(owner.unread.value, 0);
    final fresh = view.directory();
    await t.pump();
    await h.reply(h.requests.lastWhere((r) => r.name == 'directMessages.read'));
    expect((await fresh).single.ref, wire.reference);
    await t.runAsync(() async {
      owner.dispose();
      projection.dispose();
      await view.close();
      await h.close();
    });
    await t.pump();
  });

  testWidgets(
    'real Native generation retires queued directory offers before the '
    'account projection admits a replacement owner',
    (t) async {
      final h = wire.Harness(), projection = account(4);
      final owner = DirectMessageRefresh(h.adapter, projection);
      final view = owner.borrow(BridgeDirectMessages(h.session));
      await view.directory();
      await t.pump();
      expect(owner.unread.value, 1);
      final changed = h.adapter.invalidations.first;
      await h.connection.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: const {},
        ),
      );
      await changed;
      await t.pump();
      final start = h.requests.length;
      await expectLater(
        (view as DirectMessageDirectoryUpdatesPort).receiveDirectory(),
        throwsA(isA<DirectReadFailure>()),
      );
      expect(owner.unread.value, 0);
      expect(
        h.requests.skip(start).where((r) => r.name == 'directMessages.read'),
        isEmpty,
      );
      projection.value = projection.value.copyWith(generation: 5);
      await view.directory();
      expect(owner.unread.value, 1);
      await t.runAsync(() async {
        owner.dispose();
        projection.dispose();
        await view.close();
        await h.close();
      });
      await t.pump();
    },
  );
}
