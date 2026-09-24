import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/connected_manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final legacy in [false, true]) {
    test(
      'connected source uses current authenticated owner, legacy=$legacy',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        session.acceptHostCapabilities(['presence.visibility']);
        final owner = BridgeAccountContext(
          environment: 'test',
          authority: legacy ? 'starbridge-relay-test' : 'scm.invalid',
          subject: 'sample',
        );
        var mode = 'online';
        var confirmed = legacy;
        final names = <String>[];
        final sub = pair.host.incoming.listen((r) async {
          if (r.messageType != 'request') return;
          names.add(r.name);
          if (r.name == 'presence.set') {
            mode = r.payload['mode']! as String;
            confirmed = true;
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              sessionGeneration: r.sessionGeneration,
              correlationId: r.correlationId,
              accountContext: owner,
              status: 'ok',
              payload: r.name == 'account.getCurrent'
                  ? {
                      'schemaVersion': 1,
                      'state': legacy ? 'legacySignedIn' : 'signedIn',
                    }
                  : {
                      'schemaVersion': 1,
                      'revision': 'missing',
                      'mode': mode,
                      'state': confirmed ? 'ready' : 'unconfirmed',
                    },
            ),
          );
        });
        final chrome = InMemoryShellChrome();
        final connected = ConnectedManualPresence(session, chrome.projection);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(names, ['account.getCurrent', 'presence.read']);
        expect(connected.source.controller.canChange, true);
        if (!legacy) expect(connected.source.value.confirmedMode, null);
        await connected.source.controller.select(PresenceVisibility.invisible);
        expect(connected.source.value.selfKey, 'presence.invisible');
        chrome.replace(
          chrome.projection.value.copyWith(presenceKey: 'presence.away'),
        );
        expect(connected.source.value.selfKey, 'presence.invisible');
        expect(names, ['account.getCurrent', 'presence.read', 'presence.set']);
        connected.dispose();
        await sub.cancel();
        await session.close();
        await pair.host.close();
      },
    );
  }
}
