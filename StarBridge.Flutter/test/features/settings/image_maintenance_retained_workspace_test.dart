import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/settings/image_cache_maintenance_controller.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../../design_system/interaction/interaction_batch3do_test.dart'
    show BridgeFixture, scopedApp, size, loadFonts;
import '../communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload, mediaChunk;
import '../communities/community_unread_attention_test.dart' show UnreadPort;

class MaintenanceHost extends BridgeFixture implements NativeHostLease {
  final _roots = <int>{};
  Future<void> finishStartup(WidgetTester tester) async {
    await tester.pump();
    for (var index = 0; index < requests.length; index++) {
      if (requests[index].name == 'account.getCurrent' && _roots.add(index)) {
        await reply(index, {'schemaVersion': 1, 'state': 'signedOut'});
        await tester.pump();
      }
    }
  }

  final _terminated = Completer<NativeHostTermination>();
  @override
  Future<NativeHostTermination> get terminated => _terminated.future;
  bool _closed = false;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await super.close();
  }
}

class MaintenanceWorkspacePort extends WorkspaceTestPort {
  final bytes = Uint8List.fromList([1, 2, 3]);
  int mediaReads = 0;
  int decorationReads = 0;
  int active = 0, peak = 0;
  Completer<void>? decorationGate;
  Completer<void>? logoGate, bannerGate;
  String? logoFailure;
  String? decorationFailure;
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    mediaReads++;
    active++;
    if (active > peak) peak = active;
    try {
      if (memberRef == null) {
        decorationReads++;
        final gate = (kind == 'logo' ? logoGate : bannerGate) ?? decorationGate;
        final failure = kind == 'logo'
            ? logoFailure ?? decorationFailure
            : decorationFailure;
        if (gate != null) await gate.future;
        if (failure != null) throw CommunityFailure(failure);
      }
      return mediaChunk(bytes, offset, kind: kind, memberRef: memberRef);
    } finally {
      active--;
    }
  }
}

class MaintenanceDeliveryPort extends UnreadPort {
  final bytes = Uint8List.fromList([1, 2, 3]);
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    final row = workspacePayload(target: targetRef, query: query);
    row['hasLogo'] = true;
    return CommunityWorkspace.parse(row);
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => mediaChunk(bytes, offset, kind: kind, memberRef: memberRef);
}

class MaintenanceScene {
  final host = MaintenanceHost();
  final preferences = InMemoryAppPreferences();
  final port = MaintenanceWorkspacePort();
  late final composition = AppComposition.forConnectedProduct(
    nativeHost: host,
    preferences: preferences,
    windowChrome: InMemoryWindowChrome(),
  );
  Future<void> initialize(WidgetTester t) async {
    composition;
    await host.finishStartup(t);
  }

  int get clearRequest => host.requests.indexWhere(
    (request) => request.name == 'diagnostics.clearImageCache',
  );
  Future<void> reply(Map<String, dynamic> payload) =>
      host.reply(clearRequest, payload);
  Future<void> close(WidgetTester t) async {
    for (final gate in {port.decorationGate, port.logoGate, port.bannerGate}) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await host.finishStartup(t);
    await t.pumpWidget(const SizedBox.shrink());
    composition.dispose();
    await t.pump();
    await host.close();
    await port.changes.close();
    preferences.dispose();
    await t.pump(Duration.zero);
  }
}

Future<CommunityWorkspaceController> populated(
  AppComposition composition,
  MaintenanceWorkspacePort port,
  String key,
) async {
  port.reader = (target, query, offset) async {
    final payload = workspacePayload(target: target, query: query);
    payload['hasLogo'] = true;
    payload['hasBanner'] = true;
    (payload['members'] as List).first['hasAvatar'] = true;
    return CommunityWorkspace.parse(payload);
  };
  final model = composition.communities.workspaceSession.obtain(
    port,
    key * 32,
    key,
  );
  await model.load();
  expect(model.image('logo'), orderedEquals(port.bytes));
  expect(model.image('banner'), orderedEquals(port.bytes));
  expect(model.image('b' * 32), orderedEquals(port.bytes));
  return model;
}

Widget settings(AppComposition composition) => scopedApp(
  Builder(
    builder: (context) =>
        composition.features.byRoute('/settings').buildDestination(context),
  ),
  InteractionSuite.values.first,
  locale: const Locale('zh'),
);

Future<void> openMaintenance(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-section-diagnostics')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('maintenance-clear-cache')));
  await tester.pumpAndSettle();
}

Future<void> confirmClear(WidgetTester t) async {
  await t.tap(find.byKey(const Key('maintenance-clear-cache')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('maintenance-confirm-execute')));
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  testWidgets('production maintenance clears current and retained organization '
      'images on count zero while keeping metadata, view and avatars', (
    t,
  ) async {
    size(t, const Size(1600, 1100));
    final host = MaintenanceHost();
    final preferences = InMemoryAppPreferences();
    final composition = AppComposition.forConnectedProduct(
      nativeHost: host,
      preferences: preferences,
      windowChrome: InMemoryWindowChrome(),
    );
    await host.finishStartup(t);
    final port = MaintenanceWorkspacePort();
    final retained = await populated(composition, port, 'a');
    final current = await populated(composition, port, 'c');
    retained.query = 'retained filter';
    retained.selectedSection = 'chat';
    final metadata = retained.workspace;
    var disposed = false;
    Future<void> disposeFixture() async {
      if (disposed) return;
      disposed = true;
      await host.finishStartup(t);
      await t.pumpWidget(const SizedBox.shrink());
      composition.dispose();
      await t.pump();
      await host.close();
      await port.changes.close();
      preferences.dispose();
    }

    addTearDown(disposeFixture);
    await t.pumpWidget(settings(composition));
    await t.pumpAndSettle();
    await openMaintenance(t);
    await t.tap(find.byKey(const Key('maintenance-clear-cache')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('maintenance-confirm-execute')));
    await t.pump();
    final index = host.requests.indexWhere(
      (request) => request.name == 'diagnostics.clearImageCache',
    );
    expect(index, greaterThanOrEqualTo(0));
    await host.reply(index, {'schemaVersion': 1, 'count': 0});
    await t.pumpAndSettle();
    for (final model in [retained, current]) {
      expect(
        model.image('logo'),
        isNull,
        reason: 'The real maintenance route must retire retained RAM logos.',
      );
      expect(model.image('banner'), isNull);
      expect(model.image('b' * 32), orderedEquals(port.bytes));
      expect(model.error, isNull);
    }
    expect(retained.workspace, same(metadata));
    expect(retained.query, 'retained filter');
    expect(retained.selectedSection, 'chat');
    expect(
      host.requests.where(
        (request) => request.name == 'diagnostics.clearImageCache',
      ),
      hasLength(1),
    );
    await disposeFixture();
  });

  testWidgets('settings leave and reentry share the running purge; newly '
      'retained owners pause decoration reads and keep avatars', (t) async {
    size(t, const Size(1600, 1100));
    final scene = MaintenanceScene();
    await scene.initialize(t);
    try {
      final original = await populated(scene.composition, scene.port, 'a');
      await t.pumpWidget(settings(scene.composition));
      await t.pumpAndSettle();
      await openMaintenance(t);
      await confirmClear(t);
      expect(scene.composition.imageMaintenance.busy, true);
      expect(original.image('logo'), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      final before = scene.port.decorationReads;
      // Use the same actual account-scoped session while the route is absent.
      final next = scene.composition.communities.workspaceSession.obtain(
        scene.port,
        'c' * 32,
        'c',
      );
      await next.load();
      expect(next.workspace, isNotNull);
      expect(next.image('b' * 32), orderedEquals(scene.port.bytes));
      expect(scene.port.decorationReads, before);
      await t.pumpWidget(settings(scene.composition));
      await t.pump();
      await t.tap(find.byKey(const Key('settings-section-diagnostics')));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const Key('maintenance-clear-cache')),
            )
            .onPressed,
        isNull,
      );
      expect(
        scene.host.requests.where(
          (request) => request.name == 'diagnostics.clearImageCache',
        ),
        hasLength(1),
      );
      await scene.reply({'schemaVersion': 1, 'count': 0});
      await t.pumpAndSettle();
      expect(scene.composition.imageMaintenance.result, 'cleared');
      expect(original.image('logo'), isNull);
      expect(next.image('logo'), isNull);
    } finally {
      await scene.close(t);
    }
  });

  for (final failure in <String?>[
    null,
    'unavailable',
    'refreshRequired',
    'notAllowed',
    'identityUnavailable',
  ]) {
    testWidgets('late decoration $failure cannot refill after purge; '
        'current access refusal still revokes metadata', (t) async {
      final scene = MaintenanceScene();
      await scene.initialize(t);
      try {
        final model = await populated(scene.composition, scene.port, 'a');
        final avatar = model.image('b' * 32);
        // Replace only decorations through the existing refresh path and hold
        // their actual transport. The avatar stays a completed positive control.
        final gate = scene.port.decorationGate = Completer<void>();
        scene.port.decorationFailure = failure;
        final loading = model.load(refreshImages: {'logo', 'banner'});
        await t.pump();
        final metadata = model.workspace;
        expect(scene.port.active, 2);
        final clear = scene.composition.imageMaintenance.clear();
        await t.pump();
        expect(scene.port.active, 2);
        await scene.reply({'schemaVersion': 1, 'count': 0});
        await clear;
        expect(
          scene.port.active,
          2,
          reason: 'Logical maintenance completion cannot free physical IO.',
        );
        gate.complete();
        await loading;
        if (failure == 'notAllowed' || failure == 'identityUnavailable') {
          expect(model.workspace, isNull);
          expect(model.error, failure);
        } else {
          expect(model.workspace, same(metadata));
          expect(model.image('logo'), isNull);
          expect(model.image('banner'), isNull);
          expect(model.image('b' * 32), same(avatar));
          expect(model.error, isNull);
          scene.port.decorationGate = null;
          scene.port.decorationFailure = null;
          final before = scene.port.decorationReads;
          await model.enter(model.targetRef);
          expect(scene.port.decorationReads, before + 2);
          expect(model.image('logo'), orderedEquals(scene.port.bytes));
        }
        expect(scene.port.peak, lessThanOrEqualTo(3));
      } finally {
        await scene.close(t);
      }
    });
  }

  for (final receipt in <Map<String, dynamic>>[
    {'schemaVersion': 1, 'count': -1},
    {'schemaVersion': 1, 'count': 0, 'unexpected': true},
    {'schemaVersion': 2, 'count': 0},
  ]) {
    testWidgets('invalid receipt $receipt remains unconfirmed after route '
        'disposal and permits an explicit fresh read', (t) async {
      final scene = MaintenanceScene();
      await scene.initialize(t);
      try {
        final model = await populated(scene.composition, scene.port, 'a');
        final clearing = scene.composition.imageMaintenance.clear();
        final failed = expectLater(clearing, throwsStateError);
        await t.pump();
        await scene.reply(receipt);
        await failed;
        expect(scene.composition.imageMaintenance.busy, false);
        expect(scene.composition.imageMaintenance.result, 'failed');
        expect(model.workspace, isNotNull);
        expect(model.image('logo'), isNull);
        await model.enter(model.targetRef);
        expect(model.image('logo'), orderedEquals(scene.port.bytes));
        expect(
          scene.host.requests.where(
            (request) => request.name == 'diagnostics.clearImageCache',
          ),
          hasLength(1),
        );
      } finally {
        await scene.close(t);
      }
    });
  }

  testWidgets('metadata admitted before purge cannot admit stale decoration '
      'references after it; a fresh entered read can renew them', (t) async {
    final scene = MaintenanceScene();
    await scene.initialize(t);
    try {
      final model = await populated(scene.composition, scene.port, 'a');
      final reader = scene.port.reader, metadata = model.workspace!;
      final held = Completer<CommunityWorkspace>();
      scene.port.reader = (_, _, _) => held.future;
      final reading = model.load(silent: true);
      await t.pump();
      final clear = scene.composition.imageMaintenance.clear();
      await t.pump();
      await scene.reply({'schemaVersion': 1, 'count': 0});
      await clear;
      final before = scene.port.decorationReads;
      held.complete(metadata);
      await reading;
      expect(model.workspace, same(metadata));
      expect(model.image('logo'), isNull);
      expect(
        scene.port.decorationReads,
        before,
        reason: 'Old metadata is displayable but cannot re-admit old media.',
      );
      scene.port.reader = reader;
      await model.enter(model.targetRef);
      expect(model.image('logo'), orderedEquals(scene.port.bytes));
    } finally {
      await scene.close(t);
    }
  });

  testWidgets('enter while retired physical batch remains cannot exceed the '
      'same worker budget even if metadata needs renewal', (t) async {
    final scene = MaintenanceScene();
    await scene.initialize(t);
    try {
      final model = await populated(scene.composition, scene.port, 'a');
      final gate = scene.port.decorationGate = Completer<void>();
      final old = model.load(refreshImages: {'logo', 'banner'});
      await t.pump();
      expect(scene.port.active, 2);
      final clear = scene.composition.imageMaintenance.clear();
      await t.pump();
      await scene.reply({'schemaVersion': 1, 'count': 0});
      await clear;
      final before = scene.port.decorationReads;
      final entered = model.enter(model.targetRef);
      await t.pump();
      expect(scene.port.decorationReads, lessThanOrEqualTo(before + 1));
      expect(scene.port.active, lessThanOrEqualTo(3));
      scene.port.decorationGate = null;
      gate.complete();
      await Future.wait([old, entered]);
      expect(scene.port.peak, lessThanOrEqualTo(3));
      expect(model.image('logo'), orderedEquals(scene.port.bytes));
    } finally {
      await scene.close(t);
    }
  });

  testWidgets('real current refusal revokes immediately while its retired '
      'peer still physically owns the batch', (t) async {
    final scene = MaintenanceScene();
    await scene.initialize(t);
    try {
      final model = await populated(scene.composition, scene.port, 'a');
      final logo = scene.port.logoGate = Completer<void>();
      final banner = scene.port.bannerGate = Completer<void>();
      scene.port.logoFailure = 'notAllowed';
      var finished = false;
      final reading = model
          .load(refreshImages: {'logo', 'banner'})
          .then((_) => finished = true);
      await t.pump();
      final clear = scene.composition.imageMaintenance.clear();
      await t.pump();
      await scene.reply({'schemaVersion': 1, 'count': 0});
      await clear;
      logo.complete();
      await t.pump(Duration.zero);
      expect(model.workspace, isNull);
      expect(model.error, 'notAllowed');
      expect(scene.port.active, 1);
      expect(finished, false);
      banner.complete();
      await reading;
      expect(scene.port.active, 0);
    } finally {
      await scene.close(t);
    }
  });

  testWidgets('timeout and its late positive receipt never announce success '
      'or replay Native maintenance', (t) async {
    final scene = MaintenanceScene();
    await scene.initialize(t);
    try {
      final model = await populated(scene.composition, scene.port, 'a');
      final clear = scene.composition.imageMaintenance.clear();
      final failed = expectLater(clear, throwsA(isA<BridgeTimeoutException>()));
      await t.pump(const Duration(seconds: 16));
      await failed;
      expect(scene.composition.imageMaintenance.result, 'failed');
      expect(scene.composition.imageMaintenance.busy, false);
      await scene.reply({'schemaVersion': 1, 'count': 0});
      await t.pump();
      expect(scene.composition.imageMaintenance.result, 'failed');
      expect(model.workspace, isNotNull);
      expect(model.image('logo'), isNull);
      expect(
        scene.host.requests.where(
          (request) => request.name == 'diagnostics.clearImageCache',
        ),
        hasLength(1),
      );
    } finally {
      await scene.close(t);
    }
  });

  test('maintenance includes an evicted delivery owner and preserves its '
      'unknown send and next draft without replay', () async {
    final host = MaintenanceHost(), port = MaintenanceDeliveryPort();
    final session = CommunityWorkspaceSession(capacity: 1);
    final maintenance = ImageCacheMaintenanceController(
      host.session,
      caches: [session],
    );
    try {
      final owner = session.obtain(port, 'a' * 32, 'a');
      await owner.enter(owner.targetRef);
      final chat = owner.chat!;
      await chat.refresh();
      port.chat.sendResult = const CommunityChatSendOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      chat.updateDraft('submitted fixture');
      await chat.submit();
      chat.updateDraft('next unsaved fixture');
      session.obtain(port, 'c' * 32, 'c');
      final metadata = owner.workspace, pending = chat.localMessages.single;
      final clear = maintenance.clear();
      await Future<void>.delayed(Duration.zero);
      await host.reply(0, {'schemaVersion': 1, 'count': 0});
      await clear;
      expect(owner.image('logo'), isNull);
      final restored = session.obtain(port, 'a' * 32, 'a');
      expect(restored, same(owner));
      expect(restored.workspace, same(metadata));
      expect(restored.chat, same(chat));
      expect(chat.localMessages.single, same(pending));
      expect(chat.sendUncertain, true);
      expect(chat.draft, 'next unsaved fixture');
      expect(port.chat.sends, hasLength(1));
    } finally {
      maintenance.dispose();
      session.clear();
      await Future<void>.delayed(Duration.zero);
      await port.close();
      await host.close();
    }
  });
}
