import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';

import 'bridge_overlay_appearance_live_port_test.dart' show Harness, sessionId;
import 'overlay_appearance_live_session_test.dart' show frame, flush;

void main() {
  test('real workspace adapter forwards bounded placement feedback to live page', () async {
    final h = Harness();
    addTearDown(h.close);
    h.responseOverride = {
      'schemaVersion': 1,
      'sessionId': sessionId,
      'placementStates': [
        {'slotId': 'Squads-Left', 'reason': 'screen-edge'},
      ],
    };
    final live = OverlayAppearanceLiveSession(BridgeOverlayWorkspaceAdapter(h.session));
    addTearDown(live.dispose);
    await live.open(frame());
    expect(live.placementStates, {'Squads-Left': 'screen-edge'});
    expect(() => live.placementStates['other'] = 'placed', throwsUnsupportedError);

    h.responseOverride = {
      'schemaVersion': 1,
      'revision': 1,
      'placementStates': [
        {'slotId': 'Squads-Left', 'reason': 'placed'},
      ],
    };
    live.update(frame());
    expect(live.placementStates, isEmpty, reason: 'in-flight state must not show stale warnings');
    await flush();
    expect(live.placementStates, {'Squads-Left': 'placed'});
    expect(h.requests.last.payload['frame'], frame().toMap());

    // Older Host replies remain compatible and clear former feedback.
    h.responseOverride = {'schemaVersion': 1, 'revision': 2};
    live.update(frame());
    await flush();
    expect(live.placementStates, isEmpty);
    h.responseOverride = null;
    await live.close();
    expect(live.placementStates, isEmpty);
    expect(h.requests.every((r) => r.accountContext == null), true);
  });
}
