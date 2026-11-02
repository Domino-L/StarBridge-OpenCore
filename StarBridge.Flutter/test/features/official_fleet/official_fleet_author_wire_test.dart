import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_communication_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_communication_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> wire(String name) => Map<String, Object?>.from(
  jsonDecode(
    File('test/fixtures/official_fleet_authors/$name.payload.json')
        .readAsStringSync(),
  ) as Map,
);

void main() {
  test(
    'unnegotiated official Host wire keeps body but retires author identity',
    () async {
      final host = AuthorWireHost();
      addTearDown(host.close);
      final adapter = host.adapter;
      addTearDown(adapter.close);
      final context = await adapter.open();
      final page = await adapter.readChat(context.targetRef);
      expect(page.messages.single.text, 'authorized body');
      expect(page.messages.single.sequence, 1);
      expect(
        page.messages.single.callsign,
        isEmpty,
        reason: 'An open schema alone does not grant the optional author lane.',
      );
      expect(page.messages.single.hasAvatar, isFalse);
      expect(page.messages.single.avatarVersion, isNull);
      expect(
        host.requests
            .where((r) => r.payload['action'] == 'chat')
            .single
            .payload
            .containsKey('authorIdentitySchemaVersion'),
        isFalse,
      );
    },
  );

  test('both advertised protocol and this source open negotiate actual author wire', () async {
    final host = AuthorWireHost(authorCapability: true);
    addTearDown(host.close);
    addTearDown(host.adapter.close);
    final context = await host.adapter.open();
    final page = await host.adapter.readChat(context.targetRef);
    expect(page.messages.single.text, 'authorized body');
    expect(page.messages.single.callsign, 'Bridge wire-visible');
    expect(page.messages.single.hasAvatar, isTrue);
    final request = host.requests
        .where((r) => r.payload['action'] == 'chat')
        .single;
    expect(request.payload['authorIdentitySchemaVersion'], 1);
    expect(request.payload['observeMessageRefs'], isEmpty);
  });
}

final class AuthorWireHost {
  AuthorWireHost({
    bool authorCapability = false,
    bool announcementWire = false,
    String announcementFixture = 'ann-mixed-current',
    Map<String, Object?> Function()? announcementPage,
    String? announcementDetailFixture,
    Map<String, Object?> Function()? announcementDetailPage,
    Map<String, Object?> Function(BridgeEnvelope request)? chatPage,
    Map<String, Object?> Function(BridgeEnvelope request)? chatDetailPage,
    Set<String> holdActions = const {},
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities([
      'officialFleet.communication',
      if (authorCapability) 'officialFleet.communication.authorIdentities',
    ]);
    subscription = host.incoming.listen((request) async {
      requests.add(request);
      if (holdActions.contains(request.payload['action'])) return;
      final announcementGate = _announcementGate;
      if (request.payload['action'] == 'announcements' &&
          announcementGate != null &&
          !_announcementGateClaimed) {
        _announcementGateClaimed = true;
        await announcementGate.future;
      }
      final chatGate = _chatDetailGate;
      if (request.payload['action'] == 'chatDetail' &&
          chatGate != null &&
          !_chatDetailGateClaimed) {
        _chatDetailGateClaimed = true;
        await chatGate.future;
      }
      final detailGate = _announcementDetailGate;
      if (request.payload['action'] == 'announcementDetail' &&
          request.payload['authorIdentitySchemaVersion'] == 1 &&
          detailGate != null &&
          !_announcementDetailGateClaimed) {
        _announcementDetailGateClaimed = true;
        await detailGate.future;
      }
      if (_closed) return;
      var data = request.name == 'account.getCurrent'
          ? <String, Object?>{
              'schemaVersion': 1,
              'state': 'signedIn',
              'displayName': 'Synthetic viewer',
              'avatarUrl': null,
            }
          : wire(
              request.payload['action'] == 'open'
                  ? 'open-capable-context-fixture'
                  : 'chat-current-visible',
            );
      if (announcementWire && request.payload['action'] == 'open') {
        // Explicit consumer fixture alignment: producer scenarios independently
        // minted opaque targets. The original ann payload is never rewritten.
        data = {
          ...data,
          'targetRef':
              (announcementPage?.call() ??
              wire(announcementFixture))['targetRef'],
        };
      }
      if (chatPage != null && request.payload['action'] == 'open') {
        // Explicit consumer-domain address alignment; original producer bytes
        // are never rewritten and page/detail are independent scenarios.
        data = {...data, 'targetRef': chatPage(request)['targetRef']};
      }
      if (chatPage != null && request.payload['action'] == 'chat') {
        data = chatPage(request);
      }
      if (chatDetailPage != null && request.payload['action'] == 'chatDetail') {
        data = chatDetailPage(request);
      }
      if (announcementWire && request.payload['action'] == 'announcements') {
        data = announcementPage?.call() ?? wire(announcementFixture);
      }
      if (announcementDetailFixture != null &&
          request.payload['action'] == 'announcementDetail') {
        // This optional fixture is a typed consumer replay, not a legacy
        // success response. Keep an untyped request pending until fixture
        // retirement, so it cannot manufacture an unrelated dataInvalid.
        if (request.payload['authorIdentitySchemaVersion'] != 1) return;
        data =
            announcementDetailPage?.call() ?? wire(announcementDetailFixture);
      }
      if (chatPage == null &&
          request.payload['action'] == 'chat' &&
          (request.payload['after'] as int? ?? 0) > 0) {
        // These producer scenarios minted independent opaque addresses. Align
        // only addresses in this controlled incremental-worker fixture. The
        // original 36 producer files remain unchanged and separately tested.
        final original =
            (wire('chat-current-visible')['messages'] as List).single as Map;
        final updatePage = wire('chat-empty-page-observed-update');
        final observed = request.payload['observeMessageRefs'] as List? ?? [];
        data = {
          ...updatePage,
          'targetRef': request.payload['targetRef'],
          'authorUpdates': [
            if (observed.contains(original['messageRef']))
              {
                ...((updatePage['authorUpdates'] as List).single as Map),
                'messageRef': original['messageRef'],
                'senderRef': original['senderRef'],
              },
          ],
        };
      }
      if (request.payload['action'] == 'markChatRead') {
        data = {
          'schemaVersion': 1,
          'targetRef': request.payload['targetRef'],
          'messageRef': request.payload['messageRef'],
          'status': 'accepted',
          'readThroughSequence': 1,
        };
      }
      await host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: const BridgeAccountContext(
            environment: 'development',
            authority: 'scm-development',
            subject: 'synthetic-viewer',
          ),
          status: 'ok',
          payload: data,
        ),
      );
    });
    adapter = createOfficialFleetCommunicationAdapter(
      session,
      'officialFleet:7',
    );
  }
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final OrganizationCommunicationPort adapter;
  final requests = <BridgeEnvelope>[];
  bool _closed = false, _announcementGateClaimed = false;
  Completer<void>? _announcementGate;
  void holdNextAnnouncementRead() {
    if (_announcementGate != null && !_announcementGate!.isCompleted) {
      throw StateError('Only one pending fixture gate.');
    }
    _announcementGateClaimed = false;
    _announcementGate = Completer<void>();
  }

  bool get announcementReadHeld =>
      _announcementGateClaimed &&
      _announcementGate != null &&
      !_announcementGate!.isCompleted;
  void releaseAnnouncementRead() {
    if (!announcementReadHeld) throw StateError('No held announcement read.');
    _announcementGate!.complete();
  }

  bool _chatDetailGateClaimed = false;
  Completer<void>? _chatDetailGate;
  void holdNextChatDetail() {
    if (_chatDetailGate != null) {
      throw StateError('Only one chat detail fixture gate.');
    }
    _chatDetailGate = Completer<void>();
  }

  bool get chatDetailReadHeld =>
      _chatDetailGateClaimed &&
      _chatDetailGate != null &&
      !_chatDetailGate!.isCompleted;
  void releaseChatDetail() {
    if (!chatDetailReadHeld) throw StateError('No held chat detail.');
    _chatDetailGate!.complete();
  }

  bool _announcementDetailGateClaimed = false;
  Completer<void>? _announcementDetailGate;
  void holdNextAnnouncementDetail() {
    if (_announcementDetailGate != null) {
      throw StateError('Only one detail fixture gate.');
    }
    _announcementDetailGate = Completer<void>();
  }

  bool get announcementDetailReadHeld =>
      _announcementDetailGateClaimed &&
      _announcementDetailGate != null &&
      !_announcementDetailGate!.isCompleted;
  void releaseAnnouncementDetail() {
    if (!announcementDetailReadHeld) {
      throw StateError('No held announcement detail.');
    }
    _announcementDetailGate!.complete();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final announcementGate = _announcementGate;
    if (announcementGate != null && !announcementGate.isCompleted) {
      announcementGate.complete();
    }
    final detailGate = _announcementDetailGate;
    if (detailGate != null && !detailGate.isCompleted) detailGate.complete();
    final chatGate = _chatDetailGate;
    if (chatGate != null && !chatGate.isCompleted) chatGate.complete();
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}
