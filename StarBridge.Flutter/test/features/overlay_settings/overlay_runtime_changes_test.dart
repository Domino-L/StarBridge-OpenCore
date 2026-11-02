import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

Map<String, Object?> _payload(String windowState, {bool? visible}) => {
  'schemaVersion': 1,
  'windowState': windowState,
  'isVisible': visible ?? windowState == 'open',
  'appliedRevision': 1,
  'hotkeyState': 'registered',
  'followGameState': 'manual',
  'requestedSkin': 'Default',
  'effectiveSkin': 'Default',
  'usedFallbackSkin': false,
  'failureCode': null,
  'retryable': false,
};

OverlayRuntimeSnapshot _runtime(String windowState) =>
    OverlayRuntimeSnapshot.fromMap(_payload(windowState));

void main() {
  group('bridge adapter', () {
    late InMemoryBridgePair pair;
    late BridgeClientSession session;
    var sequence = 0;

    Future<void> event(
      String name,
      Map<String, Object?> payload, {
      int generation = 10,
    }) => pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: name,
        sessionGeneration: generation,
        sequence: ++sequence,
        payload: payload,
      ),
    );

    setUp(() {
      sequence = 0;
      pair = InMemoryBridgeConnection.createPair();
      session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 10,
      );
    });
    tearDown(() async {
      await session.close();
      await pair.host.close();
    });

    test('advertises pushes only with runtime and runtimeEvents', () {
      final adapter = BridgeOverlayWorkspaceAdapter(session);
      expect(adapter.supportsRuntimeChanges, false);
      session.acceptHostCapabilities(['overlay.runtimeEvents']);
      expect(adapter.supportsRuntimeChanges, false);
      session.acceptHostCapabilities([
        'overlay.runtime',
        'overlay.runtimeEvents',
      ]);
      expect(adapter.supportsRuntimeChanges, true);
    });

    test('emits valid current-generation snapshots only', () async {
      final adapter = BridgeOverlayWorkspaceAdapter(session);
      final received = <OverlayRuntimeSnapshot>[];
      final subscription = adapter.runtimeChanges.listen(received.add);
      addTearDown(subscription.cancel);

      await event('overlay.runtime.changed', _payload('open'));
      await event('overlay.runtime.changed', {
        ..._payload('closed'),
        'unexpected': true,
      });
      await event('overlay.runtime.changed', _payload('nonsense'));
      await event(
        'overlay.runtime.changed',
        _payload('suppressed'),
        generation: 9,
      );
      await event('overlay.workspace.changed', _payload('closed'));
      await event('overlay.runtime.changed', _payload('closed'));
      await pumpEventQueue();

      expect(received.map((r) => r.windowState), ['open', 'closed']);
      expect(received.first.isVisible, true);
    });
  });

  group('workspace module', () {
    test('a push during a pending save updates runtime facts only', () async {
      final port = _PushPort();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      expect(module.supportsRuntimeChanges, true);

      // Before the first read there is no workspace to attach runtime to.
      port.push(_runtime('open'));
      await pumpEventQueue();
      expect(module.projection.value.available, false);

      await module.initialize();
      expect(module.projection.value.runtime.windowState, 'closed');
      port.hold = Completer<void>();
      module.updateSetting('showChat', true);
      final draft = module.projection.value;
      expect(draft.dirty, true);

      port.push(_runtime('open'));
      await pumpEventQueue();
      final after = module.projection.value;
      expect(after.runtime.windowState, 'open');
      expect(after.runtime.enabled, true);
      expect(after.dirty, true);
      expect(identical(after.settings, draft.settings), true);
      expect(identical(after.snapshot, draft.snapshot), true);
      expect(port.runtimeCalls, 1, reason: 'a push is not a read');
      port.hold!.complete();
      await pumpEventQueue();
      expect(module.projection.value.dirty, false);
      expect(module.projection.value.runtime.windowState, 'open');
    });

    test('a response overlapping a push never replaces it', () async {
      final port = _PushPort();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();

      final pending = Completer<OverlayRuntimeSnapshot>();
      port.nextRuntime = pending;
      final sync = module.synchronize();
      await pumpEventQueue();
      port.push(_runtime('open'));
      await pumpEventQueue();
      pending.complete(_runtime('closed'));
      await sync;
      expect(module.projection.value.runtime.windowState, 'open');

      // Without an overlapping push the response is still authoritative.
      await module.synchronize();
      expect(module.projection.value.runtime.windowState, 'closed');
    });

    test('a push during the workspace read does not abort the sync', () async {
      final port = _PushPort();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.initialize();

      final read = Completer<OverlayWorkspaceSnapshot>();
      port.nextRead = read;
      port.revision = 2;
      final sync = module.synchronize();
      await pumpEventQueue();
      port.push(_runtime('open'));
      await pumpEventQueue();
      read.complete(port.snapshot());
      await sync;
      expect(module.projection.value.snapshot!.revision, 2);
    });

    test('dispose cancels the subscription', () async {
      final port = _PushPort();
      final module = OverlayWorkspaceModule(port);
      expect(port.changes.hasListener, true);
      module.dispose();
      await pumpEventQueue();
      expect(port.changes.hasListener, false);
    });

    test('ports without pushes report no support', () {
      final module = OverlayWorkspaceModule(_PlainPort());
      addTearDown(module.dispose);
      expect(module.supportsRuntimeChanges, false);
    });
  });
}

class _PlainPort implements OverlayWorkspacePort {
  int revision = 1;
  int runtimeCalls = 0;
  Completer<OverlayRuntimeSnapshot>? nextRuntime;
  Completer<OverlayWorkspaceSnapshot>? nextRead;

  OverlayWorkspaceSnapshot snapshot() => OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: 'ready',
    activePresetId: 'default',
    renderMode: 'NativeComposition',
    appearances: const [],
    presets: [
      OverlayWorkspacePreset(
        id: 'default',
        name: '默认预设',
        isActive: true,
        storageState: 'ready',
        settings: settings(),
        layout: const [],
      ),
    ],
    settings: settings(),
    layout: const [],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Ctrl+Shift+O',
      enabled: true,
      runtimeState: 'registered',
    ),
  );

  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    final pending = nextRead;
    nextRead = null;
    return pending == null ? snapshot() : pending.future;
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    await hold?.future;
    return OverlayWorkspaceWriteResult.completed(snapshot());
  }

  Completer<void>? hold;

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    runtimeCalls++;
    final pending = nextRuntime;
    nextRuntime = null;
    return pending == null ? _runtime('closed') : pending.future;
  }

  @override
  Future<void> close() async {}
}

final class _PushPort extends _PlainPort implements OverlayRuntimeChangePort {
  final changes = StreamController<OverlayRuntimeSnapshot>.broadcast();
  void push(OverlayRuntimeSnapshot runtime) => changes.add(runtime);

  @override
  bool get supportsRuntimeChanges => true;
  @override
  Stream<OverlayRuntimeSnapshot> get runtimeChanges => changes.stream;
}
