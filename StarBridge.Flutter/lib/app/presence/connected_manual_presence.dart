import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'bridge_manual_presence.dart';

/// Binds to the existing authenticated Host; no independent login or poller.
class ConnectedManualPresence {
  ConnectedManualPresence(this.session, this.chrome) {
    source = BridgeManualPresence(session, _account);
    chrome.addListener(_chromeChanged);
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _account.value = PresenceAccountScope(
          generation: session.activeGeneration,
          account: null,
          available: false,
          automaticKey: chrome.value.displayPresenceKey,
        );
        unawaited(refresh());
      }
    });
    unawaited(refresh());
  }
  final BridgeClientSession session;
  final ValueListenable<ShellChromeProjection> chrome;
  final _account = ValueNotifier(
    const PresenceAccountScope(generation: 0, account: null, available: false),
  );
  late final BridgeManualPresence source;
  late final StreamSubscription<BridgeEnvelope> _events;
  bool _disposed = false;
  int _epoch = 0;
  void _chromeChanged() {
    final current = _account.value;
    _account.value = PresenceAccountScope(
      generation: current.generation,
      account: current.account,
      available: current.available,
      automaticKey: chrome.value.displayPresenceKey,
    );
  }

  Future<void> refresh() async {
    if (_disposed ||
        !session.hostCapabilities.contains('presence.visibility')) {
      return;
    }
    final epoch = ++_epoch;
    try {
      final result = await session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (_disposed ||
          epoch != _epoch ||
          result.sessionGeneration != session.activeGeneration) {
        return;
      }
      final owner = result.accountContext;
      final state = result.payload['state'];
      final available =
          result.payload['schemaVersion'] == 1 &&
          owner != null &&
          (state == 'signedIn' ||
              state == 'legacySignedIn' &&
                  owner.authority.startsWith('starbridge-relay-'));
      _account.value = PresenceAccountScope(
        generation: result.sessionGeneration,
        account: available ? owner : null,
        available: available,
        automaticKey: chrome.value.displayPresenceKey,
      );
      await source.refresh();
    } on Object {
      if (_disposed || epoch != _epoch) return;
      final old = _account.value;
      _account.value = PresenceAccountScope(
        generation: old.generation,
        account: old.account,
        available: false,
        automaticKey: chrome.value.displayPresenceKey,
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    unawaited(_events.cancel());
    chrome.removeListener(_chromeChanged);
    source.dispose();
    _account.dispose();
  }
}
