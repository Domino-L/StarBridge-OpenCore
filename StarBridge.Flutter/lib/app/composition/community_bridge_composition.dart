import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/communities/bridge_communities.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// Borrow current display sources; no completed root response or authority is retained.
BridgeCommunities composeCommunityBridge(
  BridgeClientSession session,
  ValueListenable<AccountProjection> account,
  ConnectionModeControl? mode,
) => BridgeCommunities(
  session,
  connectionMode: mode,
  retainedSelectionChanges: account,
  retainedPreviousReadId: () => account.value.retainedPreviousReadId,
  retainedReadId: () {
    final current = account.value;
    return current.generation == session.activeGeneration &&
            current.hasRetainedDisplayRead
        ? current.retainedReadId
        : null;
  },
  ownAvatar: () {
    final current = account.value;
    return current.generation == session.activeGeneration &&
            (current.isSignedIn ||
                current.sessionState == AccountSessionState.legacySignedIn)
        ? current.profile?.avatarImageData
        : null;
  },
);
