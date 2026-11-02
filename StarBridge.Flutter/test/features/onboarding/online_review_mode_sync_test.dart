import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';

import 'connection_mode_test.dart' show modeWire;
import 'online_review_test_support.dart';
import 'retained_online_review_test.dart' show retainedWire;

void main() {
  test(
    'cancel and resume refresh the original mode owner without a Host event',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
        BridgeConnectionModeAdapter.capability,
      ]);
      var state = 'signInRequired';
      var revision = 7;
      f.onRequest = (request) async {
        if (request.name == 'onboarding.mode.read') {
          await f.respond(request, value: modeWire(state, revision: revision));
          return;
        }
        if (request.name.endsWith('.cancel')) {
          state = 'offline';
          revision++;
        }
        if (request.name.endsWith('.begin')) {
          state = 'signInRequired';
          revision++;
        }
        await f.respond(
          request,
          value: retainedWire(
            mode: state,
            state: state == 'offline' ? 'notStarted' : 'signInRequired',
            revision: revision,
          ),
        );
      };
      final mode = ConnectionModeController(
        BridgeConnectionModeAdapter(f.session),
      );
      addTearDown(mode.dispose);
      await mode.refresh();
      final review = BridgeOnlineReviewAdapter(
        f.session,
        onModeChanged: mode.refresh,
      );
      await review.read();
      await review.execute(OnlineReviewAction.cancel, revision);
      expect(mode.snapshot.state, ConnectionModeState.offline);
      expect(mode.allowsOnlineTraffic, false);
      await review.execute(OnlineReviewAction.begin, revision);
      expect(mode.snapshot.state, ConnectionModeState.signInRequired);
      expect(mode.allowsOnlineTraffic, false);
    },
  );
}
