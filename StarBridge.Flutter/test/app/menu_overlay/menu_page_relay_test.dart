import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_page_relay.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_bridge_relay.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_requests.dart';

const _owner = BridgeAccountContext(
  environment: 'test',
  authority: 'test',
  subject: 'owner',
);

/// A Host that answers from a table and records what reached it.
final class _Host {
  _Host() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 3)
      ..acceptHostCapabilities(const {
        'marketplace.read',
        'marketplace.trade',
        'marketplace.chat',
        'tradeProfile.read',
        'tradeProfile.write',
        'account.getCurrent',
        'overlay.update',
        'officialFleet.getMembers',
        'officialFleet.governanceRole',
      });
    pair.host.incoming.listen(_answer);
  }
  late final dynamic connection;
  late final BridgeClientSession session;
  final seen = <String>[];
  final subjects = <String?>[];
  int _sequence = 0;
  Completer<void>? hold;

  Future<void> _answer(BridgeEnvelope request) async {
    seen.add(request.name);
    subjects.add(request.accountContext?.subject);
    await hold?.future;
    if (request.name == 'bridge.cancel') return;
    final payload = switch (request.name) {
      'account.getCurrent' => {
        'schemaVersion': 1,
        'state': 'signedIn',
        'profile': {'displayName': 'secret'},
      },
      'marketplace.chat' => {
        'schemaVersion': 1,
        'data': {
          'ref': 'chat-1',
          'peer': {'name': 'seller', 'userMobile': '13700000000'},
        },
      },
      'tradeProfile.read' => {
        'schemaVersion': 1,
        'data': {
          'userMobile': '13800000000',
          'orderLimit': 5,
          'nested': [
            {'userMobile': '13900000000', 'keep': 1},
          ],
        },
      },
      'officialFleet.getMembers' => {
        'schemaVersion': 1,
        'rows': [
          {'handle': 'Member', 'email': 'member@example.invalid'},
        ],
      },
      _ => {
        'schemaVersion': 1,
        'data': {'rows': <Object?>[]},
        'readAt': '2026-10-30T00:00:00Z',
      },
    };
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: request.name == 'account.getCurrent' ? _owner : null,
        payload: payload,
        status: 'ok',
      ),
    );
  }

  Future<void> event(
    String name, {
    int? generation,
    Map<String, Object?> payload = const {},
  }) => connection.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: name,
      sessionGeneration: generation ?? session.activeGeneration,
      sequence: ++_sequence,
      payload: payload,
    ),
  );
}

String _request(
  String name, {
  String id = 'menu-1',
  int generation = 3,
  Map<String, Object?> payload = const {'schemaVersion': 1},
  BridgeAccountContext? owner,
}) => jsonEncode(
  BridgeEnvelope(
    protocolVersion: 1,
    messageType: 'request',
    name: name,
    correlationId: id,
    sessionGeneration: generation,
    accountContext: owner,
    payload: payload,
  ).toJson(),
);

BridgeEnvelope _reply(Object? value) => BridgeEnvelope.fromJson(
  (jsonDecode(value! as String) as Map).cast<String, Object?>(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const primary = MethodChannel('test/primary');
  const surface = MethodChannel('test/surface');
  late _Host host;
  late MenuBridgeRelay relay;
  late List<Map<dynamic, dynamic>> published;
  var opening = 7;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> call(Map<String, Object?> args) => relay.handle(
    {'opening': opening, ...args},
    opening: opening,
    isCurrent: () => true,
  );

  setUp(() {
    host = _Host();
    published = [];
    opening = 7;
    relay = MenuBridgeRelay(host.session, mode: () => null, channel: primary);
    messenger.setMockMethodCallHandler(primary, (call) async {
      if (call.method == 'bridgeEvent') {
        published.add(call.arguments as Map);
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(primary, null);
    messenger.setMockMethodCallHandler(surface, null);
  });

  group('primary side', () {
    // The owner the relay hands the menu (opaque; the Host's subject stays).
    late BridgeAccountContext owner;
    setUp(() async {
      owner = _reply(
        await call({
          'action': 'request',
          'payload': _request('account.getCurrent', id: 'owner-read'),
        }),
      ).accountContext!;
      host.seen.clear();
    });

    test('a request outside the list never reaches the Host', () async {
      for (final name in const [
        'overlay.update',
        'tradeProfile.write',
        'account.logout',
      ]) {
        final reply = _reply(
          await call({
            'action': 'request',
            'payload': _request(name, owner: owner),
          }),
        );
        expect(reply.status, 'error', reason: name);
        expect(reply.error?.code, 'menu.relay_not_allowed', reason: name);
      }
      expect(host.seen, isEmpty);
    });

    test('a request for another opening is refused', () async {
      await expectLater(
        relay.handle(
          {'opening': 6, 'action': 'request', 'payload': _request('marketplace.read')},
          opening: opening,
          isCurrent: () => true,
        ),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        relay.handle(
          {'opening': 7, 'action': 'request', 'payload': _request('marketplace.read')},
          opening: opening,
          isCurrent: () => false,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(host.seen, isEmpty);
    });

    test('the contact number and account body stay in the primary', () async {
      final profile = _reply(
        await call({
          'action': 'request',
          'payload': _request('tradeProfile.read', owner: owner),
        }),
      );
      expect(jsonEncode(profile.payload), isNot(contains('138')));
      expect(jsonEncode(profile.payload), isNot(contains('139')));
      expect(profile.payload['data'], containsPair('orderLimit', 5));
      final account = _reply(
        await call({
          'action': 'request',
          'payload': _request('account.getCurrent'),
        }),
      );
      expect(account.payload, {'schemaVersion': 1, 'state': 'signedIn'});
      expect(account.accountContext?.subject, owner.subject);
      expect(owner.subject, isNot('owner'));
      expect(owner.subject, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(account.correlationId, 'menu-1');
    });

    test('the menu never sees the Host subject; its owner maps back, and an '
        'account change retires it', () async {
      final reply = _reply(
        await call({
          'action': 'request',
          'payload': _request('marketplace.trade', id: 'own-1', owner: owner),
        }),
      );
      expect(reply.status, 'ok');
      expect(host.subjects.last, 'owner');
      expect(jsonEncode(reply.toJson()), isNot(contains('"owner"')));
      final forged = _reply(
        await call({
          'action': 'request',
          'payload': _request('marketplace.trade', id: 'own-2', owner: _owner),
        }),
      );
      expect(forged.error?.code, 'marketplace.context_changed');
      await host.event('account.changed');
      await pumpEventQueue();
      final stale = _reply(
        await call({
          'action': 'request',
          'payload': _request('communities.saveRoles', id: 'own-3', owner: owner),
        }),
      );
      expect(stale.error?.code, 'communities.refreshRequired');
      expect(host.seen, ['marketplace.trade']);
    });

    test('a legacy account id never reaches the menu in any reply', () async {
      // A legacy session's subject is its account id (ScmAccountBridgeHost).
      const legacy = BridgeAccountContext(
        environment: 'legacy',
        authority: 'starbridge-legacy',
        subject: 'legacy-account-1234567890',
      );
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      )..acceptHostCapabilities(const {'account.getCurrent', 'marketplace.read'});
      pair.host.incoming.listen(
        (request) => pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: legacy,
            payload: {
              'schemaVersion': 1,
              'state': 'legacySignedIn',
              'accountId': 'legacy-account-1234567890',
            },
            status: 'ok',
          ),
        ),
      );
      relay = MenuBridgeRelay(session, mode: () => null, channel: primary);
      for (final name in const ['account.getCurrent', 'marketplace.read']) {
        final raw = await call({
          'action': 'request',
          'payload': _request(name, id: 'legacy-$name'),
        });
        expect(raw as String, isNot(contains('1234567890')), reason: name);
        expect(_reply(raw).accountContext?.subject, isNot(legacy.subject));
      }
    });

    test('a profile save that touches an image stays in the client', () async {
      for (final changes in const [
        {'logoImageData': 'data:image/png;base64,AA=='},
        {'clearLogoImage': true},
        {'clearBackgroundImage': true},
        {'bannerImageData': 'data:image/png;base64,AA=='},
      ]) {
        final reply = _reply(
          await call({
            'action': 'request',
            'payload': _request(
              'communities.saveProfile',
              owner: owner,
              payload: {'schemaVersion': 1, 'changes': changes},
            ),
          }),
        );
        expect(reply.error?.code, 'menu.relay_not_allowed', reason: '$changes');
      }
      expect(host.seen, isEmpty);
      final text = _reply(
        await call({
          'action': 'request',
          'payload': _request(
            'communities.saveProfile',
            owner: owner,
            payload: {
              'schemaVersion': 1,
              'changes': {'description': 'x', 'clearLogoImage': false},
            },
          ),
        }),
      );
      expect(text.status, 'ok');
      expect(host.seen, ['communities.saveProfile']);
    });

    test('hello offers only listed capabilities', () async {
      final state = jsonDecode(await call({'action': 'hello'}) as String) as Map;
      expect(state['generation'], 3);
      expect(
        (state['capabilities'] as List).toSet(),
        {
          'marketplace.read',
          'marketplace.trade',
          'marketplace.chat',
          'tradeProfile.read',
          'account.getCurrent',
          'officialFleet.getMembers',
          'officialFleet.governanceRole',
        },
      );
      expect(state['online'], isFalse);
    });

    test('events: only listed ones, account bodies stripped, none after retire', () async {
      await call({'action': 'hello'});
      await host.event('overlay.changed');
      await host.event('marketplace.changed', payload: {'kind': 'trade'});
      await host.event('bootstrap.invalidated', payload: {'secret': 'x'});
      await pumpEventQueue();
      expect(published, hasLength(2));
      final first = jsonDecode(published[0]['payload'] as String) as Map;
      final second = jsonDecode(published[1]['payload'] as String) as Map;
      expect(first['envelope']['name'], 'marketplace.changed');
      expect(first['envelope']['payload'], {'kind': 'trade'});
      expect(second['envelope']['payload'], isEmpty);
      relay.retire();
      await host.event('marketplace.changed');
      await pumpEventQueue();
      expect(published, hasLength(2));
    });

    test('trade chat: requests and pushes pass without contact numbers, and '
        'pushes stop when the menu hides', () async {
      final reply = _reply(
        await call({
          'action': 'request',
          'payload': _request('marketplace.chat', owner: owner),
        }),
      );
      expect(reply.status, 'ok');
      expect(host.seen, ['marketplace.chat']);
      expect(jsonEncode(reply.payload), isNot(contains('137')));
      expect(reply.payload['data'], containsPair('ref', 'chat-1'));
      await call({'action': 'hello'});
      await host.event(
        'marketplace.chatPushed',
        payload: {
          'push': {
            'ref': 'chat-1',
            'sender': {'name': 'seller', 'userMobile': '13600000000'},
            'text': 'hello',
          },
        },
      );
      await pumpEventQueue();
      expect(published, hasLength(1));
      final pushed = jsonDecode(published.single['payload'] as String) as Map;
      expect(pushed['envelope']['name'], 'marketplace.chatPushed');
      expect(pushed['envelope']['payload']['push']['text'], 'hello');
      expect(jsonEncode(pushed), isNot(contains('136')));
      relay.retire();
      await host.event('marketplace.chatPushed', payload: {'push': {}});
      await pumpEventQueue();
      expect(published, hasLength(1));
    });

    test('fleet: reads pass without emails, client-only writes do not', () async {
      final members = _reply(
        await call({
          'action': 'request',
          'payload': _request('officialFleet.getMembers', owner: owner),
        }),
      );
      expect(members.status, 'ok');
      expect(jsonEncode(members.payload), isNot(contains('example.invalid')));
      expect(jsonEncode(members.payload), contains('Member'));
      final role = _reply(
        await call({
          'action': 'request',
          'payload': _request(
            'officialFleet.governance.activate',
            owner: owner,
          ),
        }),
      );
      expect(role.error?.code, 'menu.relay_not_allowed');
      expect(host.seen, ['officialFleet.getMembers']);
    });

    test('organizations: reads, chat and approved writes pass; picking, overlay '
        'and whole-organization writes stay in the client; its pushes arrive without bodies', () async {
      for (final name in const [
        'communities.pickLogo',
        'communities.cropLogo',
        'communities.disband',
        'communities.transferOwnership',
        'overlay.updateWorkspace',
        'account.refreshRsiData',
      ]) {
        final reply = _reply(
          await call({
            'action': 'request',
            'payload': _request(name, owner: owner),
          }),
        );
        expect(reply.error?.code, 'menu.relay_not_allowed', reason: name);
      }
      expect(host.seen, isEmpty);
      for (final name in const [
        'communities.read',
        'communities.sendChat',
        'communities.removeMember',
        'officialFleet.writeRankPolicy',
      ]) {
        expect(MenuBridgeRelay.requests, contains(name));
      }
      await call({'action': 'hello'});
      await host.event('hangarReader.changed', payload: {'secret': 'x'});
      await host.event('account.presentationChanged', payload: {'secret': 'x'});
      await host.event('communities.unlisted');
      await pumpEventQueue();
      expect(published, hasLength(2));
      for (final message in published) {
        final envelope = (jsonDecode(message['payload'] as String) as Map)['envelope'];
        expect(envelope['payload'], isEmpty);
      }
    });

    test('own profile: only name and inline avatar, and it follows changes', () async {
      final profile = ValueNotifier(
        const AccountProfile(
          displayName: 'Self',
          avatarUrl: 'https://example.invalid/a.png',
          avatarImageData: 'not-an-inline-image',
          email: 'self@example.invalid',
          maskedAccount: 's***@example.invalid',
        ),
      );
      relay = MenuBridgeRelay(
        host.session,
        mode: () => null,
        channel: primary,
        ownProfile: () => profile.value,
        ownProfileChanges: profile,
      );
      final state = jsonDecode(await call({'action': 'hello'}) as String) as Map;
      expect(state['self'], {'displayName': 'Self'});
      expect(jsonEncode(state), isNot(contains('example.invalid')));
      profile.value = const AccountProfile(displayName: 'Renamed');
      await pumpEventQueue();
      final pushed = jsonDecode(published.last['payload'] as String) as Map;
      expect(pushed['self'], {'displayName': 'Renamed'});
      relay.retire();
      final count = published.length;
      profile.value = const AccountProfile(displayName: 'Hidden');
      await pumpEventQueue();
      expect(published, hasLength(count));
    });

    test('SCM-only is a single yes or no and follows account changes', () async {
      final account = ValueNotifier(false);
      relay = MenuBridgeRelay(
        host.session,
        mode: () => null,
        channel: primary,
        ownProfileChanges: account,
        scmOnly: () => account.value,
      );
      final state = jsonDecode(await call({'action': 'hello'}) as String) as Map;
      expect(state['scmOnly'], isFalse);
      account.value = true;
      await pumpEventQueue();
      final pushed = jsonDecode(published.last['payload'] as String) as Map;
      expect(pushed['scmOnly'], isTrue);
    });

    test('hiding cancels relayed reads before a mode change, not writes', () async {
      final clock = Stopwatch()..start();
      await call({'action': 'hello'});
      host.hold = Completer();
      final read = call({
        'action': 'request',
        'payload': _request('marketplace.read', id: 'read-1', owner: owner),
      });
      final write = call({
        'action': 'request',
        'payload': _request('marketplace.trade', id: 'write-1', owner: owner),
      });
      await pumpEventQueue();
      relay.retire();
      expect(_reply(await read).status, 'cancelled');
      await pumpEventQueue();
      expect(host.seen.where((name) => name == 'bridge.cancel'), hasLength(1));
      var switched = false;
      final change = host.session.runConnectionModeChange(
        () async => switched = true,
      );
      // The read was cancelled at the Host before the change began; the menu
      // engine then says its own work has exited.
      await relay.handle(
        {'opening': opening, 'action': 'exited'},
        opening: null,
        isCurrent: () => false,
      );
      host.hold!.complete();
      expect(_reply(await write).status, 'ok');
      await change;
      expect(switched, isTrue);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a menu that hides while asked to pause is waited for until it has '
        'exited', () async {
      await call({'action': 'hello'});
      var switched = false;
      final clock = Stopwatch()..start();
      final change = host.session.runConnectionModeChange(
        () async => switched = true,
      );
      await pumpEventQueue();
      expect(switched, isFalse); // Asked to pause; the menu has not answered.
      relay.retire();
      await pumpEventQueue();
      expect(switched, isFalse); // Hidden now: its exit is awaited instead.
      await relay.handle(
        {'opening': opening, 'action': 'exited'},
        opening: null,
        isCurrent: () => false,
      );
      await change;
      expect(switched, isTrue);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('hide, reopen and hide again: each opening\'s exit is awaited', () async {
      final first = opening;
      await call({'action': 'hello'});
      relay.retire(); // Opening A hides.
      var switched = false;
      final clock = Stopwatch()..start();
      final change = host.session.runConnectionModeChange(
        () async => switched = true,
      );
      await pumpEventQueue();
      opening = first + 1; // Opening B, then it hides too.
      await call({'action': 'hello'});
      relay.retire();
      await pumpEventQueue();
      expect(switched, isFalse);
      // A's word arrives after the reopening (native accepts an earlier one).
      await relay.handle(
        {'opening': first, 'action': 'exited'},
        opening: null,
        isCurrent: () => false,
      );
      await pumpEventQueue();
      expect(switched, isFalse); // B has not said it yet.
      await relay.handle(
        {'opening': first + 1, 'action': 'exited'},
        opening: null,
        isCurrent: () => false,
      );
      await change;
      expect(switched, isTrue);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('another page greeting during a pause question does not end it', () async {
      await call({'action': 'hello'});
      String? asked;
      messenger.setMockMethodCallHandler(primary, (call) async {
        if (call.method == 'bridgeEvent') {
          final message =
              jsonDecode((call.arguments as Map)['payload'] as String) as Map;
          if (message['kind'] == 'pause') asked = '${message['id']}';
        }
        return null;
      });
      var switched = false;
      final change = host.session.runConnectionModeChange(
        () async => switched = true,
      );
      await pumpEventQueue();
      expect(asked, isNotNull);
      await call({'action': 'hello'}); // The fleet page connects meanwhile.
      await pumpEventQueue();
      expect(switched, isFalse);
      await call({'action': 'paused', 'payload': asked});
      await change;
      expect(switched, isTrue);
    });

    test('pages greeting in one opening keep each other\'s reads', () async {
      await call({'action': 'hello'});
      host.hold = Completer();
      final read = call({
        'action': 'request',
        'payload': _request('marketplace.read', id: 'read-2', owner: owner),
      });
      await pumpEventQueue();
      await call({'action': 'hello'});
      await call({'action': 'hello'});
      host.hold!.complete();
      expect(_reply(await read).status, 'ok');
      expect(host.seen, isNot(contains('bridge.cancel')));
    });

    test('a request id already in flight is refused, not replaced', () async {
      host.hold = Completer();
      final first = call({
        'action': 'request',
        'payload': _request('marketplace.read', id: 'same', owner: owner),
      });
      await pumpEventQueue();
      final second = _reply(
        await call({
          'action': 'request',
          'payload': _request('marketplace.read', id: 'same', owner: owner),
        }),
      );
      expect(second.error?.code, 'menu.duplicate_request');
      await call({'action': 'cancel', 'payload': 'same'});
      expect(_reply(await first).status, 'cancelled');
      host.hold!.complete();
    });

    test('a request already sent still answers after the menu hides', () async {
      host.hold = Completer();
      final answer = call({
        'action': 'request',
        'payload': _request('marketplace.trade', owner: owner),
      });
      await pumpEventQueue();
      relay.retire();
      host.hold!.complete();
      expect(_reply(await answer).status, 'ok');
    });

    test('after dispose no event or mode change touches the menu', () async {
      await call({'action': 'hello'});
      relay.dispose();
      await host.event('marketplace.changed');
      await host.session.runConnectionModeChange(() async {});
      await pumpEventQueue();
      expect(published, isEmpty);
    });

    test('a stale generation is answered without reaching the Host', () async {
      final reply = _reply(
        await call({
          'action': 'request',
          'payload': _request('marketplace.read', generation: 2),
        }),
      );
      expect(reply.status, 'cancelled');
      expect(reply.sessionGeneration, 2);
      expect(host.seen, isEmpty);
    });

    test('cancel reaches the Host for the menu\'s own request', () async {
      host.hold = Completer();
      final answer = call({
        'action': 'request',
        'payload': _request('marketplace.read', id: 'menu-9'),
      });
      await pumpEventQueue();
      await call({'action': 'cancel', 'payload': 'menu-9'});
      expect(_reply(await answer).status, 'cancelled');
      host.hold!.complete();
    });
  });

  group('menu side', () {
    late MenuPageRelay page;

    setUp(() {
      page = MenuPageRelay(surface);
      messenger.setMockMethodCallHandler(primary, (call) async {
        if (call.method == 'bridgeEvent') page.accept(call.arguments);
        return null;
      });
      messenger.setMockMethodCallHandler(surface, (call) async {
        expect(call.method, 'bridgeRelay');
        return relay.handle(
          call.arguments,
          opening: opening,
          isCurrent: () => true,
        );
      });
      relay = MenuBridgeRelay(
        host.session,
        mode: () => _AlwaysOnline(),
        channel: primary,
      );
    });
    tearDown(() async => page.release());

    Future<BridgeClientSession> open() async {
      page.update(opening: opening, wanted: true, enabled: true);
      return (await page.connect())!;
    }

    test('the hall port works through a real session', () async {
      final session = await open();
      expect(session.activeGeneration, 3);
      expect(page.allowsOnlineTraffic, isTrue);
      final port = BridgeMarketplacePort(session, page);
      expect(port.available, isTrue);
      final read = await port.read('latest');
      expect(read.rows, isEmpty);
      expect(host.seen, ['marketplace.read']);
      final profile = await port.tradeProfile();
      expect(profile.containsKey('userMobile'), isFalse);
      port.dispose();
    });

    test('a hidden menu sends nothing, and an opening restores it', () async {
      final session = await open();
      final port = BridgeMarketplacePort(session, page);
      page.update(opening: opening, wanted: false, enabled: true);
      expect(page.allowsOnlineTraffic, isFalse);
      await expectLater(port.read('latest'), throwsA(anything));
      expect(host.seen, isEmpty);
      opening = 8;
      await open();
      expect(page.allowsOnlineTraffic, isTrue);
      await port.read('latest');
      expect(host.seen, ['marketplace.read']);
      port.dispose();
    });

    test('hello after an account change moves the generation', () async {
      final session = await open();
      final context = page.contextRevision;
      host.session.advanceGeneration(5);
      opening = 8;
      await open();
      expect(session.activeGeneration, 5);
      expect(page.contextRevision, context + 1);
    });

    test('an account event while open moves the context and tells listeners', () async {
      await open();
      final context = page.contextRevision;
      var told = 0;
      page.addListener(() => told++);
      page.accept({
        'opening': opening,
        'payload': jsonEncode({
          'kind': 'event',
          'envelope': const BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 4,
            sequence: 1,
            payload: {},
          ).toJson(),
        }),
      });
      await pumpEventQueue();
      expect(page.contextRevision, context + 1);
      expect(told, greaterThan(0));
    });

    test('a mode change waits until the menu has stopped', () async {
      final session = await open();
      var drained = false;
      session.registerConnectionModeNetworkWork(
        ConnectionModeNetworkWork(
          pause: () async {
            await pumpEventQueue();
            drained = true;
          },
          reconcile: () async => drained = false,
        ),
      );
      var during = true;
      await host.session.runConnectionModeChange(() async {
        expect(drained, isTrue);
        expect(session.connectionModeChanging, isTrue);
        during = page.allowsOnlineTraffic;
        final reply = _reply(
          await call({
            'action': 'request',
            'payload': _request('marketplace.read'),
          }),
        );
        expect(reply.error?.code, 'bridge.mode_changing');
      });
      expect(during, isFalse);
      await pumpEventQueue();
      expect(page.allowsOnlineTraffic, isTrue);
      expect(session.connectionModeChanging, isFalse);
      expect(drained, isFalse);
    });

    test('the shared session stays until the last page lets go', () async {
      page.update(opening: opening, wanted: true, enabled: true);
      final hall = Object(), fleet = Object();
      final first = (await page.connect(holder: hall))!;
      final second = (await page.connect(holder: fleet))!;
      expect(identical(first, second), isTrue);
      await page.releaseFor(hall);
      expect(first.isClosed, isFalse);
      await page.releaseFor(fleet);
      expect(first.isClosed, isTrue);
    });

    test('pages keep holding after the primary was replaced', () async {
      page.update(opening: opening, wanted: true, enabled: true);
      final hall = Object(), fleet = Object();
      final old = (await page.connect(holder: hall))!;
      await page.connect(holder: fleet);
      // Another primary composition: the hall's next greeting revokes.
      relay = MenuBridgeRelay(
        host.session,
        mode: () => _AlwaysOnline(),
        channel: primary,
      );
      final replaced = (await page.connect(holder: hall))!;
      expect(identical(old, replaced), isFalse);
      expect(old.isClosed, isTrue);
      await page.releaseFor(fleet);
      expect(replaced.isClosed, isFalse);
      await page.releaseFor(hall);
      expect(replaced.isClosed, isTrue);
    });

    test('hiding is not going offline for the organization and fleet pages', () async {
      await open();
      var hostModeChanges = 0;
      page.hostMode.addListener(() => hostModeChanges++);
      expect(page.allowsOnlineTraffic, isTrue);
      expect(page.hostMode.allowsOnlineTraffic, isTrue);
      page.update(opening: opening, wanted: false, enabled: true);
      // Images and the hall close with the menu; writes in flight do not.
      expect(page.allowsOnlineTraffic, isFalse);
      expect(page.hostMode.allowsOnlineTraffic, isTrue);
      expect(hostModeChanges, 0);
      await page.release();
      expect(page.hostMode.allowsOnlineTraffic, isFalse);
      expect(hostModeChanges, 1);
    });

    test('the own profile is there while open and gone once hidden', () async {
      relay = MenuBridgeRelay(
        host.session,
        mode: () => _AlwaysOnline(),
        channel: primary,
        ownProfile: () => const AccountProfile(
          displayName: 'Self',
          email: 'self@example.invalid',
        ),
      );
      await open();
      expect(page.ownProfile?.displayName, 'Self');
      expect(page.ownProfile?.email, isNull);
      page.update(opening: opening, wanted: false, enabled: true);
      expect(page.ownProfile, isNull);
    });

    test('the menu pages learn SCM-only from the client, follow it and drop it '
        'on release', () async {
      final account = ValueNotifier(true);
      relay = MenuBridgeRelay(
        host.session,
        mode: () => _AlwaysOnline(),
        channel: primary,
        ownProfileChanges: account,
        scmOnly: () => account.value,
      );
      expect(page.scmOnly, isFalse);
      await open();
      expect(page.scmOnly, isTrue);
      var told = 0;
      page.addListener(() => told++);
      account.value = false;
      await pumpEventQueue();
      expect(page.scmOnly, isFalse);
      expect(told, greaterThan(0), reason: 'pages redraw their entries');
      account.value = true;
      await pumpEventQueue();
      expect(page.scmOnly, isTrue);
      await page.release();
      expect(page.scmOnly, isFalse);
    });

    group('a hidden menu', () {
      int? current;
      setUp(() {
        current = opening;
        // The window passes no opening once the menu has hidden.
        messenger.setMockMethodCallHandler(surface, (call) async {
          return relay.handle(
            call.arguments,
            opening: current,
            isCurrent: () => current != null,
          );
        });
      });

      void hide() {
        relay.retire(); // The window suspends first, then the snapshot.
        current = null;
        page.update(opening: opening, wanted: false, enabled: true);
      }

      test('a mode change waits until its cancelled work has exited', () async {
        await open();
        final exit = Completer<void>();
        page.registerExit(() => exit.future);
        hide();
        var switched = false;
        final change = host.session.runConnectionModeChange(
          () async => switched = true,
        );
        await pumpEventQueue();
        expect(switched, isFalse);
        exit.complete();
        await change;
        expect(switched, isTrue);
      });

      test('with nothing running the mode change goes on at once', () async {
        await open();
        hide();
        await pumpEventQueue();
        final clock = Stopwatch()..start();
        await host.session.runConnectionModeChange(() async {});
        expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      });

      test('a word for another opening ends no wait; silence is bounded', () async {
        await open();
        final exit = Completer<void>();
        page.registerExit(() => exit.future);
        hide();
        await relay.handle(
          {'opening': opening + 1, 'action': 'exited'},
          opening: null,
          isCurrent: () => false,
        );
        final clock = Stopwatch()..start();
        await host.session.runConnectionModeChange(() async {});
        expect(clock.elapsed, greaterThan(const Duration(milliseconds: 2900)));
        exit.complete();
      });

      test('the exit word opens nothing: requests stay refused', () async {
        await open();
        hide();
        await expectLater(
          relay.handle(
            {'opening': opening, 'action': 'request', 'payload': _request('marketplace.read')},
            opening: null,
            isCurrent: () => false,
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(host.seen.where((n) => n == 'marketplace.read'), isEmpty);
      });
    });

    test('a quick hide and reopen greets again for the new opening', () async {
      page.update(opening: opening, wanted: true, enabled: true);
      final first = page.connect();
      page.update(opening: opening, wanted: false, enabled: true);
      opening = 8;
      page.update(opening: opening, wanted: true, enabled: true);
      final second = page.connect();
      expect(await second, isNotNull);
      expect(await first, anyOf(isNull, isNotNull));
      expect(page.allowsOnlineTraffic, isTrue);
    });

    test('another primary composition never reuses the old session', () async {
      final session = await open();
      final context = page.contextRevision;
      relay = MenuBridgeRelay(
        host.session,
        mode: () => _AlwaysOnline(),
        channel: primary,
      );
      opening = 8;
      final next = await open();
      expect(identical(next, session), isFalse);
      expect(session.isClosed, isTrue);
      expect(page.contextRevision, greaterThan(context));
    });

    test('a new native tools epoch revokes the session', () async {
      page.fromSnapshot(opening, true, {'pageRelay': true, 'localToolsEpoch': 1});
      final session = (await page.connect())!;
      page.fromSnapshot(opening, false, {'localToolsEpoch': 2});
      await pumpEventQueue();
      expect(session.isClosed, isTrue);
    });

    test('an event for another opening is ignored', () async {
      final session = await open();
      final events = <String>[];
      final work = session.events.listen((event) => events.add(event.name));
      void deliver(int forOpening) => page.accept({
        'opening': forOpening,
        'payload': jsonEncode({
          'kind': 'event',
          'envelope': BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'marketplace.changed',
            sessionGeneration: 3,
            sequence: forOpening,
            payload: const {},
          ).toJson(),
        }),
      });
      deliver(6);
      await pumpEventQueue();
      expect(events, isEmpty);
      deliver(7);
      await pumpEventQueue();
      expect(events, ['marketplace.changed']);
      await work.cancel();
    });

    test('losing the capability releases the session', () async {
      final session = await open();
      page.update(opening: opening, wanted: true, enabled: false);
      await pumpEventQueue();
      expect(session.isClosed, isTrue);
      expect(page.active, isFalse);
    });
  });

  test('without a relay (recovery not answered) the request is refused', () {
    expect(
      () => routeMenuWindowRequest(
        const MethodCall('bridgeRelay', {'opening': 1, 'action': 'hello'}),
        opening: 1,
        isCurrent: () => true,
        execHangar: null,
        openExecHangar: () {},
        browserResume: () => null,
        relay: null,
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('toolbar orders saved before the hall or the fleet keep working', () {
    Map<String, Object?> saved(List<String> order) => {
      'order': order,
      'hidden': const <String>[],
      'density': 'standard',
      'labels': 'auto',
    };
    final beforeFleet = MenuToolbarPreferences.ids
        .where((id) => id != 'officialFleet')
        .toList();
    expect(
      MenuToolbarPreferences.parse(saved(beforeFleet))?.order.last,
      'officialFleet',
    );
    final old = beforeFleet.where((id) => id != 'marketplace');
    expect(
      MenuToolbarPreferences.parse(saved(old.toList()))?.order.sublist(
        old.length,
      ),
      ['marketplace', 'officialFleet'],
    );
    // A newer tool without an older one was never written by any version.
    expect(
      MenuToolbarPreferences.parse(saved([...old, 'officialFleet'])),
      isNull,
    );
    final older = old.where((id) => id != 'execHangar').toList();
    expect(
      MenuToolbarPreferences.parse({
        'order': older,
        'hidden': const <String>[],
        'density': 'standard',
        'labels': 'auto',
      })?.order.sublist(older.length),
      ['execHangar', 'marketplace', 'officialFleet'],
    );
  });
}

/// Just enough of a connection mode for the relay's online fact.
final class _AlwaysOnline extends ChangeNotifier
    implements ConnectionModeControl {
  @override
  bool get allowsOnlineTraffic => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
