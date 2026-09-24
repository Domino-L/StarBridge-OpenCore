import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/host/native_host_session_connector.dart';

void main() {
  test(
    'role capabilities are negotiated without excluding older Hosts',
    () async {
      final platform = _FakePlatformPort((request) {
        if (request.name == 'host.hello') {
          expect(
            request.payload['capabilities'],
            containsAll([
              'communities.roles',
              'communities.logs',
              'communities.announcements',
              'communities.ships',
              'communities.hangarSharing',
              'communities.saveHangarSharing',
              'communities.shipImage',
              'communities.reportShipImage',
              'communities.announcementDetail',
              'communities.manageAnnouncements',
              'communities.deleteLog',
              'communities.saveRoles',
              'communities.memberRole',
              'communities.saveMemberRole',
              'communities.memberRemoval',
              'communities.removeMember',
              'communities.ownershipTransfer',
              'communities.transferOwnership',
              'communities.ownershipExit',
              'communities.leaveWithSuccessor',
            ]),
          );
        }
        return _validResponder(request);
      });
      final lease = await NativeHostSessionConnector(
        platform: platform,
        random: Random(10),
      ).open();
      expect(
        lease.session.hostCapabilities,
        isNot(contains('communities.roles')),
      );
      await lease.close();
    },
  );

  test('connector negotiates without retired compatibility and adopts the Host generation', () async {
    final platform = _FakePlatformPort(_validResponder);
    final connector = NativeHostSessionConnector(
      platform: platform,
      random: Random(7),
    );

    final lease = await connector.open();

    expect(platform.lastPipeName, startsWith('starbridge-flutter-'));
    expect(lease.session.activeGeneration, 7);
    expect(lease.session.hostCapabilities, contains('host.gamePresence'));
    expect(platform.requests, ['host.hello', 'host.ready']);
    await lease.close();
    expect(platform.lastLease!.closed, isTrue);
  });

  test('connector rejects a Host missing an advertised capability', () async {
    final platform = _FakePlatformPort((request) {
      if (request.name == 'host.hello') {
        return _response(request, {
          'selectedProtocol': 1,
          'hostCapabilities': ['host.lifecycle'],
          'hostInstanceId': 'host-test',
          'sessionGeneration': 0,
          'maximumFrameBytes': BridgeProtocol.maximumFrameBytes,
        });
      }
      return _response(request, const {});
    });
    final connector = NativeHostSessionConnector(
      platform: platform,
      random: Random(8),
    );

    await expectLater(
      connector.open(),
      throwsA(
        isA<NativeHostConnectionException>().having(
          (error) => error.code,
          'code',
          'host.capability_missing',
        ),
      ),
    );
    expect(platform.lastLease!.closed, isTrue);
  });

  test(
    'connector exposes platform termination without inventing state',
    () async {
      final platform = _FakePlatformPort(_validResponder);
      final lease = await NativeHostSessionConnector(
        platform: platform,
        random: Random(9),
      ).open();

      platform.lastLease!.completeTermination(
        const NativeHostTermination(code: 'host.process_exited', exitCode: 4),
      );

      expect(
        await lease.terminated,
        isA<NativeHostTermination>()
            .having((value) => value.code, 'code', 'host.process_exited')
            .having((value) => value.exitCode, 'exitCode', 4),
      );
      await lease.close();
    },
  );
}

BridgeEnvelope _validResponder(BridgeEnvelope request) {
  if (request.name == 'host.hello') {
    return _response(request, {
      'selectedProtocol': 1,
      'hostCapabilities': [
        'account.lifecycle',
        'account.read',
        'host.lifecycle',
        'host.gamePresence',
        'officialFleet.read',
        'applicationPreferences.read',
        'applicationPreferences.write',
      ],
      'hostInstanceId': 'host-test',
      'sessionGeneration': 7,
      'maximumFrameBytes': BridgeProtocol.maximumFrameBytes,
    });
  }
  if (request.name == 'host.ready') {
    return _response(request, {'ready': true, 'hostInstanceId': 'host-test'});
  }
  throw StateError('Unexpected request ${request.name}');
}

BridgeEnvelope _response(BridgeEnvelope request, Map<String, Object?> payload) {
  return BridgeEnvelope(
    protocolVersion: 1,
    messageType: 'response',
    name: request.name,
    correlationId: request.correlationId,
    sessionGeneration: request.sessionGeneration,
    payload: payload,
    status: 'ok',
  );
}

typedef _Responder = BridgeEnvelope Function(BridgeEnvelope request);

final class _FakePlatformPort implements NativeHostPlatformPort {
  _FakePlatformPort(this._responder);

  final _Responder _responder;
  final List<String> requests = [];
  String? lastPipeName;
  _FakePlatformLease? lastLease;

  @override
  Future<NativeHostPlatformLease> start({required String pipeName}) async {
    lastPipeName = pipeName;
    final pair = InMemoryBridgeConnection.createPair();
    final lease = _FakePlatformLease(pair.client, pair.host);
    lastLease = lease;
    unawaited(
      pair.host.incoming.forEach((request) async {
        requests.add(request.name);
        await pair.host.send(_responder(request));
      }),
    );
    return lease;
  }
}

final class _FakePlatformLease implements NativeHostPlatformLease {
  _FakePlatformLease(this.connection, this._hostConnection);

  @override
  final BridgeConnection connection;
  final BridgeConnection _hostConnection;
  final Completer<NativeHostTermination> _termination = Completer();
  bool closed = false;

  @override
  Future<NativeHostTermination> get terminated => _termination.future;

  void completeTermination(NativeHostTermination termination) {
    if (!_termination.isCompleted) {
      _termination.complete(termination);
    }
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _hostConnection.close();
  }
}
