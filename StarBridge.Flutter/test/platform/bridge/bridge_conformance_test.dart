import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('Dart consumes the shared C# bridge fixture exactly', () {
    final file = File(
      '../contracts/native-bridge/v1/fixtures/request.profile-get-self.json',
    );
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final envelope = BridgeEnvelope.fromJson(decoded);
    expect(envelope.protocolVersion, 1);
    expect(envelope.name, 'profile.getSelf');
    expect(envelope.sessionGeneration, 7);
    expect(envelope.accountContext?.subject, 'synthetic-subject');
    expect(envelope.payload['locale'], 'zh-CN');
    expect(
      BridgeFrameCodec.decode(BridgeFrameCodec.encode(envelope)).toJson(),
      envelope.toJson(),
    );
  });

  test('incompatible protocol fails closed after decoding', () {
    final envelope = BridgeEnvelope(
      protocolVersion: 2,
      messageType: 'event',
      name: 'host.ready',
      sessionGeneration: 0,
      sequence: 0,
      payload: const {},
    );
    expect(
      envelope.requireCurrentVersion,
      throwsA(isA<BridgeVersionException>()),
    );
  });

  test('malformed account context is rejected', () {
    final json = <String, Object?>{
      'protocolVersion': 1,
      'messageType': 'request',
      'name': 'profile.getSelf',
      'correlationId': 'synthetic',
      'sessionGeneration': 1,
      'accountContext': {
        'environment': 'local',
        'authority': '',
        'subject': 'synthetic-subject',
      },
      'payload': <String, Object?>{},
    };
    expect(
      () => BridgeEnvelope.fromJson(json),
      throwsA(isA<BridgeFormatException>()),
    );
  });

  test('memory adapter uses the same frame round trip', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final observed = pair.host.incoming.first.timeout(
      const Duration(seconds: 2),
    );
    await pair.client.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'request',
        name: 'host.hello',
        correlationId: 'synthetic',
        sessionGeneration: 0,
        payload: {'text': '你好\nStarBridge'},
      ),
    );
    final envelope = await observed;
    expect(envelope.payload['text'], '你好\nStarBridge');
    await pair.client.close();
    await pair.host.close();
  });
}
